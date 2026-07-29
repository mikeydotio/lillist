import Testing
import Foundation
import CoreData
@testable import LillistCore

/// H5: `SeriesStore` had no rollback discipline at all — every mutating
/// method called `context.save()` with no surrounding `do`/`catch`.
@Suite("SeriesStore rollback on save failure")
struct SeriesStoreRollbackTests {
    @Test("A failed update rolls the viewContext back")
    func updateRollsBack() async throws {
        let p = try await TestStore.make()
        let taskStore = TaskStore(persistence: p)
        let seriesStore = SeriesStore(persistence: p)
        let taskID = try await taskStore.create(title: "Recurring")
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        let seriesID = try await seriesStore.create(fromSeedTask: taskID, rule: rule)
        let view = p.container.viewContext

        // Pin viewContext at v1 with a pending change + error policy — the
        // same technique TaskStoreRollbackTests uses. The store's own
        // `update` call below re-fetches this same cached, already-dirty
        // managed object (Core Data dedupes by objectID within one context).
        await view.perform {
            view.automaticallyMergesChangesFromParent = false
            view.mergePolicy = NSMergePolicy.error
            let req = NSFetchRequest<Series>(entityName: "Series")
            req.predicate = NSPredicate(format: "id == %@", seriesID as CVarArg)
            let m = try! view.fetch(req).first!
            m.nextOccurrenceAfter = Date(timeIntervalSince1970: 0)
        }
        // Bump the row to v2 from a background context.
        let bg = p.container.newBackgroundContext()
        await bg.perform {
            let req = NSFetchRequest<Series>(entityName: "Series")
            req.predicate = NSPredicate(format: "id == %@", seriesID as CVarArg)
            let m = try! bg.fetch(req).first!
            try! m.setRule(RecurrenceRule.calendar(.init(freq: .weekly, interval: 2)))
            try! bg.save()
        }

        var threw = false
        do {
            try await seriesStore.update(id: seriesID, rule: RecurrenceRule.calendar(.init(freq: .daily, interval: 5)))
        } catch {
            threw = true
        }
        #expect(threw == true)

        let hasChanges: Bool = await view.perform { view.hasChanges }
        #expect(hasChanges == false, "update's catch must roll back the shared viewContext")
    }
}
