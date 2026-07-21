import Testing
import CoreData
import Foundation
@testable import LillistCore

@Suite("TaskDuplicateReconciler")
struct TaskDuplicateReconcilerTests {
    /// Reports a fixed set of object IDs as "mirrored" — the injectable seam
    /// standing in for a live `NSPersistentCloudKitContainer.recordIDs(for:)`,
    /// which (like `TaskStore.syncCounts()`'s own mirrored>0 case) is
    /// otherwise untestable under unsigned `swift test`.
    private struct FakeMirrorIdentifier: MirroredObjectIdentifying {
        let mirrored: Set<NSManagedObjectID>
        func mirroredObjectIDs(among ids: [NSManagedObjectID]) -> Set<NSManagedObjectID> {
            Set(ids).intersection(mirrored)
        }
    }

    private func makeContext() async throws -> (PersistenceController, NSManagedObjectContext) {
        let p = try await TestStore.make()
        return (p, p.container.viewContext)
    }

    /// Inserts a second `LillistTask` row sharing `id` with an existing one
    /// — the shape a CloudKit re-import produces when local mirroring
    /// bookkeeping was discarded/rebuilt while the zone still held a
    /// matching record (issue #66). Bypasses `TaskStore` (which always
    /// mints a fresh `UUID()`) by inserting directly via the managed
    /// object, mirroring how `Importer.apply` creates a fresh row for an
    /// `id` it doesn't recognize.
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

    // MARK: - The exact bug: merges when exactly one candidate is mirrored

    @Test("Merges a duplicate pair down to the mirrored survivor, deleting the other")
    func mergesToMirroredSurvivor() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let id = try await tasks.create(title: "Hello!")
        // A second row sharing the SAME id, pending upload (never mirrored) —
        // exactly Nephele's shape: a tombstone-like duplicate alongside the
        // live, already-mirrored copy.
        let loserObjectID = try await insertDuplicate(id: id, title: "Hello! (dup)", deletedAt: Date(), in: ctx)

        let survivorObjectID = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@ AND self != %@", id as CVarArg, loserObjectID)
            return try ctx.fetch(req).first!.objectID
        }

        let mirrorIdentifier = FakeMirrorIdentifier(mirrored: [survivorObjectID])
        let deletedCount = try await TaskDuplicateReconciler.reconcileDuplicates(in: ctx, mirrorIdentifier: mirrorIdentifier)
        #expect(deletedCount == 1)

        let remaining = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            return try ctx.fetch(req)
        }
        #expect(remaining.count == 1)
        #expect(remaining.first?.objectID == survivorObjectID)
    }

    @Test("Deleting the loser also removes its own journal entries (Cascade)")
    func deletingLoserCascadesItsChildren() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let journal = JournalStore(persistence: p)
        let id = try await tasks.create(title: "Hello!")
        let loserObjectID = try await insertDuplicate(id: id, title: "Hello! (dup)", deletedAt: Date(), in: ctx)
        // Give the LOSER its own journal entry to prove cascade fires on
        // plain context.delete(_:), not just the row itself.
        try await ctx.perform {
            let loser = try ctx.existingObject(with: loserObjectID) as! LillistTask
            let entry = JournalEntry(context: ctx)
            entry.id = UUID()
            entry.kindRaw = 0
            entry.createdAt = Date()
            entry.body = "orphaned note"
            entry.task = loser
            try ctx.save()
        }
        _ = journal // silence unused-import warning if JournalStore ends up unused elsewhere

        let survivorObjectID = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@ AND self != %@", id as CVarArg, loserObjectID)
            return try ctx.fetch(req).first!.objectID
        }
        let mirrorIdentifier = FakeMirrorIdentifier(mirrored: [survivorObjectID])
        _ = try await TaskDuplicateReconciler.reconcileDuplicates(in: ctx, mirrorIdentifier: mirrorIdentifier)

        let remainingEntries = try await ctx.perform {
            try ctx.fetch(NSFetchRequest<JournalEntry>(entityName: "JournalEntry"))
        }
        #expect(remainingEntries.isEmpty, "the loser's journal entry must be cascade-deleted with it")
    }

    // MARK: - Ambiguous signal: does nothing, never guesses

    @Test("Does nothing when NEITHER duplicate is mirrored (ambiguous)")
    func doesNothingWhenNeitherMirrored() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let id = try await tasks.create(title: "Hello!")
        try await insertDuplicate(id: id, title: "Hello! (dup)", in: ctx)

        let mirrorIdentifier = FakeMirrorIdentifier(mirrored: [])
        let deletedCount = try await TaskDuplicateReconciler.reconcileDuplicates(in: ctx, mirrorIdentifier: mirrorIdentifier)
        #expect(deletedCount == 0)

        let remaining = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            return try ctx.fetch(req)
        }
        #expect(remaining.count == 2, "an ambiguous group must be left untouched, not guessed at")
    }

    @Test("Does nothing when BOTH duplicates are mirrored (ambiguous)")
    func doesNothingWhenBothMirrored() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let id = try await tasks.create(title: "Hello!")
        let loserObjectID = try await insertDuplicate(id: id, title: "Hello! (dup)", in: ctx)

        let survivorObjectID = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@ AND self != %@", id as CVarArg, loserObjectID)
            return try ctx.fetch(req).first!.objectID
        }
        let mirrorIdentifier = FakeMirrorIdentifier(mirrored: [survivorObjectID, loserObjectID])
        let deletedCount = try await TaskDuplicateReconciler.reconcileDuplicates(in: ctx, mirrorIdentifier: mirrorIdentifier)
        #expect(deletedCount == 0)
    }

    @Test("Does nothing when no mirror identifier is available (e.g. local-only mode)")
    func doesNothingWithoutMirrorIdentifier() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let id = try await tasks.create(title: "Hello!")
        try await insertDuplicate(id: id, title: "Hello! (dup)", in: ctx)

        let deletedCount = try await TaskDuplicateReconciler.reconcileDuplicates(in: ctx, mirrorIdentifier: nil)
        #expect(deletedCount == 0)
    }

    // MARK: - No duplicates: no-op

    @Test("No-op when every id is unique")
    func noOpWhenNoDuplicates() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        _ = try await tasks.create(title: "A")
        _ = try await tasks.create(title: "B")

        let mirrorIdentifier = FakeMirrorIdentifier(mirrored: [])
        let deletedCount = try await TaskDuplicateReconciler.reconcileDuplicates(in: ctx, mirrorIdentifier: mirrorIdentifier)
        #expect(deletedCount == 0)
    }

    // MARK: - Multiple independent duplicate groups in one pass

    @Test("Resolves multiple independent duplicate groups in a single pass")
    func resolvesMultipleGroups() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let idA = try await tasks.create(title: "Hello!")
        let idB = try await tasks.create(title: "Bah")
        let loserA = try await insertDuplicate(id: idA, title: "Hello! (dup)", in: ctx)
        let loserB = try await insertDuplicate(id: idB, title: "Bah (dup)", in: ctx)

        let (survivorA, survivorB) = try await ctx.perform { () -> (NSManagedObjectID, NSManagedObjectID) in
            let reqA = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            reqA.predicate = NSPredicate(format: "id == %@ AND self != %@", idA as CVarArg, loserA)
            let reqB = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            reqB.predicate = NSPredicate(format: "id == %@ AND self != %@", idB as CVarArg, loserB)
            return (try ctx.fetch(reqA).first!.objectID, try ctx.fetch(reqB).first!.objectID)
        }

        let mirrorIdentifier = FakeMirrorIdentifier(mirrored: [survivorA, survivorB])
        let deletedCount = try await TaskDuplicateReconciler.reconcileDuplicates(in: ctx, mirrorIdentifier: mirrorIdentifier)
        #expect(deletedCount == 2)

        let remainingA = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", idA as CVarArg)
            return try ctx.fetch(req).count
        }
        let remainingB = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", idB as CVarArg)
            return try ctx.fetch(req).count
        }
        #expect(remainingA == 1)
        #expect(remainingB == 1)
    }

    // MARK: - Triplicate: more than two rows sharing one id

    @Test("Resolves a triplicate (3 rows sharing one id) down to the one mirrored survivor")
    func resolvesTriplicate() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let id = try await tasks.create(title: "Hello!")
        try await insertDuplicate(id: id, title: "Hello! (dup1)", in: ctx)
        try await insertDuplicate(id: id, title: "Hello! (dup2)", in: ctx)

        let survivorObjectID = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@ AND title == %@", id as CVarArg, "Hello!")
            return try ctx.fetch(req).first!.objectID
        }
        let mirrorIdentifier = FakeMirrorIdentifier(mirrored: [survivorObjectID])
        let deletedCount = try await TaskDuplicateReconciler.reconcileDuplicates(in: ctx, mirrorIdentifier: mirrorIdentifier)
        #expect(deletedCount == 2)

        let remaining = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            return try ctx.fetch(req)
        }
        #expect(remaining.count == 1)
        #expect(remaining.first?.objectID == survivorObjectID)
    }
}
