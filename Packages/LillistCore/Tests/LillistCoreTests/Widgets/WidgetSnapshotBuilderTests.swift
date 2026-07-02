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
}
