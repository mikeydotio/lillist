import Testing
import Foundation
@testable import LillistCore

/// data-sync-hardening `X5`, built on the `1c` Keystone harness's two-
/// `PersistenceController`-one-file pattern (`MultiProcessStoreHarnessTests`)
/// to prove the fix holds across genuinely separate controllers/contexts —
/// the real cross-process topology (main app vs. widget extension) — not
/// just "the same builder queried twice."
///
/// **Deviation from the plan doc's §5 sketch, recorded here per the plan
/// doc's own deviations-tracker convention:** the doc originally framed this
/// as reproducing genuine same-device cross-process *staleness* (controller
/// B holding an outdated, unrefreshed view of controller A's very recent
/// write). Empirically probed against this harness (two separate
/// `PersistenceController`s over one on-disk file, in one SPM test process):
/// a **first-time** fetch of a row-existence query (`SmartFilterStore.list()`)
/// on either controller always reflects the other's already-committed writes
/// immediately, with or without `refreshAllObjects()` — confirmed by
/// replaying `MultiProcessStoreHarnessTests.writeFromA_visibleToB` itself
/// with its `refreshAllObjects()` call removed, which still passed. SQLite's
/// WAL visibility has no meaningful propagation delay between two
/// independently-constructed containers sharing one file on one machine —
/// `refreshAllObjects()` matters for re-syncing an *already-fetched,
/// registered* object's stale property values, not for row-existence
/// queries against rows a context has never touched before. Genuine
/// cross-process lag of that specific shape isn't reproducible this way, so
/// this suite instead proves the stronger, mechanism-independent invariant
/// the fix actually provides: pruning authority belongs *only* to
/// `regenerateAuthoritatively()`, never to `regenerate(filterIDs:)` — even
/// when the additive caller's own read is *fully correct* (not stale at
/// all, via a genuinely separate controller) about a filter being gone.
/// Under the pre-fix code this exact scenario still deletes the now-orphaned
/// filter's own on-disk snapshot as a side effect of a narrow, single-filter
/// cache-miss call that never should have had prune authority — proven
/// below by asserting it survives instead.
@Suite("WidgetSnapshotBuilder — X5 cross-process prune authority")
struct WidgetSnapshotBuilderX5CrossProcessTests {
    private func tempStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetSnapshotBuilderX5CrossProcessTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Lillist.sqlite")
    }

    private func tempSnapshotStore() -> (store: WidgetSnapshotStore, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetSnapshotBuilderX5CrossProcessTests-snap-\(UUID().uuidString)", isDirectory: true)
        return (WidgetSnapshotStore(rootDirectory: dir), dir)
    }

    private func todoGroup() -> PredicateGroup {
        .init(combinator: .all, predicates: [
            .leaf(.init(field: .status, op: .is, value: .statusSet([.todo])))
        ])
    }

    @Test("a widget-side controller's additive cache-miss rebuild must not prune a stale snapshot, even when its own (unstale, cross-controller) read agrees the filter is gone")
    func widgetControllerNeverPrunesAcrossControllers() async throws {
        let storeURL = tempStoreURL()
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Two independent PersistenceControllers over one on-disk file — the
        // real cross-process topology, per the `1c` Keystone harness.
        let controllerA = try await PersistenceController(
            configuration: .onDisk(url: storeURL, syncMode: .localOnly),
            transactionAuthor: PersistenceController.localTransactionAuthor
        )
        let controllerB = try await PersistenceController(
            configuration: .onDisk(url: storeURL, syncMode: .localOnly),
            transactionAuthor: PersistenceController.widgetTransactionAuthor
        )

        // The app: creates a filter, writes its snapshot authoritatively —
        // the real `WidgetRefreshController` call shape.
        let tasksA = TaskStore(persistence: controllerA)
        _ = try await tasksA.create(title: "Submit feedback")
        let filtersA = SmartFilterStore(persistence: controllerA)
        let filterID = try await filtersA.create(name: "Todayish", group: todoGroup())

        let (snapStore, dir) = tempSnapshotStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let builderA = WidgetSnapshotBuilder(smartFilterStore: filtersA, snapshotStore: snapStore)
        await builderA.regenerateAuthoritatively()
        #expect(snapStore.read(filterID: filterID) != nil)

        // The filter is later deleted from the app side.
        try await filtersA.delete(id: filterID)

        // Controller B (the widget extension, a genuinely separate
        // controller/context) is asked to rebuild its cold cache for that
        // same filter id — the `FilterTimelineProvider` cache-miss call
        // shape. Its own fresh read correctly agrees the filter is gone
        // (confirmed, not assumed — see the suite doc comment on why this
        // harness can't force B to be *wrong*).
        let filtersB = SmartFilterStore(persistence: controllerB)
        let listAsSeenByB = try await filtersB.list()
        #expect(listAsSeenByB.contains { $0.id == filterID } == false)

        let builderB = WidgetSnapshotBuilder(smartFilterStore: filtersB, snapshotStore: snapStore)
        await builderB.regenerate(filterIDs: [filterID])

        #expect(
            snapStore.read(filterID: filterID) != nil,
            "a non-authoritative, single-filter cache-miss rebuild must never prune — not even a now-orphaned snapshot for the filter it was itself scoped to"
        )
    }
}
