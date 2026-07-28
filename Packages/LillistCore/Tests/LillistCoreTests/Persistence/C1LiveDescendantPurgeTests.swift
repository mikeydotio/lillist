import Testing
import Foundation
import CoreData
@testable import LillistCore

/// C1 — trash purge must never hard-delete a live descendant of a trashed
/// ancestor. `NSBatchDeleteRequest` bypasses Core Data's in-memory
/// delete-rule engine, but the model's `children` relationship
/// (`deletionRule="Cascade"`) still cascades at the SQLite row level even
/// for batch deletes (see `docs/engineering-notes.md`, "Batch delete skips
/// delete rules — and the result set lies") — so merely excluding a live
/// child's objectID from the deletion set is not enough; its `parent` link
/// must be severed (promoting it to root) *before* the batch delete runs,
/// or the store's own FK cascade takes the live row down anyway regardless
/// of what CascadeReaper reports.
///
/// The live-under-trashed precondition is constructed by direct context
/// manipulation (bypassing `TaskStore`'s own guards) — the same shape a
/// CloudKit merge can produce even after M1/C2 close every local path to it.
@Suite("C1 purge spares live descendants of a trashed ancestor")
struct C1LiveDescendantPurgeTests {
    private func makeLiveUnderTrashed(
        store: TaskStore,
        persistence: PersistenceController
    ) async throws -> (parentID: UUID, childID: UUID) {
        let parentID = try await store.create(title: "parent")
        let childID = try await store.create(title: "child", parent: parentID)
        try await store.softDelete(id: parentID) // cascades trash to child too

        // Restore only the child's own `deletedAt`, directly — leaving its
        // parent trashed. This is exactly the state C2's fix (restore
        // promotes to root) prevents going forward; here we need it to
        // exist so the purge-time barrier has something to defend against.
        let ctx = persistence.container.viewContext
        try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", childID as CVarArg)
            let child = try ctx.fetch(req).first!
            child.deletedAt = nil
            try ctx.save()
        }
        return (parentID, childID)
    }

    @Test("purgeAll spares the live child and promotes it to root")
    func purgeAllSparesLiveDescendant() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let (_, childID) = try await makeLiveUnderTrashed(store: store, persistence: p)

        let purged = try await store.purgeAll()

        #expect(purged == 1, "only the trashed parent is purged; the live child survives")
        let child = try await store.fetch(id: childID)
        #expect(child.deletedAt == nil)
        #expect(child.parentID == nil, "the surviving live child is promoted to root")
        let roots = try await store.children(of: nil)
        #expect(roots.contains { $0.id == childID })
    }

    @Test("purgeAll spares an entire live subtree hanging off the barrier node")
    func purgeAllSparesLiveSubtree() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let (_, childID) = try await makeLiveUnderTrashed(store: store, persistence: p)
        let grandchildID = try await store.create(title: "grandchild", parent: childID)

        let purged = try await store.purgeAll()

        #expect(purged == 1)
        let grandchild = try await store.fetch(id: grandchildID)
        #expect(grandchild.deletedAt == nil)
        #expect(grandchild.parentID == childID, "the live child's own subtree stays attached to it, untouched")
    }

    @Test("AutoPurgeJob spares the live child and promotes it to root")
    func autoPurgeJobSparesLiveDescendant() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let prefs = PreferencesStore(persistence: p)
        try await prefs.update { $0.trashRetentionDays = 0 } // purge anything trashed
        let (parentID, childID) = try await makeLiveUnderTrashed(store: store, persistence: p)

        // Backdate the parent's deletedAt so it clears the 0-day retention window.
        let ctx = p.container.viewContext
        try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", parentID as CVarArg)
            let parent = try ctx.fetch(req).first!
            parent.deletedAt = Date().addingTimeInterval(-86_400)
            try ctx.save()
        }

        let job = AutoPurgeJob(persistence: p, preferences: prefs)
        let purged = try await job.run()

        #expect(purged == 1)
        let child = try await store.fetch(id: childID)
        #expect(child.deletedAt == nil)
        #expect(child.parentID == nil, "the surviving live child is promoted to root")
    }

    @Test("A fully cascade-trashed subtree still purges completely (no over-sparing)")
    func fullyTrashedSubtreeStillFullyPurges() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parent = try await store.create(title: "parent")
        let child = try await store.create(title: "child", parent: parent)
        _ = try await store.create(title: "grandchild", parent: child)
        try await store.softDelete(id: parent) // cascades to the whole subtree

        let purged = try await store.purgeAll()

        #expect(purged == 3, "an entirely trashed subtree purges completely, unaffected by the live-descendant barrier")
    }
}
