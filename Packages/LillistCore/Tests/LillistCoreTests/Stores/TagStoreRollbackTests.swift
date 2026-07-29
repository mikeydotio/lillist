import Testing
import Foundation
import CoreData
@testable import LillistCore

/// H5: pre-`withMutationRollback`, `TagStore` had zero rollback discipline
/// anywhere — `create`/`rename`/`delete` had a `do`/`catch` but it only
/// recorded a breadcrumb, never called `context.rollback()`; `reparent`/
/// `setTintColor` had no `do`/`catch` at all. A failed save left the
/// partially-mutated row dirty on the shared `viewContext`, ready to be
/// committed by the next unrelated save from any other store. Mirrors
/// `TaskStoreRollbackTests`'s optimistic-locking-conflict technique.
@Suite("TagStore rollback on save failure")
struct TagStoreRollbackTests {
    @Test("A failed rename rolls the viewContext back")
    func renameRollsBack() async throws {
        let p = try await TestStore.make()
        let store = TagStore(persistence: p)
        let id = try await store.create(name: "Home")
        let view = p.container.viewContext

        // Pin viewContext at v1 with a pending change + error policy.
        await view.perform {
            view.automaticallyMergesChangesFromParent = false
            view.mergePolicy = NSMergePolicy.error
            let req = NSFetchRequest<LillistCore.Tag>(entityName: "Tag")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            let m = try! view.fetch(req).first!
            m.tintColor = "#000000"
        }
        // Bump the row from a background context so the store's save conflicts.
        let bg = p.container.newBackgroundContext()
        await bg.perform {
            let req = NSFetchRequest<LillistCore.Tag>(entityName: "Tag")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            let m = try! bg.fetch(req).first!
            m.name = "bg-edit"
            try! bg.save()
        }

        var threw = false
        do {
            try await store.rename(id: id, to: "Work")
        } catch {
            threw = true
        }
        #expect(threw == true)

        let hasChanges: Bool = await view.perform { view.hasChanges }
        #expect(hasChanges == false, "rename's catch must roll back the shared viewContext")
    }
}
