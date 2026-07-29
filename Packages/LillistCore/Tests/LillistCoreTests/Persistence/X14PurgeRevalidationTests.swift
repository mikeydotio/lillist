import Testing
import Foundation
import CoreData
@testable import LillistCore

/// X14 — a task restored (or re-trashed past a retention cutoff) after
/// being fetched as a purge candidate, but before its chunk's delete
/// actually runs, must survive. Drives `TrashPurger`'s two decomposed
/// steps (`fetchCandidateRootObjectIDs`, `purgeChunk`) directly rather than
/// the composed `purge()`, so the restore can be inserted at the exact
/// point between them — deterministically, not via a timing race.
///
/// The interleaving is deterministic for the same reason
/// `TagStoreFindOrCreateRaceTests.secondContextCanRace` is: the purge
/// context has `automaticallyMergesChangesFromParent = true`, and
/// `NSManagedObjectContext.save()` posts its `NSManagedObjectContextDidSave`
/// notification *synchronously*, before returning — so by the time this
/// test's `await viewContext.perform { ...; try viewContext.save() }` call
/// returns, the resulting auto-merge block is already enqueued on the purge
/// context's serial queue ahead of anything this test subsequently sends it
/// via `ctx.perform`, guaranteeing FIFO delivery with no sleep.
@Suite("X14 — purge revalidates the victim predicate at delete time")
struct X14PurgeRevalidationTests {
    @Test("A task restored after being fetched as a candidate is not purged")
    func restoredMidFlightSurvives() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let victimID = try await store.create(title: "victim")
        let survivorID = try await store.create(title: "innocent bystander")
        try await store.softDelete(id: victimID)
        try await store.softDelete(id: survivorID)

        let ctx = p.makeBackgroundContext()
        let viewContext = p.container.viewContext

        // Step 0: fetch candidates on the purge context — this is what
        // registers/fires both rows in `ctx`, caching their (currently
        // trashed) state, exactly like the real `purge()`'s first step.
        let candidates = try await TrashPurger.fetchCandidateRootObjectIDs(
            predicateFormat: "deletedAt != nil",
            arguments: [],
            context: ctx
        )
        #expect(candidates.count == 2)

        // The restore lands on a DIFFERENT, real context (viewContext) and
        // is durably saved before the chunk runs — modeling "another
        // process/actor restored this task while the purge was in flight."
        try await store.restore(id: victimID)

        // The chunk's delete-time revalidation must see the restore (via
        // the purge context's auto-merge) and skip the now-live task.
        let purgedCount = try await TrashPurger.purgeChunk(
            candidates,
            predicateFormat: "deletedAt != nil",
            arguments: [],
            context: ctx,
            viewContext: viewContext
        )

        #expect(purgedCount == 1, "only the still-trashed survivor row should purge")
        let victim = try await store.fetch(id: victimID)
        #expect(victim.deletedAt == nil, "the restored task must not have been purged")
        await #expect(throws: LillistError.notFound) {
            _ = try await store.fetch(id: survivorID)
        }
    }

    @Test("A task re-trashed past a retention cutoff is not purged by a stale predicate")
    func reTrashedPastCutoffSurvives() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let victimID = try await store.create(title: "victim")
        try await store.softDelete(id: victimID)

        let ctx = p.makeBackgroundContext()
        let viewContext = p.container.viewContext
        let cutoff = Date().addingTimeInterval(-30 * 86_400)

        // Backdate deletedAt past the cutoff so a Step-0 fetch sees it as a
        // genuine victim...
        try await viewContext.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", victimID as CVarArg)
            let m = try viewContext.fetch(req).first!
            m.deletedAt = cutoff.addingTimeInterval(-86_400)
            try viewContext.save()
        }
        let staleCandidates = try await TrashPurger.fetchCandidateRootObjectIDs(
            predicateFormat: "deletedAt != nil AND deletedAt < %@",
            arguments: [cutoff],
            context: ctx
        )
        #expect(staleCandidates.count == 1)

        // ...then softDelete AGAIN (re-trash), which unconditionally stamps
        // a fresh `deletedAt = now` — moving the row back inside the
        // retention window without ever clearing `deletedAt` to nil. A
        // naive "still has deletedAt" recheck would miss this; only a full
        // predicate re-evaluation catches it.
        try await store.softDelete(id: victimID)

        let purgedCount = try await TrashPurger.purgeChunk(
            staleCandidates,
            predicateFormat: "deletedAt != nil AND deletedAt < %@",
            arguments: [cutoff],
            context: ctx,
            viewContext: viewContext
        )

        #expect(purgedCount == 0, "the freshly-re-trashed row now falls outside the retention cutoff")
        let victim = try await store.fetch(id: victimID)
        #expect(victim.deletedAt != nil, "still trashed, just not old enough to purge")
    }
}
