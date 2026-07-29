import Testing
import Foundation
import CoreData
@testable import LillistCore

/// H5: `SmartFilterStore` had no rollback discipline anywhere — every
/// mutating method called `context.save()` with no surrounding `do`/`catch`
/// at all. Mirrors `TaskStoreRollbackTests`'s optimistic-locking-conflict
/// technique.
@Suite("SmartFilterStore rollback on save failure")
struct SmartFilterStoreRollbackTests {
    @Test("A failed update rolls the viewContext back")
    func updateRollsBack() async throws {
        let p = try await TestStore.make()
        let store = SmartFilterStore(persistence: p)
        let id = try await store.create(name: "Today", group: .init(combinator: .all, predicates: []))
        let view = p.container.viewContext

        await view.perform {
            view.automaticallyMergesChangesFromParent = false
            view.mergePolicy = NSMergePolicy.error
            let req = NSFetchRequest<SmartFilter>(entityName: "SmartFilter")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            let m = try! view.fetch(req).first!
            m.tintColor = "#000000"
        }
        let bg = p.container.newBackgroundContext()
        await bg.perform {
            let req = NSFetchRequest<SmartFilter>(entityName: "SmartFilter")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            let m = try! bg.fetch(req).first!
            m.name = "bg-edit"
            try! bg.save()
        }

        var threw = false
        do {
            try await store.update(id: id) { $0.name = "Renamed" }
        } catch {
            threw = true
        }
        #expect(threw == true)

        let hasChanges: Bool = await view.perform { view.hasChanges }
        #expect(hasChanges == false, "update's catch must roll back the shared viewContext")
    }
}
