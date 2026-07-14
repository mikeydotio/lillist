import Testing
import Foundation
@testable import LillistCore

@Suite("WidgetSnapshotBuilder — regeneration")
struct WidgetSnapshotBuilderTests {
    /// Matches every active (non-trashed, non-archived) task: an empty `.all`
    /// group compiles to TRUEPREDICATE, conjoined with the implicit
    /// `deletedAt == nil && archivedAt == nil` rules.
    private func allTasksGroup() -> PredicateGroup {
        .init(combinator: .all, predicates: [])
    }

    private func todoGroup() -> PredicateGroup {
        .init(combinator: .all, predicates: [
            .leaf(.init(field: .status, op: .is, value: .statusSet([.todo])))
        ])
    }

    private func tempSnapshotStore() -> (store: WidgetSnapshotStore, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetSnapshotBuilderTests-\(UUID().uuidString)", isDirectory: true)
        return (WidgetSnapshotStore(rootDirectory: dir), dir)
    }

    @Test("regenerate writes a per-filter snapshot and an index")
    func regenerateWritesSnapshotAndIndex() async throws {
        let controller = try await TestStore.make()
        let tasks = TaskStore(persistence: controller)
        let filters = SmartFilterStore(persistence: controller)
        _ = try await tasks.create(title: "Submit feedback")
        _ = try await tasks.create(title: "Renew passport")
        let filterID = try await filters.create(name: "Todayish", group: todoGroup())

        let (snapStore, dir) = tempSnapshotStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let builder = WidgetSnapshotBuilder(smartFilterStore: filters, snapshotStore: snapStore)
        await builder.regenerate()

        let snap = try #require(snapStore.read(filterID: filterID))
        #expect(snap.filterName == "Todayish")
        #expect(snap.totalCount == 2)
        #expect(snap.openCount == 2)
        #expect(snap.tasks.count == 2)
        #expect(Set(snap.tasks.map(\.title)) == ["Submit feedback", "Renew passport"])

        let index = try #require(snapStore.readIndex())
        #expect(index.filters.map(\.id) == [filterID])
    }

    @Test("openCount excludes closed tasks; totalCount includes them")
    func openCountExcludesClosed() async throws {
        let controller = try await TestStore.make()
        let tasks = TaskStore(persistence: controller)
        let filters = SmartFilterStore(persistence: controller)
        let a = try await tasks.create(title: "A")
        _ = try await tasks.create(title: "B")
        let c = try await tasks.create(title: "C")
        try await tasks.transition(id: a, to: .closed)
        try await tasks.transition(id: c, to: .closed)
        let filterID = try await filters.create(name: "All", group: allTasksGroup())

        let (snapStore, dir) = tempSnapshotStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let builder = WidgetSnapshotBuilder(smartFilterStore: filters, snapshotStore: snapStore)
        await builder.regenerate()

        let snap = try #require(snapStore.read(filterID: filterID))
        #expect(snap.totalCount == 3)
        #expect(snap.openCount == 1)
    }

    private func openOnlyGroup() -> PredicateGroup {
        .init(combinator: .all, predicates: [
            .leaf(.init(field: .status, op: .isNot, value: .statusSet([.closed])))
        ])
    }

    @Test("a task completed today sinks to the bottom of an exclude-closed filter")
    func completedTaskSinksToBottom() async throws {
        let controller = try await TestStore.make()
        let tasks = TaskStore(persistence: controller)
        let filters = SmartFilterStore(persistence: controller)
        _ = try await tasks.create(title: "X")
        let y = try await tasks.create(title: "Y")
        _ = try await tasks.create(title: "Z")
        try await tasks.transition(id: y, to: .closed)   // completed today
        let filterID = try await filters.create(name: "Open", group: openOnlyGroup())

        let (snapStore, dir) = tempSnapshotStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let builder = WidgetSnapshotBuilder(smartFilterStore: filters, snapshotStore: snapStore)
        await builder.regenerate()

        let snap = try #require(snapStore.read(filterID: filterID))
        // Y is excluded by the filter yet retained (grace) — and pinned last.
        #expect(snap.tasks.count == 3)
        #expect(snap.tasks.last?.title == "Y")
        #expect(snap.tasks.last?.status == .closed)
        #expect(snap.openCount == 2)
        #expect(Set(snap.tasks.dropLast().map(\.title)) == ["X", "Z"])
    }

    @Test("regenerate writes the No-Filter sentinel snapshot (open first, done at bottom)")
    func regenerateWritesSentinel() async throws {
        let controller = try await TestStore.make()
        let tasks = TaskStore(persistence: controller)
        let filters = SmartFilterStore(persistence: controller)
        _ = try await tasks.create(title: "Open one")
        let done = try await tasks.create(title: "Done one")
        try await tasks.transition(id: done, to: .closed)

        let (snapStore, dir) = tempSnapshotStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let builder = WidgetSnapshotBuilder(smartFilterStore: filters, snapshotStore: snapStore)
        await builder.regenerate()

        let snap = try #require(snapStore.read(filterID: WidgetSnapshot.unfilteredID))
        #expect(snap.isUnfiltered)
        #expect(snap.filterName == "")
        #expect(snap.tasks.first?.title == "Open one")
        #expect(snap.tasks.last?.title == "Done one")      // completed today, sunk to bottom
        #expect(snap.openCount == 1)
    }

    @Test("rows are capped at rowCap; totalCount reflects the full match set")
    func rowCap() async throws {
        let controller = try await TestStore.make()
        let tasks = TaskStore(persistence: controller)
        let filters = SmartFilterStore(persistence: controller)
        for i in 0..<5 { _ = try await tasks.create(title: "Task \(i)") }
        let filterID = try await filters.create(name: "Many", group: allTasksGroup())

        let (snapStore, dir) = tempSnapshotStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let builder = WidgetSnapshotBuilder(smartFilterStore: filters, snapshotStore: snapStore, rowCap: 3)
        await builder.regenerate()

        let snap = try #require(snapStore.read(filterID: filterID))
        #expect(snap.tasks.count == 3)
        #expect(snap.totalCount == 5)
    }

    @Test("advancing an open task's status does not move it in the No-Filter sentinel")
    func sentinelOrderStableUnderStatusChange() async throws {
        let controller = try await TestStore.make()
        let tasks = TaskStore(persistence: controller)
        let filters = SmartFilterStore(persistence: controller)
        _ = try await tasks.create(title: "A")           // creation order == position order
        let b = try await tasks.create(title: "B")
        _ = try await tasks.create(title: "C")
        try await tasks.transition(id: b, to: .started)  // bumps modifiedAt; must NOT reorder

        let (snapStore, dir) = tempSnapshotStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let builder = WidgetSnapshotBuilder(smartFilterStore: filters, snapshotStore: snapStore)
        await builder.regenerate()

        let snap = try #require(snapStore.read(filterID: WidgetSnapshot.unfilteredID))
        #expect(snap.tasks.map(\.title) == ["A", "B", "C"])
        #expect(snap.openCount == 3)
    }

    @Test("advancing status does not reorder a modifiedAt-sorted saved filter's open rows")
    func savedFilterVolatileSortStableUnderStatusChange() async throws {
        let controller = try await TestStore.make()
        let tasks = TaskStore(persistence: controller)
        let filters = SmartFilterStore(persistence: controller)
        _ = try await tasks.create(title: "A")
        let b = try await tasks.create(title: "B")
        _ = try await tasks.create(title: "C")
        let filterID = try await filters.create(
            name: "Recently touched",
            group: openOnlyGroup(),
            sortField: .modifiedAt,
            sortAscending: false
        )
        try await tasks.transition(id: b, to: .started)

        let (snapStore, dir) = tempSnapshotStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let builder = WidgetSnapshotBuilder(smartFilterStore: filters, snapshotStore: snapStore)
        await builder.regenerate()

        let snap = try #require(snapStore.read(filterID: filterID))
        // A modifiedAt sort would lift B (just advanced) to the top; the volatile
        // fallback pins the open slice to position order instead.
        #expect(snap.tasks.map(\.title) == ["A", "B", "C"])
        #expect(snap.openCount == 3)
    }

    @Test("a saved filter's stable custom sort is preserved (not forced to position order)")
    func savedFilterStableSortPreserved() async throws {
        let controller = try await TestStore.make()
        let tasks = TaskStore(persistence: controller)
        let filters = SmartFilterStore(persistence: controller)
        // Creation (== position) order deliberately differs from title order.
        _ = try await tasks.create(title: "Cherry")      // position 0
        let apple = try await tasks.create(title: "Apple")  // position 1
        _ = try await tasks.create(title: "Banana")      // position 2
        let filterID = try await filters.create(
            name: "Alphabetical",
            group: openOnlyGroup(),
            sortField: .title,
            sortAscending: true
        )
        try await tasks.transition(id: apple, to: .started)  // title unchanged

        let (snapStore, dir) = tempSnapshotStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let builder = WidgetSnapshotBuilder(smartFilterStore: filters, snapshotStore: snapStore)
        await builder.regenerate()

        let snap = try #require(snapStore.read(filterID: filterID))
        // Title is stable under a status transition, so the configured sort wins
        // (position order would be Cherry, Apple, Banana).
        #expect(snap.tasks.map(\.title) == ["Apple", "Banana", "Cherry"])
        #expect(snap.openCount == 3)
    }
}
