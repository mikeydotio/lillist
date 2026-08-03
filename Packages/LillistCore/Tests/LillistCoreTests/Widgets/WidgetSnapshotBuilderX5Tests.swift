import Testing
import Foundation
@testable import LillistCore

/// data-sync-hardening `X5`: the widget's cache-miss rebuild treated an empty
/// filter list as ground truth, pruning every snapshot the app had already
/// written. Fixed by splitting `regenerate(filterIDs:)` (additive, never
/// prunes, never writes the index) from `regenerateAuthoritatively()` (full
/// read + prune + index write — the one path trusted with deletion
/// authority). See the plan doc's §2/§3 for the empty-vs-failed semantics and
/// prune-authority rules this suite pins.
@Suite("WidgetSnapshotBuilder — X5 prune authority")
struct WidgetSnapshotBuilderX5Tests {
    private func todoGroup() -> PredicateGroup {
        .init(combinator: .all, predicates: [
            .leaf(.init(field: .status, op: .is, value: .statusSet([.todo])))
        ])
    }

    private func tempSnapshotStore() -> (store: WidgetSnapshotStore, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetSnapshotBuilderX5Tests-\(UUID().uuidString)", isDirectory: true)
        return (WidgetSnapshotStore(rootDirectory: dir), dir)
    }

    @Test("additive regenerate never prunes a snapshot for a filter its own read didn't include")
    func additiveRegenerateNeverPrunes() async throws {
        let controller = try await TestStore.make()
        let tasks = TaskStore(persistence: controller)
        let filters = SmartFilterStore(persistence: controller)
        _ = try await tasks.create(title: "Submit feedback")
        let filterID = try await filters.create(name: "Todayish", group: todoGroup())
        let otherFilterID = try await filters.create(name: "Someday", group: todoGroup())

        let (snapStore, dir) = tempSnapshotStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let builder = WidgetSnapshotBuilder(smartFilterStore: filters, taskLookup: tasks, snapshotStore: snapStore)
        await builder.regenerate()
        #expect(snapStore.read(filterID: filterID) != nil)

        // Simulate a reader whose current view no longer includes `filterID`
        // — indistinguishable, at the call site, from a stale cross-process
        // read (§2 of the plan doc). A real deletion is the simplest way to
        // produce that observable state deterministically in-process.
        try await filters.delete(id: filterID)

        // The widget's cache-miss rebuild: additive, scoped to the OTHER
        // filter only. Must not touch — let alone delete — `filterID`'s
        // snapshot as a side effect.
        await builder.regenerate(filterIDs: [otherFilterID])

        #expect(snapStore.read(filterID: filterID) != nil, "additive regenerate must never prune")
    }

    @Test("regenerateAuthoritatively prunes a snapshot for a genuinely deleted filter")
    func authoritativeRegeneratePrunesRealDeletions() async throws {
        let controller = try await TestStore.make()
        let tasks = TaskStore(persistence: controller)
        let filters = SmartFilterStore(persistence: controller)
        _ = try await tasks.create(title: "Submit feedback")
        let filterID = try await filters.create(name: "Todayish", group: todoGroup())

        let (snapStore, dir) = tempSnapshotStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let builder = WidgetSnapshotBuilder(smartFilterStore: filters, taskLookup: tasks, snapshotStore: snapStore)
        await builder.regenerateAuthoritatively()
        #expect(snapStore.read(filterID: filterID) != nil)

        try await filters.delete(id: filterID)
        await builder.regenerateAuthoritatively()

        #expect(snapStore.read(filterID: filterID) == nil, "authoritative regenerate must still reclaim real deletions")
    }

    @Test("regenerateAuthoritatively writes the picker index; additive regenerate does not")
    func onlyAuthoritativeWritesIndex() async throws {
        let controller = try await TestStore.make()
        let tasks = TaskStore(persistence: controller)
        let filters = SmartFilterStore(persistence: controller)
        let filterID = try await filters.create(name: "Todayish", group: todoGroup())

        let (snapStore, dir) = tempSnapshotStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let builder = WidgetSnapshotBuilder(smartFilterStore: filters, taskLookup: tasks, snapshotStore: snapStore)

        await builder.regenerate()
        #expect(snapStore.readIndex() == nil)

        await builder.regenerateAuthoritatively()
        let index = try #require(snapStore.readIndex())
        #expect(index.filters.map(\.id) == [filterID])
    }

    @Test("regenerateAuthoritatively against a genuinely empty store prunes every saved-filter snapshot")
    func authoritativeRegenerateOnEmptyStorePrunesEverything() async throws {
        let controller = try await TestStore.make()
        let tasks = TaskStore(persistence: controller)
        let filters = SmartFilterStore(persistence: controller)
        let filterID = try await filters.create(name: "Todayish", group: todoGroup())

        let (snapStore, dir) = tempSnapshotStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let builder = WidgetSnapshotBuilder(smartFilterStore: filters, taskLookup: tasks, snapshotStore: snapStore)
        await builder.regenerateAuthoritatively()
        #expect(snapStore.read(filterID: filterID) != nil)

        try await filters.delete(id: filterID)
        await builder.regenerateAuthoritatively()

        #expect(snapStore.read(filterID: filterID) == nil)
        // The sentinel is never pruned — a fresh/empty install still has an
        // "all tasks" widget state to render.
        #expect(snapStore.read(filterID: WidgetSnapshot.unfilteredID) != nil)
    }
}
