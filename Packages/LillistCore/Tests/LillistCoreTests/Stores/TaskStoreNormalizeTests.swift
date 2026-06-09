import Testing
import Foundation
import CoreData
@testable import LillistCore

@Suite("TaskStore.normalizeSiblingsIfDegenerate", .serialized)
struct TaskStoreNormalizeTests {

    // MARK: - T17a: Healthy sibling set — zero writes (idempotent)

    @Test("Healthy sibling set: zero writes (idempotent)")
    func healthySetNoWrite() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parentID = try await store.create(title: "P")
        let a = try await store.create(title: "A", parent: parentID)
        let b = try await store.create(title: "B", parent: parentID)
        let c = try await store.create(title: "C", parent: parentID)

        let before = try await store.children(of: parentID).map(\.position)
        try await store.normalizeSiblingsIfDegenerate(ofParent: parentID)
        let after = try await store.children(of: parentID).map(\.position)
        #expect(before == after, "Healthy set should not be mutated by normalize")
        _ = (a, b, c)
    }

    // MARK: - T17b: Degenerate (tied) siblings — normalize compacts to strictly increasing

    @Test("Degenerate (tied) siblings: normalize compacts to strictly increasing")
    func degenerateSetNormalized() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parentID = try await store.create(title: "P")
        let aID = try await store.create(title: "A", parent: parentID)
        let bID = try await store.create(title: "B", parent: parentID)

        // Force a tie by setting both siblings to the same position directly
        // via the viewContext, bypassing the store's public API.
        let ctx = p.container.viewContext
        try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id IN %@", [aID, bID] as CVarArg)
            let tasks = (try? ctx.fetch(req)) ?? []
            for t in tasks { t.position = 5.0 }
            try ctx.save()
        }

        try await store.normalizeSiblingsIfDegenerate(ofParent: parentID)
        let positions = try await store.children(of: parentID).map(\.position)
        #expect(positions.count == 2)
        #expect(positions[0] < positions[1], "Positions must be strictly increasing after normalize")
    }

    // MARK: - T17c: Second call on already-normalized data — zero writes (idempotent)

    @Test("Second call on already-normalized data: zero writes (idempotent)")
    func normalizeIsIdempotent() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parentID = try await store.create(title: "P")
        let aID = try await store.create(title: "A", parent: parentID)
        let bID = try await store.create(title: "B", parent: parentID)

        // Force a tie, then normalize once to produce a clean state.
        let ctx = p.container.viewContext
        try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id IN %@", [aID, bID] as CVarArg)
            let tasks = (try? ctx.fetch(req)) ?? []
            for t in tasks { t.position = 5.0 }
            try ctx.save()
        }
        try await store.normalizeSiblingsIfDegenerate(ofParent: parentID)

        let after1 = try await store.children(of: parentID).map(\.position)
        try await store.normalizeSiblingsIfDegenerate(ofParent: parentID)
        let after2 = try await store.children(of: parentID).map(\.position)
        #expect(after1 == after2, "Second normalize call on already-clean data must be a no-op")
    }
}
