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

/// Polls `condition` until it's true or `timeout` elapses, instead of a
/// single fixed `Task.sleep` margin — a fixed margin is exactly the
/// documented parallel-test-flake shape (`CLAUDE.md`'s `--parallel`
/// CPU-contention note): under `swift test --parallel --num-workers 2` with
/// 250+ suites running concurrently, scheduling delay alone can exceed a
/// margin that's comfortable in isolation. Polling only ever waits as long
/// as actually needed, and stays correct (just slower) under contention
/// rather than flaking.
private func waitUntil(
    timeout: Duration = .seconds(5),
    interval: Duration = .milliseconds(10),
    _ condition: () -> Bool
) async {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return }
        try? await Task.sleep(for: interval)
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
        let builder = WidgetSnapshotBuilder(smartFilterStore: filters, taskLookup: tasks, snapshotStore: snapStore)
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

        // Poll on the reload, not the snapshot write — regenerateAuthoritatively()
        // writes the snapshot partway through its own body, strictly before
        // it returns and `reloadAllTimelines()` runs; polling on the write
        // alone can observe that intermediate state and race the reload
        // under contention. The reload always happens last, so waiting for
        // it guarantees the snapshot is already settled too.
        await waitUntil { reloader.reloadCount >= 1 }

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
        let builder = WidgetSnapshotBuilder(smartFilterStore: filters, taskLookup: tasks, snapshotStore: snapStore)
        let reloader = RecordingReloader()
        let refresh = await WidgetRefreshController(
            persistence: controller,
            builder: builder,
            reloader: reloader,
            // LIL-84: widened from 100ms (with 20ms gaps, ~5x headroom) to
            // 500ms (with 5ms gaps, ~20x headroom) — this test flaked under
            // `swift test --parallel` contention when a save's own
            // `Task.sleep(for: .milliseconds(20))` occasionally overshot
            // far enough that an EARLIER debounce timer fired before a
            // LATER save landed, coalescing into more than one reload (or
            // reflecting fewer than 5 tasks) instead of the one this test
            // asserts. The debounce-coalescing MECHANISM this test proves
            // is unchanged; only the timing margin needed extra headroom.
            debounce: .milliseconds(500)
        )
        await refresh.start()

        for i in 0..<5 {
            _ = try await tasks.create(title: "Task \(i)")
            // Well under the debounce window, so each save restarts it
            // rather than letting it fire.
            try await Task.sleep(for: .milliseconds(5))
        }

        // Poll on the reload (see the previous test's comment for why not
        // the snapshot write) rather than a fixed post-burst margin.
        await waitUntil { reloader.reloadCount >= 1 }

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
        let builder = WidgetSnapshotBuilder(smartFilterStore: filters, taskLookup: tasks, snapshotStore: snapStore)
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
        // Asserting an absence has no positive signal to poll for — waiting
        // longer only ever strengthens this claim (a stopped controller
        // can't un-stop itself under contention), so a generous fixed
        // margin is safe here, unlike the positive-signal tests above.
        try await Task.sleep(for: .milliseconds(500))

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
        let builder = WidgetSnapshotBuilder(smartFilterStore: filters, taskLookup: tasks, snapshotStore: snapStore)
        let reloader = RecordingReloader()
        let refresh = await WidgetRefreshController(
            persistence: controller,
            builder: builder,
            reloader: reloader,
            debounce: .seconds(30) // long enough that a debounced call would never land in this test
        )
        await refresh.refreshNow()
        await waitUntil { reloader.reloadCount >= 1 }

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
        let builder = WidgetSnapshotBuilder(smartFilterStore: filters, taskLookup: tasks, snapshotStore: snapStore)
        let reloader = RecordingReloader()
        let refresh = await WidgetRefreshController(
            persistence: controller,
            builder: builder,
            reloader: reloader,
            debounce: .milliseconds(50)
        )
        await refresh.refreshNow()
        await waitUntil { reloader.reloadCount >= 1 }
        #expect(snapStore.read(filterID: filterID) != nil)

        await refresh.resetAfterDestructiveOp()

        // Awaited synchronously — the rebuild has already happened by the
        // time this returns, no extra wait needed.
        #expect(snapStore.read(filterID: filterID) != nil)
        #expect(reloader.reloadCount == 2)
    }
}
