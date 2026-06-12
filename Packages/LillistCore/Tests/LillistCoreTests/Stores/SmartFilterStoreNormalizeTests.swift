import Testing
import Foundation
import CoreData
@testable import LillistCore

@Suite("SmartFilterStore.normalizeIfDegenerate", .serialized)
struct SmartFilterStoreNormalizeTests {
    private func sampleGroup() -> PredicateGroup {
        .init(combinator: .all, predicates: [
            .leaf(.init(field: .status, op: .is, value: .statusSet([.todo])))
        ])
    }

    @Test("Empty table: normalize is a no-op, not a crash")
    func emptyTableNoCrash() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        // The filters-list load seam calls this before any filter exists.
        try await store.normalizeIfDegenerate()
        let rows = try await store.list()
        #expect(rows.isEmpty)
    }

    @Test("Single row: normalize is a no-op")
    func singleRowNoOp() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        let id = try await store.create(name: "Only", group: sampleGroup())
        let before = try await store.list().map(\.position)
        try await store.normalizeIfDegenerate()
        let after = try await store.list().map(\.position)
        #expect(before == after)
        _ = id
    }

    @Test("Degenerate (tied) rows: normalize compacts to strictly increasing")
    func degenerateRowsNormalized() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        let aID = try await store.create(name: "A", group: sampleGroup())
        let bID = try await store.create(name: "B", group: sampleGroup())

        // Force a tie directly via the viewContext, bypassing the public API.
        let ctx = controller.container.viewContext
        try await ctx.perform {
            let req = NSFetchRequest<SmartFilter>(entityName: "SmartFilter")
            req.predicate = NSPredicate(format: "id IN %@", [aID, bID] as CVarArg)
            let rows = (try? ctx.fetch(req)) ?? []
            for r in rows { r.position = 5.0 }
            try ctx.save()
        }

        try await store.normalizeIfDegenerate()
        let positions = try await store.list().map(\.position)
        #expect(positions.count == 2)
        #expect(positions[0] < positions[1], "Positions must be strictly increasing after normalize")
    }
}
