import Testing
import Foundation
import CoreData
@testable import LillistCore

/// M1 — `create`, `reparent`, and `reorder` (both `.infer` and `.explicit`)
/// must reject a soft-deleted target parent, mirroring the existing
/// soft-deleted-*anchor* guard. Left unguarded, any of these three entry
/// points can directly construct the live-under-trashed illegal state
/// `C1`/`C2` exist to clean up after.
@Suite("M1 reject a soft-deleted parent")
struct TaskStoreTrashedParentGuardTests {
    @Test("create throws when the requested parent is trashed")
    func createRejectsTrashedParent() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parentID = try await store.create(title: "parent")
        try await store.softDelete(id: parentID)

        await #expect(throws: LillistError.self) {
            _ = try await store.create(title: "child", parent: parentID)
        }
    }

    @Test("reparent throws when the target parent is trashed")
    func reparentRejectsTrashedParent() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parentID = try await store.create(title: "parent")
        let childID = try await store.create(title: "child")
        try await store.softDelete(id: parentID)

        await #expect(throws: LillistError.self) {
            try await store.reparent(id: childID, newParent: parentID)
        }
        let child = try await store.fetch(id: childID)
        #expect(child.parentID == nil, "a rejected reparent must not have partially applied")
    }

    @Test("reorder(.explicit) throws when the target parent is trashed")
    func reorderExplicitRejectsTrashedParent() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parentID = try await store.create(title: "parent")
        let childID = try await store.create(title: "child")
        try await store.softDelete(id: parentID)

        await #expect(throws: LillistError.self) {
            try await store.reorder(id: childID, after: nil, before: nil, parent: .explicit(parentID))
        }
    }

    @Test("reorder(.infer) throws when the anchor-derived parent is trashed")
    func reorderInferRejectsTrashedParent() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parentID = try await store.create(title: "parent")
        let anchor = try await store.create(title: "anchor", parent: parentID)
        let mover = try await store.create(title: "mover")

        // `softDelete` cascades trash to every live child, which would trash
        // the anchor along with the parent — defeating this test's premise.
        // Simulate the live-under-trashed state M1 defends against directly
        // (a state that can only be reached via a CloudKit merge racing
        // ahead of the cascade, not via any local mutation once M1 lands):
        // the anchor stays live, only its parent gets trashed.
        let ctx = p.container.viewContext
        try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", parentID as CVarArg)
            let parent = try ctx.fetch(req).first!
            parent.deletedAt = Date()
            try ctx.save()
        }

        // The anchor itself is still live (only its parent was trashed) —
        // M1's guard fires on the *derived parent* being trashed, distinct
        // from the pre-existing soft-deleted-*anchor* guard, which only
        // fires when the anchor task itself is trashed.
        await #expect(throws: LillistError.self) {
            try await store.reorder(id: mover, after: anchor, before: nil, parent: .infer)
        }
    }

    @Test("create still succeeds under a live parent")
    func createSucceedsUnderLiveParent() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parentID = try await store.create(title: "parent")
        let childID = try await store.create(title: "child", parent: parentID)
        let child = try await store.fetch(id: childID)
        #expect(child.parentID == parentID)
    }
}
