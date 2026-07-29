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

    // MARK: - C3: merge re-points the loser's subtree instead of destroying it

    @Test("C3: merging re-points the loser's journal entries onto the survivor instead of deleting them")
    func mergeRepointsJournalEntries() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let id = try await tasks.create(title: "Hello!")
        let loserObjectID = try await insertDuplicate(id: id, title: "Hello! (dup)", deletedAt: Date(), in: ctx)
        // Give the LOSER its own journal entry — before C3, this got
        // cascade-deleted with the loser row; after C3, it must survive,
        // re-pointed onto the survivor.
        let entryID = UUID()
        try await ctx.perform {
            let loser = try ctx.existingObject(with: loserObjectID) as! LillistTask
            let entry = JournalEntry(context: ctx)
            entry.id = entryID
            entry.kindRaw = 0
            entry.createdAt = Date()
            entry.body = "orphaned note"
            entry.task = loser
            try ctx.save()
        }

        let survivorObjectID = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@ AND self != %@", id as CVarArg, loserObjectID)
            return try ctx.fetch(req).first!.objectID
        }
        let mirrorIdentifier = FakeMirrorIdentifier(mirrored: [survivorObjectID])
        _ = try await TaskDuplicateReconciler.reconcileDuplicates(in: ctx, mirrorIdentifier: mirrorIdentifier)

        let (entryExists, entryTaskObjectID): (Bool, NSManagedObjectID?) = try await ctx.perform {
            let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
            req.predicate = NSPredicate(format: "id == %@", entryID as CVarArg)
            let entry = try ctx.fetch(req).first
            return (entry != nil, entry?.task?.objectID)
        }
        #expect(entryExists, "the loser's journal entry must survive the merge, not be cascade-deleted")
        #expect(entryTaskObjectID == survivorObjectID, "the surviving journal entry must now belong to the survivor")
    }

    @Test("C3: merging re-points the loser's children onto the survivor instead of deleting them")
    func mergeRepointsChildren() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let id = try await tasks.create(title: "Hello!")
        let loserObjectID = try await insertDuplicate(id: id, title: "Hello! (dup)", deletedAt: Date(), in: ctx)
        let childID = UUID()
        try await ctx.perform {
            let loser = try ctx.existingObject(with: loserObjectID) as! LillistTask
            let child = LillistTask(context: ctx)
            child.id = childID
            child.title = "orphaned child"
            child.statusRaw = 0
            child.createdAt = Date()
            child.modifiedAt = Date()
            child.parent = loser
            try ctx.save()
        }

        let survivorObjectID = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@ AND self != %@", id as CVarArg, loserObjectID)
            return try ctx.fetch(req).first!.objectID
        }
        let mirrorIdentifier = FakeMirrorIdentifier(mirrored: [survivorObjectID])
        _ = try await TaskDuplicateReconciler.reconcileDuplicates(in: ctx, mirrorIdentifier: mirrorIdentifier)

        let (childExists, childParentObjectID): (Bool, NSManagedObjectID?) = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", childID as CVarArg)
            let child = try ctx.fetch(req).first
            return (child != nil, child?.parent?.objectID)
        }
        #expect(childExists, "the loser's child must survive the merge, not be cascade-deleted")
        #expect(childParentObjectID == survivorObjectID, "the surviving child must now be parented under the survivor")
    }

    @Test("C3: merging re-points the loser's attachments onto the survivor instead of deleting them")
    func mergeRepointsAttachments() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let id = try await tasks.create(title: "Hello!")
        let loserObjectID = try await insertDuplicate(id: id, title: "Hello! (dup)", deletedAt: Date(), in: ctx)
        let attachmentID = UUID()
        try await ctx.perform {
            let loser = try ctx.existingObject(with: loserObjectID) as! LillistTask
            let attachment = LillistCore.Attachment(context: ctx)
            attachment.id = attachmentID
            attachment.filename = "orphaned.bin"
            attachment.uti = "public.data"
            attachment.byteSize = 1
            attachment.data = Data([1])
            attachment.createdAt = Date()
            attachment.task = loser
            try ctx.save()
        }

        let survivorObjectID = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@ AND self != %@", id as CVarArg, loserObjectID)
            return try ctx.fetch(req).first!.objectID
        }
        let mirrorIdentifier = FakeMirrorIdentifier(mirrored: [survivorObjectID])
        _ = try await TaskDuplicateReconciler.reconcileDuplicates(in: ctx, mirrorIdentifier: mirrorIdentifier)

        let (attachmentExists, attachmentTaskObjectID): (Bool, NSManagedObjectID?) = try await ctx.perform {
            let req = NSFetchRequest<LillistCore.Attachment>(entityName: "Attachment")
            req.predicate = NSPredicate(format: "id == %@", attachmentID as CVarArg)
            let attachment = try ctx.fetch(req).first
            return (attachment != nil, attachment?.task?.objectID)
        }
        #expect(attachmentExists, "the loser's attachment must survive the merge, not be cascade-deleted")
        #expect(attachmentTaskObjectID == survivorObjectID, "the surviving attachment must now belong to the survivor")
    }

    @Test("C3: merging re-points the loser's notification specs onto the survivor instead of deleting them")
    func mergeRepointsNotificationSpecs() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let id = try await tasks.create(title: "Hello!")
        let loserObjectID = try await insertDuplicate(id: id, title: "Hello! (dup)", deletedAt: Date(), in: ctx)
        let specID = UUID()
        try await ctx.perform {
            let loser = try ctx.existingObject(with: loserObjectID) as! LillistTask
            let spec = NotificationSpec(context: ctx)
            spec.id = specID
            spec.kindRaw = 0
            spec.createdAt = Date()
            spec.task = loser
            try ctx.save()
        }

        let survivorObjectID = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@ AND self != %@", id as CVarArg, loserObjectID)
            return try ctx.fetch(req).first!.objectID
        }
        let mirrorIdentifier = FakeMirrorIdentifier(mirrored: [survivorObjectID])
        _ = try await TaskDuplicateReconciler.reconcileDuplicates(in: ctx, mirrorIdentifier: mirrorIdentifier)

        let (specExists, specTaskObjectID): (Bool, NSManagedObjectID?) = try await ctx.perform {
            let req = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
            req.predicate = NSPredicate(format: "id == %@", specID as CVarArg)
            let spec = try ctx.fetch(req).first
            return (spec != nil, spec?.task?.objectID)
        }
        #expect(specExists, "the loser's notification spec must survive the merge, not be cascade-deleted")
        #expect(specTaskObjectID == survivorObjectID, "the surviving notification spec must now belong to the survivor")
    }

    @Test("C3: field-merge adopts the loser's content when the loser is strictly newer")
    func fieldMergeNewerLoserWins() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let id = try await tasks.create(title: "Original title")
        try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            let survivor = try ctx.fetch(req).first!
            survivor.modifiedAt = Date(timeIntervalSince1970: 1_000)
            try ctx.save()
        }
        let loserObjectID = try await insertDuplicate(id: id, title: "Newer edit", in: ctx)
        try await ctx.perform {
            let loser = try ctx.existingObject(with: loserObjectID) as! LillistTask
            loser.notes = "newer notes"
            loser.modifiedAt = Date(timeIntervalSince1970: 2_000) // strictly newer
            try ctx.save()
        }

        let survivorObjectID = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@ AND self != %@", id as CVarArg, loserObjectID)
            return try ctx.fetch(req).first!.objectID
        }
        let mirrorIdentifier = FakeMirrorIdentifier(mirrored: [survivorObjectID])
        _ = try await TaskDuplicateReconciler.reconcileDuplicates(in: ctx, mirrorIdentifier: mirrorIdentifier)

        let survivor = try await ctx.perform { try ctx.existingObject(with: survivorObjectID) as! LillistTask }
        #expect(survivor.title == "Newer edit")
        #expect(survivor.notes == "newer notes")
    }

    @Test("C3: field-merge keeps the survivor's own content when the survivor is newer or equal")
    func fieldMergeSurvivorStandsWhenNotOlder() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let id = try await tasks.create(title: "Kept title")
        try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            let survivor = try ctx.fetch(req).first!
            survivor.modifiedAt = Date(timeIntervalSince1970: 2_000)
            try ctx.save()
        }
        let loserObjectID = try await insertDuplicate(id: id, title: "Stale edit", in: ctx)
        try await ctx.perform {
            let loser = try ctx.existingObject(with: loserObjectID) as! LillistTask
            loser.modifiedAt = Date(timeIntervalSince1970: 1_000) // strictly older
            try ctx.save()
        }

        let survivorObjectID = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@ AND self != %@", id as CVarArg, loserObjectID)
            return try ctx.fetch(req).first!.objectID
        }
        let mirrorIdentifier = FakeMirrorIdentifier(mirrored: [survivorObjectID])
        _ = try await TaskDuplicateReconciler.reconcileDuplicates(in: ctx, mirrorIdentifier: mirrorIdentifier)

        let survivor = try await ctx.perform { try ctx.existingObject(with: survivorObjectID) as! LillistTask }
        #expect(survivor.title == "Kept title")
    }

    @Test("C3: field-merge never adopts the loser's position or parent, even when the loser wins")
    func fieldMergeExcludesPositionAndParent() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let parentID = try await tasks.create(title: "the one true parent")
        let id = try await tasks.create(title: "Original", parent: parentID)
        let survivorPosition: Double = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            let survivor = try ctx.fetch(req).first!
            survivor.modifiedAt = Date(timeIntervalSince1970: 1_000)
            try ctx.save()
            return survivor.position
        }
        let loserObjectID = try await insertDuplicate(id: id, title: "Newer, but structurally untrustworthy", in: ctx)
        try await ctx.perform {
            let loser = try ctx.existingObject(with: loserObjectID) as! LillistTask
            loser.position = 999.0
            loser.parent = nil // the loser thinks it's a root task
            loser.modifiedAt = Date(timeIntervalSince1970: 2_000) // strictly newer
            try ctx.save()
        }

        let survivorObjectID = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@ AND self != %@", id as CVarArg, loserObjectID)
            return try ctx.fetch(req).first!.objectID
        }
        let mirrorIdentifier = FakeMirrorIdentifier(mirrored: [survivorObjectID])
        _ = try await TaskDuplicateReconciler.reconcileDuplicates(in: ctx, mirrorIdentifier: mirrorIdentifier)

        let (survivorTitle, survivorFinalPosition, survivorParentObjectID): (String?, Double, UUID?) = try await ctx.perform {
            let survivor = try ctx.existingObject(with: survivorObjectID) as! LillistTask
            return (survivor.title, survivor.position, survivor.parent?.id)
        }
        #expect(survivorTitle == "Newer, but structurally untrustworthy", "content still merges normally")
        #expect(survivorFinalPosition == survivorPosition, "position must never be adopted from the loser")
        #expect(survivorParentObjectID == parentID, "parent must never be adopted from the loser")
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

    // MARK: - M5: a reconcile failure must be surfaced, never silently swallowed

    @Test("M5: reconcileNow surfaces a reconcile failure instead of silently swallowing it")
    func reconcileNowSurfacesFailure() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let id = try await tasks.create(title: "Hello!")
        let ctx = p.container.viewContext
        let loserObjectID = try await insertDuplicate(id: id, title: "Hello! (dup)", in: ctx)
        let survivorObjectID = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@ AND self != %@", id as CVarArg, loserObjectID)
            return try ctx.fetch(req).first!.objectID
        }

        // Force a deterministic optimistic-lock conflict on the
        // reconciler's own merge save: pin the loser row dirty on
        // viewContext at a stale version (mergePolicy = .error, auto-merge
        // off), then bump the SAME row from a background context so
        // ctx.delete(loser) conflicts on save — same technique as
        // TaskStoreRollbackTests.
        await ctx.perform {
            ctx.automaticallyMergesChangesFromParent = false
            ctx.mergePolicy = NSMergePolicy.error
            let loser = try! ctx.existingObject(with: loserObjectID) as! LillistTask
            loser.notes = "dirty-pin"
        }
        let bg = p.container.newBackgroundContext()
        await bg.perform {
            let m = try! bg.existingObject(with: loserObjectID) as! LillistTask
            m.title = "bg-edit"
            try! bg.save()
        }

        let reconciler = TaskDuplicateReconciler(persistence: p)
        let spy = SpyDiagnosticSink()
        reconciler.diagnosticLog = spy
        let mirrorIdentifier = FakeMirrorIdentifier(mirrored: [survivorObjectID])

        await reconciler.reconcileNow(mirrorIdentifier: mirrorIdentifier)

        let events = await spy.events
        #expect(!events.isEmpty, "a reconcile failure must be surfaced (diagnostic emit), not silently swallowed")

        // Restore normal merge behavior so the shared viewContext isn't left
        // wedged for any test that happens to run after this one.
        await ctx.perform {
            ctx.rollback()
            ctx.automaticallyMergesChangesFromParent = true
            ctx.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        }
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

    // MARK: - M3: overlapping notifications collapse into a bounded number of passes

    /// Always reports nothing mirrored (ambiguous — never resolves the
    /// duplicate group), so a `mirroredObjectIDs` call fires on EVERY full
    /// pass that finds the group still present, for as long as the test
    /// runs — letting the call count double as a direct proxy for "how many
    /// times the reconcile core actually ran," independent of whether any
    /// individual pass does useful work.
    private final class CountingAmbiguousMirrorIdentifier: MirroredObjectIdentifying, @unchecked Sendable {
        private let lock = NSLock()
        private var _callCount = 0
        var callCount: Int { lock.lock(); defer { lock.unlock() }; return _callCount }
        func mirroredObjectIDs(among ids: [NSManagedObjectID]) -> Set<NSManagedObjectID> {
            lock.lock(); _callCount += 1; lock.unlock()
            return []   // ambiguous: 0 mirrored — the group is never resolved
        }
    }

    @Test("M3: concurrent reconcileNow calls collapse into a bounded number of full-table passes, not one per notification")
    func concurrentCallsCollapseIntoBoundedPasses() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let id = try await tasks.create(title: "Hello!")
        try await insertDuplicate(id: id, title: "Hello! (dup)", in: ctx)   // never resolves — kept ambiguous

        let counter = CountingAmbiguousMirrorIdentifier()
        let reconciler = TaskDuplicateReconciler(persistence: p)

        // Fire many overlapping drains at once — without DrainGate, each of
        // the 24 concurrent calls independently runs its own full-table
        // scan (24 calls to the mirror identifier); with it, all but the
        // owner plus a small, bounded number of coalesced reruns must
        // return without running a pass at all.
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<24 {
                group.addTask { await reconciler.reconcileNow(mirrorIdentifier: counter) }
            }
        }

        #expect(counter.callCount < 24, "overlapping notifications must coalesce into far fewer full-table passes than the number of concurrent calls")
        #expect(counter.callCount <= 4, "the gate must bound the coalesced rerun count, not merely reduce it a little")
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
