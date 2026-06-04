import Testing
import CoreData
import Foundation
@testable import LillistCore

/// Find-or-create atomicity is only guaranteed because every production
/// caller shares the single main-queue `viewContext`: the read and the
/// optional insert run inside one `context.perform`, so two concurrent
/// callers can't both miss the row and both insert.
///
/// This suite proves that contract two ways:
///   1. Concurrent `findOrCreate` calls on the SAME `TagStore` (single
///      context) NEVER create a duplicate — the invariant the app relies on.
///   2. Two INDEPENDENT `NSManagedObjectContext`s, interleaved so both miss
///      the row before either inserts, DO produce a duplicate — the proof
///      that the no-dup guarantee is a single-context property, not a
///      schema/predicate property.
///
/// Test 2 is interleaved DETERMINISTICALLY (not via a timing race) so it
/// reliably demonstrates the duplicate window without flaking under CI load.
/// See engineering-notes "find-or-create single-context invariant".
@Suite("TagStore.findOrCreate — concurrency", .serialized)
struct TagStoreFindOrCreateRaceTests {
    private static let concurrentCallers = 16
    private static let iterations = 25

    @Test("Concurrent findOrCreate on one store returns a single tag (single-context atomicity)")
    func singleContextStaysAtomic() async throws {
        for iteration in 0..<Self.iterations {
            let p = try await TestStore.make()
            let store = TagStore(persistence: p)

            // Many tasks racing to create the same name. All share the one
            // viewContext, so the perform blocks serialize and the second+
            // callers see the row the first inserted.
            let ids = await withTaskGroup(of: UUID?.self) { group -> [UUID] in
                for _ in 0..<Self.concurrentCallers {
                    group.addTask { try? await store.findOrCreate(name: "groceries") }
                }
                var collected: [UUID] = []
                for await id in group { if let id { collected.append(id) } }
                return collected
            }

            #expect(ids.count == Self.concurrentCallers, "iteration \(iteration): a caller threw")
            #expect(Set(ids).count == 1, "iteration \(iteration): findOrCreate returned distinct IDs — duplicate created")

            let all = try await store.children(of: nil)
            let groceries = all.filter { $0.name.lowercased() == "groceries" }
            #expect(groceries.count == 1, "iteration \(iteration): \(groceries.count) 'groceries' tags exist")
        }
    }

    @Test("Two independent contexts that both miss the row both insert — the invariant rests on single-context discipline")
    func secondContextCanRace() async throws {
        // The tripwire, made deterministic. We bypass findOrCreate's
        // single-context guarantee by driving TWO independent contexts on the
        // same coordinator and interleaving their find-then-insert by hand:
        //   1. A reads "errands" -> absent
        //   2. B reads "errands" -> absent   (B's snapshot predates A's insert)
        //   3. A inserts + saves
        //   4. B inserts + saves             (B still believes the row is absent)
        // Because the two contexts don't serialize their perform blocks and
        // there is no (parent,name) unique constraint, both inserts persist.
        // This is the window the shared viewContext closes by serializing.
        let p = try await TestStore.make()
        let ctxA = p.container.viewContext
        let ctxB = p.container.newBackgroundContext()
        ctxB.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)

        // 1 & 2: both contexts observe the row absent before either inserts.
        // The fetch is inlined rather than extracted to a local function to
        // satisfy Swift 6 Sendable rules: NSManagedObjectContext is non-Sendable,
        // so a captured closure over it would not compile under strict concurrency.
        await ctxA.perform {
            // LillistCore.Tag is fully qualified to disambiguate from Testing.Tag.
            let req = NSFetchRequest<LillistCore.Tag>(entityName: "Tag")
            req.predicate = NSPredicate(format: "parent == nil AND name ==[c] %@", "errands")
            req.fetchLimit = 1
            let absent = ((try? ctxA.fetch(req))?.first) == nil
            #expect(absent, "ctxA: 'errands' should not exist before any insert")
        }
        await ctxB.perform {
            let req = NSFetchRequest<LillistCore.Tag>(entityName: "Tag")
            req.predicate = NSPredicate(format: "parent == nil AND name ==[c] %@", "errands")
            req.fetchLimit = 1
            let absent = ((try? ctxB.fetch(req))?.first) == nil
            #expect(absent, "ctxB: 'errands' should not exist before any insert")
        }

        // 3: A inserts + saves.
        try await ctxA.perform {
            let t = LillistCore.Tag(context: ctxA)
            t.id = UUID()
            t.name = "errands"
            t.position = 0
            try ctxA.save()
        }
        // 4: B inserts + saves, still on its stale "absent" snapshot.
        try await ctxB.perform {
            let t = LillistCore.Tag(context: ctxB)
            t.id = UUID()
            t.name = "errands"
            t.position = 1
            try ctxB.save()
        }

        // The store now holds two "errands" tags — no constraint collapsed them.
        let count: Int = try await p.container.viewContext.perform {
            p.container.viewContext.refreshAllObjects()
            let req = NSFetchRequest<LillistCore.Tag>(entityName: "Tag")
            req.predicate = NSPredicate(format: "name ==[c] %@", "errands")
            return try p.container.viewContext.count(for: req)
        }
        #expect(
            count == 2,
            """
            Two independent contexts each missed the row and inserted, yet the \
            store does not hold 2 'errands' tags (got \(count)). Either a \
            (parent,name) unique constraint now prevents duplicates — in which \
            case update engineering-notes 'find-or-create single-context \
            invariant' and assert the constraint instead — or Core Data merged \
            them, which would change the documented invariant.
            """
        )
    }
}
