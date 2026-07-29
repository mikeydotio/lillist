import Testing
import Foundation
import CoreData
@testable import LillistCore

/// H5: `JournalStore` had no rollback discipline at all — every mutating
/// method called `context.save()` with no surrounding `do`/`catch`.
@Suite("JournalStore rollback on save failure")
struct JournalStoreRollbackTests {
    @Test("A failed editNote rolls the viewContext back")
    func editNoteRollsBack() async throws {
        let p = try await TestStore.make()
        let taskStore = TaskStore(persistence: p)
        let journalStore = JournalStore(persistence: p)
        let taskID = try await taskStore.create(title: "T")
        let entryID = try await journalStore.appendNote(taskID: taskID, body: "original")
        let view = p.container.viewContext

        await view.perform {
            view.automaticallyMergesChangesFromParent = false
            view.mergePolicy = NSMergePolicy.error
            let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
            req.predicate = NSPredicate(format: "id == %@", entryID as CVarArg)
            let m = try! view.fetch(req).first!
            m.body = "dirty-pin"
        }
        let bg = p.container.newBackgroundContext()
        await bg.perform {
            let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
            req.predicate = NSPredicate(format: "id == %@", entryID as CVarArg)
            let m = try! bg.fetch(req).first!
            m.body = "bg-edit"
            try! bg.save()
        }

        var threw = false
        do {
            try await journalStore.editNote(id: entryID, body: "view-edit")
        } catch {
            threw = true
        }
        #expect(threw == true)

        let hasChanges: Bool = await view.perform { view.hasChanges }
        #expect(hasChanges == false, "editNote's catch must roll back the shared viewContext")
    }
}
