import Testing
import Foundation
import CoreData
@testable import LillistCore

@Suite("TaskStore rollback on save failure")
struct TaskStoreRollbackTests {
    /// Force a deterministic optimistic-locking save conflict: pin the
    /// shared viewContext at a stale row version (auto-merge OFF, a pending
    /// change keeps the v1 snapshot, error merge policy), then bump the row
    /// from a background context so the store's save conflicts.
    @Test("A failed save rolls the viewContext back and the next op succeeds")
    func rollsBackThenRecovers() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "seed")
        let other = try await store.create(title: "other")
        let view = p.container.viewContext

        // Pin viewContext at v1 with a pending change + error policy.
        await view.perform {
            view.automaticallyMergesChangesFromParent = false
            view.mergePolicy = NSMergePolicy.error
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            let m = try! view.fetch(req).first!
            m.notes = "dirty-pin"
        }
        // Bump the row to v2 from a background context.
        let bg = p.container.newBackgroundContext()
        await bg.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            let m = try! bg.fetch(req).first!
            m.title = "bg-edit"
            try! bg.save()
        }

        // The store mutator's save now conflicts and throws.
        var threw = false
        var capturedError: Error?
        do {
            try await store.update(id: id) { $0.title = "view-edit" }
        } catch {
            threw = true
            capturedError = error
        }
        #expect(threw == true)
        #expect((capturedError as NSError?)?.code == NSManagedObjectMergeError, "expected an optimistic-lock merge conflict (133020), got \(String(describing: capturedError))")

        // The catch path must have rolled the viewContext back.
        let hasChanges: Bool = await view.perform { view.hasChanges }
        #expect(hasChanges == false)

        // Restore normal merge behavior and prove a fresh op on a different row succeeds.
        await view.perform {
            view.automaticallyMergesChangesFromParent = true
            view.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        }
        try await store.update(id: other) { $0.title = "other-updated" }
        let rec = try await store.fetch(id: other)
        #expect(rec.title == "other-updated")
    }

    @Test("A failed transition save rolls back (no stranded journal entry / spawn)")
    func transitionRollsBack() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "seed")
        let other = try await store.create(title: "other")
        let view = p.container.viewContext

        await view.perform {
            view.automaticallyMergesChangesFromParent = false
            view.mergePolicy = NSMergePolicy.error
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            let m = try! view.fetch(req).first!
            m.notes = "dirty-pin"
        }
        let bg = p.container.newBackgroundContext()
        await bg.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            let m = try! bg.fetch(req).first!
            m.title = "bg-edit"
            try! bg.save()
        }

        var threw = false
        do { try await store.transition(id: id, to: .closed) } catch { threw = true }
        #expect(threw == true)

        let hasChanges: Bool = await view.perform { view.hasChanges }
        #expect(hasChanges == false, "transition's catch must roll back the shared viewContext")

        await view.perform {
            view.automaticallyMergesChangesFromParent = true
            view.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        }
        try await store.update(id: other) { $0.title = "other-updated" }
        #expect(try await store.fetch(id: other).title == "other-updated")
    }
}
