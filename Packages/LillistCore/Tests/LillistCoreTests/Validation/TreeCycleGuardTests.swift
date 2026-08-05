import Testing
import Foundation
import CoreData
@testable import LillistCore

/// H7 — a parent-cycle CloudKit's property-level merge can create
/// (`X.parent == Y`, `Y.parent == X`) must never hang or overflow a walk
/// that encounters it. Every ancestor/descendant walk the review named gets
/// its own regression test here: `Validators.wouldCreateCycle`,
/// `TaskStore.applySoftDelete`/`clearSoftDelete` (via the public
/// `softDelete`/`restore`), `TaskStore+Queries.breadcrumbs(for:)`,
/// `RecurrenceSpawner.deepCopy` (via `TaskStore.transition`), and
/// `Tag.descendants`.
///
/// Each cyclic graph is built by direct context manipulation — bypassing
/// every store-level cycle guard on purpose, the same way a CloudKit
/// property-level merge would (no local mutation path can construct these
/// once M1/H7 land, but a remote merge writes each row's relationships
/// independently and is not bound by local validation).
///
/// LIL-97's cascade-close/cascade-reopen walks (also via `TaskStore
/// .transition`) get their own dedicated cycle-guard tests in
/// `TaskStoreCascadeCompleteTests` rather than duplicating them here, since
/// they need richer fixtures (mixed statuses, journal entries) than this
/// file's minimal two-node cycles.
@Suite("H7 tree/tag cycle guards")
struct TreeCycleGuardTests {
    @Test("wouldCreateCycle terminates and conservatively blocks when it encounters a pre-existing ancestor cycle")
    func wouldCreateCycleTerminatesOnPreexistingCycle() async throws {
        let p = try await TestStore.make()
        let ctx = p.container.viewContext
        let (aID, cID): (NSManagedObjectID, NSManagedObjectID) = try await ctx.perform {
            let a = LillistTask(context: ctx)
            a.id = UUID(); a.title = "A"
            let b = LillistTask(context: ctx)
            b.id = UUID(); b.title = "B"
            let c = LillistTask(context: ctx)
            c.id = UUID(); c.title = "C"
            a.parent = b
            b.parent = a // pre-existing cycle, unrelated to candidate c
            try ctx.save()
            return (a.objectID, c.objectID)
        }

        let outcome: Bool? = HangGuard.run(timeout: 3) {
            nonisolated(unsafe) var result = false
            ctx.performAndWait {
                guard let a = try? ctx.existingObject(with: aID) as? LillistTask,
                      let c = try? ctx.existingObject(with: cID) as? LillistTask else { return }
                result = Validators.wouldCreateCycle(candidate: c, newParent: a)
            }
            return result
        }

        #expect(outcome != nil, "wouldCreateCycle must terminate even when the walk encounters a pre-existing cycle")
        #expect(outcome == true, "an unresolvable ancestor cycle must be treated conservatively as blocking")
    }

    @Test("softDelete terminates on a mutual parent-cycle and trashes both members")
    func softDeleteTerminatesOnCycle() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let ctx = p.container.viewContext
        let aID: UUID = UUID()
        let bID: UUID = UUID()
        try await ctx.perform {
            let a = LillistTask(context: ctx)
            a.id = aID; a.title = "A"
            let b = LillistTask(context: ctx)
            b.id = bID; b.title = "B"
            a.parent = b
            b.parent = a
            try ctx.save()
        }

        let completed: Bool? = HangGuard.run(timeout: 3) {
            let sem = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var threw = false
            Task {
                do { try await store.softDelete(id: aID) } catch { threw = true }
                sem.signal()
            }
            sem.wait()
            return !threw
        }

        #expect(completed == true, "softDelete must terminate (and succeed) on a mutual parent-cycle")
        let a = try await store.fetch(id: aID)
        let b = try await store.fetch(id: bID)
        #expect(a.deletedAt != nil)
        #expect(b.deletedAt != nil)
    }

    @Test("restore terminates on a mutual parent-cycle and clears both members")
    func restoreTerminatesOnCycle() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let ctx = p.container.viewContext
        let aID = UUID()
        let bID = UUID()
        let now = Date()
        try await ctx.perform {
            let a = LillistTask(context: ctx)
            a.id = aID; a.title = "A"; a.deletedAt = now
            let b = LillistTask(context: ctx)
            b.id = bID; b.title = "B"; b.deletedAt = now
            a.parent = b
            b.parent = a
            try ctx.save()
        }

        let completed: Bool? = HangGuard.run(timeout: 3) {
            let sem = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var threw = false
            Task {
                do { try await store.restore(id: aID) } catch { threw = true }
                sem.signal()
            }
            sem.wait()
            return !threw
        }

        #expect(completed == true, "restore must terminate (and succeed) on a mutual parent-cycle")
    }

    @Test("breadcrumbs(for:) terminates on a parent cycle instead of looping forever")
    func breadcrumbsTerminatesOnCycle() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let ctx = p.container.viewContext
        let aID = UUID()
        try await ctx.perform {
            let a = LillistTask(context: ctx)
            a.id = aID; a.title = "A"
            let b = LillistTask(context: ctx)
            b.id = UUID(); b.title = "B"
            a.parent = b
            b.parent = a
            try ctx.save()
        }

        let completed: Bool? = HangGuard.run(timeout: 3) {
            let sem = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var ok = false
            Task {
                _ = try? await store.breadcrumbs(for: [aID])
                ok = true
                sem.signal()
            }
            sem.wait()
            return ok
        }

        #expect(completed == true, "breadcrumbs(for:) must terminate even on a parent cycle")
    }

    @Test("Tag.descendants terminates on a parent cycle instead of looping forever")
    func tagDescendantsTerminatesOnCycle() async throws {
        let p = try await TestStore.make()
        let ctx = p.container.viewContext
        let rootID: NSManagedObjectID = try await ctx.perform {
            let a = LillistCore.Tag(context: ctx)
            a.id = UUID(); a.name = "A"
            let b = LillistCore.Tag(context: ctx)
            b.id = UUID(); b.name = "B"
            a.parent = b
            b.parent = a
            try ctx.save()
            return a.objectID
        }

        let count: Int? = HangGuard.run(timeout: 3) {
            nonisolated(unsafe) var result = 0
            ctx.performAndWait {
                if let a = try? ctx.existingObject(with: rootID) as? LillistCore.Tag {
                    result = a.descendants.count
                }
            }
            return result
        }

        #expect(count != nil, "Tag.descendants must terminate even on a parent cycle")
    }

    @Test("RecurrenceSpawner deep-copy terminates when the seed's subtree contains a parent cycle")
    func deepCopyTerminatesOnCycle() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let seedID = try await tasks.create(title: "seed")
        let kidID = try await tasks.create(title: "kid", parent: seedID)
        let grandkidID = try await tasks.create(title: "grandkid", parent: kidID)
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        _ = try await series.create(fromSeedTask: seedID, rule: rule)

        // Close a 3-ring back through `seed` itself: kid is seed's child
        // (deepCopy's entry point, from `seed.children`), grandkid is kid's
        // child, and — via this direct context write, bypassing every store
        // guard — seed becomes grandkid's child too. `parent` is to-one, so a
        // ring reachable from deepCopy's fixed entry point (kid.parent must
        // stay `seed`) can only close by looping back through `seed` itself.
        // No local mutation path can construct this once M1/H7 land; a
        // CloudKit property-level merge is the only realistic way to reach it.
        let ctx = p.container.viewContext
        try await ctx.perform {
            let seedReq = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            seedReq.predicate = NSPredicate(format: "id == %@", seedID as CVarArg)
            let seed = try ctx.fetch(seedReq).first!
            let grandkidReq = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            grandkidReq.predicate = NSPredicate(format: "id == %@", grandkidID as CVarArg)
            let grandkid = try ctx.fetch(grandkidReq).first!
            seed.parent = grandkid
            try ctx.save()
        }

        let completed: Bool? = HangGuard.run(timeout: 3) {
            let sem = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var ok = false
            Task {
                _ = try? await tasks.transition(id: seedID, to: .closed)
                ok = true
                sem.signal()
            }
            sem.wait()
            return ok
        }

        #expect(completed == true, "closing a recurring seed must terminate even if its subtree contains a parent cycle")
    }
}
