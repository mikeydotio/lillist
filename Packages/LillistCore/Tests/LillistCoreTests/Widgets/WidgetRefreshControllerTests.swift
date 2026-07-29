import Testing
import Foundation
@testable import LillistCore

/// data-sync-hardening `X6`: `WidgetRefreshController` must rebuild the
/// snapshot cache and reload timelines in response to this process's own
/// local `viewContext` saves, not only `.NSPersistentStoreRemoteChange`
/// (which never fires for same-coordinator local writes). Proven entirely at
/// the `LillistCore` level — no WidgetKit — via the `WidgetTimelineReloading`
/// protocol seam.

/// Test double for `WidgetTimelineReloading` — records reload calls under a
/// lock, since `NotificationCenter` can invoke the controller's observers
/// from any queue before they hop onto `@MainActor`.
final class RecordingReloader: WidgetTimelineReloading, @unchecked Sendable {
    private let lock = NSLock()
    private var _reloadCount = 0

    var reloadCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _reloadCount
    }

    func reloadAllTimelines() {
        lock.lock(); defer { lock.unlock() }
        _reloadCount += 1
    }
}

@Suite("WidgetRefreshController — X6 local-save observation")
struct WidgetRefreshControllerTests {
    private func todoGroup() -> PredicateGroup {
        .init(combinator: .all, predicates: [
            .leaf(.init(field: .status, op: .is, value: .statusSet([.todo])))
        ])
    }

    private func tempSnapshotStore() -> (store: WidgetSnapshotStore, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetRefreshControllerTests-\(UUID().uuidString)", isDirectory: true)
        return (WidgetSnapshotStore(rootDirectory: dir), dir)
    }

    @Test("a local task save triggers a debounced snapshot rebuild and a timeline reload")
    func localSaveTriggersRebuildAndReload() async throws {
        let controller = try await TestStore.make()
        let tasks = TaskStore(persistence: controller)
        let filters = SmartFilterStore(persistence: controller)
        let filterID = try await filters.create(name: "Todayish", group: todoGroup())

        let (snapStore, dir) = tempSnapshotStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let builder = WidgetSnapshotBuilder(smartFilterStore: filters, snapshotStore: snapStore)
        let reloader = RecordingReloader()
        let refresh = await WidgetRefreshController(
            persistence: controller,
            builder: builder,
            reloader: reloader,
            debounce: .milliseconds(50)
        )
        await refresh.start()

        // Baseline: nothing rebuilt yet.
        #expect(snapStore.read(filterID: filterID) == nil)

        // A genuine local save on the SAME viewContext the mutation stores use.
        _ = try await tasks.create(title: "Submit feedback")

        // Wait comfortably past the debounce window.
        try await Task.sleep(for: .milliseconds(500))

        let snap = try #require(snapStore.read(filterID: filterID))
        #expect(snap.totalCount == 1, "the rebuild must reflect the task the local save just created")
        #expect(reloader.reloadCount >= 1)

        await refresh.stop()
    }

    @Test("a burst of local saves debounces into exactly one rebuild + reload")
    func burstOfSavesDebouncesToOneReload() async throws {
        let controller = try await TestStore.make()
        let tasks = TaskStore(persistence: controller)
        let filters = SmartFilterStore(persistence: controller)
        let filterID = try await filters.create(name: "Todayish", group: todoGroup())

        let (snapStore, dir) = tempSnapshotStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let builder = WidgetSnapshotBuilder(smartFilterStore: filters, snapshotStore: snapStore)
        let reloader = RecordingReloader()
        let refresh = await WidgetRefreshController(
            persistence: controller,
            builder: builder,
            reloader: reloader,
            debounce: .milliseconds(100)
        )
        await refresh.start()

        for i in 0..<5 {
            _ = try await tasks.create(title: "Task \(i)")
            // Well under the debounce window, so each save restarts it
            // rather than letting it fire.
            try await Task.sleep(for: .milliseconds(20))
        }

        try await Task.sleep(for: .milliseconds(500))

        let snap = try #require(snapStore.read(filterID: filterID))
        #expect(snap.totalCount == 5)
        #expect(reloader.reloadCount == 1, "a burst of saves must coalesce into exactly one reload")

        await refresh.stop()
    }

    @Test("stop() prevents further rebuilds from subsequent saves")
    func stopPreventsFurtherRebuilds() async throws {
        let controller = try await TestStore.make()
        let tasks = TaskStore(persistence: controller)
        let filters = SmartFilterStore(persistence: controller)
        let filterID = try await filters.create(name: "Todayish", group: todoGroup())

        let (snapStore, dir) = tempSnapshotStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let builder = WidgetSnapshotBuilder(smartFilterStore: filters, snapshotStore: snapStore)
        let reloader = RecordingReloader()
        let refresh = await WidgetRefreshController(
            persistence: controller,
            builder: builder,
            reloader: reloader,
            debounce: .milliseconds(50)
        )
        await refresh.start()
        await refresh.stop()

        _ = try await tasks.create(title: "Submit feedback")
        try await Task.sleep(for: .milliseconds(300))

        #expect(snapStore.read(filterID: filterID) == nil)
        #expect(reloader.reloadCount == 0)
    }

    @Test("refreshNow rebuilds immediately without waiting for the debounce window")
    func refreshNowIsImmediate() async throws {
        let controller = try await TestStore.make()
        let tasks = TaskStore(persistence: controller)
        let filters = SmartFilterStore(persistence: controller)
        let filterID = try await filters.create(name: "Todayish", group: todoGroup())
        _ = try await tasks.create(title: "Submit feedback")

        let (snapStore, dir) = tempSnapshotStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let builder = WidgetSnapshotBuilder(smartFilterStore: filters, snapshotStore: snapStore)
        let reloader = RecordingReloader()
        let refresh = await WidgetRefreshController(
            persistence: controller,
            builder: builder,
            reloader: reloader,
            debounce: .seconds(30) // long enough that a debounced call would never land in this test
        )
        await refresh.refreshNow()
        try await Task.sleep(for: .milliseconds(200))

        #expect(snapStore.read(filterID: filterID) != nil)
        #expect(reloader.reloadCount == 1)
    }

    @Test("X11: resetAfterDestructiveOp clears the cache before rebuilding, and awaits synchronously")
    func resetAfterDestructiveOpClearsThenRebuilds() async throws {
        let controller = try await TestStore.make()
        let tasks = TaskStore(persistence: controller)
        let filters = SmartFilterStore(persistence: controller)
        let filterID = try await filters.create(name: "Todayish", group: todoGroup())
        _ = try await tasks.create(title: "Submit feedback")

        let (snapStore, dir) = tempSnapshotStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let builder = WidgetSnapshotBuilder(smartFilterStore: filters, snapshotStore: snapStore)
        let reloader = RecordingReloader()
        let refresh = await WidgetRefreshController(
            persistence: controller,
            builder: builder,
            reloader: reloader,
            debounce: .milliseconds(50)
        )
        await refresh.refreshNow()
        try await Task.sleep(for: .milliseconds(200))
        #expect(snapStore.read(filterID: filterID) != nil)

        await refresh.resetAfterDestructiveOp()

        // Awaited synchronously — the rebuild has already happened by the
        // time this returns, no extra sleep needed.
        #expect(snapStore.read(filterID: filterID) != nil)
        #expect(reloader.reloadCount == 2)
    }
}
