import Testing
import Foundation
import CoreData
@testable import LillistCore

@Suite("AutoPurgeJob")
struct AutoPurgeJobTests {
    @Test("Old soft-deleted tasks are hard-deleted")
    func purgesOld() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let prefs = PreferencesStore(persistence: p)
        try await prefs.update { $0.trashRetentionDays = 30 }

        let id = try await tasks.create(title: "old")
        try await tasks.softDelete(id: id)

        try await p.container.viewContext.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            let m = try p.container.viewContext.fetch(req).first!
            m.deletedAt = Date().addingTimeInterval(-31 * 86400)
            try p.container.viewContext.save()
        }

        let job = AutoPurgeJob(persistence: p, preferences: prefs)
        let purged = try await job.run(now: Date())
        #expect(purged == 1)
        await #expect(throws: LillistError.notFound) {
            _ = try await tasks.fetch(id: id)
        }
    }

    @Test("Recently soft-deleted tasks survive")
    func sparesRecent() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let prefs = PreferencesStore(persistence: p)
        try await prefs.update { $0.trashRetentionDays = 30 }

        let id = try await tasks.create(title: "fresh")
        try await tasks.softDelete(id: id)

        let job = AutoPurgeJob(persistence: p, preferences: prefs)
        let purged = try await job.run(now: Date())
        #expect(purged == 0)
        _ = try await tasks.fetch(id: id)
    }

    @Test("Non-deleted tasks are never purged")
    func ignoresLiveTasks() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let prefs = PreferencesStore(persistence: p)
        try await prefs.update { $0.trashRetentionDays = 30 }
        _ = try await tasks.create(title: "live")
        let job = AutoPurgeJob(persistence: p, preferences: prefs)
        let purged = try await job.run(now: Date())
        #expect(purged == 0)
    }
}
