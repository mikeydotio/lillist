import Testing
import CoreData
import Foundation
@testable import LillistCore

/// X19/H5: `reconcileDuplicates`'s `ctx.save()` previously had no rollback
/// on failure — a failed merge left every re-pointed relationship and
/// pending `ctx.delete(loser)` dirty on the shared `viewContext`, ready for
/// the next unrelated save (from any other store) to commit. Migrating onto
/// `withMutationRollback` closes this the same way it closed it for the
/// five bare stores.
@Suite("TaskDuplicateReconciler X19 rollback")
struct TaskDuplicateReconcilerX19RollbackTests {
    private struct FakeMirrorIdentifier: MirroredObjectIdentifying {
        let mirrored: Set<NSManagedObjectID>
        func mirroredObjectIDs(among ids: [NSManagedObjectID]) -> Set<NSManagedObjectID> {
            Set(ids).intersection(mirrored)
        }
    }

    @discardableResult
    private func insertDuplicate(
        id: UUID, title: String, deletedAt: Date? = nil, in ctx: NSManagedObjectContext
    ) async throws -> NSManagedObjectID {
        try await ctx.perform {
            let task = LillistTask(context: ctx)
            task.id = id
            task.title = title
            task.statusRaw = 0
            task.createdAt = Date()
            task.modifiedAt = Date()
            task.position = 0
            task.schemaVersion = 1
            task.deletedAt = deletedAt
            try ctx.save()
            return task.objectID
        }
    }

    @Test("A failed merge save rolls the viewContext back")
    func failedMergeSaveRollsBack() async throws {
        let p = try await TestStore.make()
        let ctx = p.container.viewContext
        let tasks = TaskStore(persistence: p)
        let id = try await tasks.create(title: "Hello!")
        let loserObjectID = try await insertDuplicate(id: id, title: "Hello! (dup)", deletedAt: Date(), in: ctx)

        let survivorObjectID = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@ AND self != %@", id as CVarArg, loserObjectID)
            return try ctx.fetch(req).first!.objectID
        }

        // Pin the survivor at v1 with a pending change + error policy, then
        // bump it from a background context — the same optimistic-lock
        // conflict technique TaskStoreRollbackTests uses. reconcileDuplicates
        // will re-fetch this same cached, already-dirty survivor object
        // (Core Data dedupes by objectID within one context) and its own
        // save will conflict.
        await ctx.perform {
            ctx.automaticallyMergesChangesFromParent = false
            ctx.mergePolicy = NSMergePolicy.error
            let survivor = try! ctx.existingObject(with: survivorObjectID) as! LillistTask
            survivor.notes = "dirty-pin"
        }
        let bg = p.container.newBackgroundContext()
        await bg.perform {
            let survivor = try! bg.existingObject(with: survivorObjectID) as! LillistTask
            survivor.title = "bg-edit"
            try! bg.save()
        }

        let mirrorIdentifier = FakeMirrorIdentifier(mirrored: [survivorObjectID])
        var threw = false
        do {
            _ = try await TaskDuplicateReconciler.reconcileDuplicates(in: ctx, mirrorIdentifier: mirrorIdentifier)
        } catch {
            threw = true
        }
        #expect(threw == true)

        let hasChanges: Bool = await ctx.perform { ctx.hasChanges }
        #expect(hasChanges == false, "a failed merge save must roll back the re-pointed relationships and pending delete")

        // The loser must still exist (the delete was rolled back, not committed).
        let loserStillExists: Bool = await ctx.perform {
            (try? ctx.existingObject(with: loserObjectID)) != nil && !((try? ctx.existingObject(with: loserObjectID))?.isDeleted ?? true)
        }
        #expect(loserStillExists == true)
    }
}
