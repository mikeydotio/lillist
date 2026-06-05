import Testing
import Foundation
import CoreData
@testable import LillistCore

@Suite("PersistenceController.background context")
struct BackgroundContextTests {
    @Test("makeBackgroundContext returns a private-queue context distinct from viewContext")
    func vendsPrivateQueueContext() async throws {
        let p = try await TestStore.make()
        let bg = p.makeBackgroundContext()
        #expect(bg !== p.container.viewContext)
        #expect(bg.concurrencyType == .privateQueueConcurrencyType)
    }

    @Test("makeBackgroundContext stamps the local transaction author")
    func stampsLocalAuthor() async throws {
        let p = try await TestStore.make()
        let bg = p.makeBackgroundContext()
        #expect(bg.transactionAuthor == PersistenceController.localTransactionAuthor)
    }

    @Test("background-context saves merge into the viewContext automatically")
    func bgSavesReachViewContext() async throws {
        let p = try await TestStore.make()
        let id = UUID()
        let bg = p.makeBackgroundContext()
        try await bg.perform {
            let t = LillistTask(context: bg)
            t.id = id
            t.title = "from-bg"
            t.createdAt = Date()
            try bg.save()
        }
        let title: String? = try await p.container.viewContext.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            return try p.container.viewContext.fetch(req).first?.title
        }
        #expect(title == "from-bg")
    }
}
