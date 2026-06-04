import Testing
import Foundation
import CoreData
@testable import LillistCore

/// Proves the exact `AutoPurgeJob.run()` invocation that
/// `AppEnvironment.bootstrap()` and the iOS BGProcessingTask handler make
/// actually hard-deletes an aged soft-deleted task. The app-target
/// bootstrap call cannot be unit-tested directly (the standalone iOS test
/// bundle has no app host), so this LillistCore test stands in as the
/// behavioral contract the launch path relies on.
@Suite("AutoPurge launch contract")
struct AutoPurgeLaunchTests {
    @Test("run() at launch purges a task aged past retention")
    func launchPurgePurgesAgedTask() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let prefs = PreferencesStore(persistence: p)
        try await prefs.update { $0.trashRetentionDays = 30 }

        let id = try await tasks.create(title: "stale-trash")
        try await tasks.softDelete(id: id)
        try await p.container.viewContext.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            let m = try p.container.viewContext.fetch(req).first!
            m.deletedAt = Date().addingTimeInterval(-31 * 86400)
            try p.container.viewContext.save()
        }

        // Exactly what AppEnvironment.bootstrap() / the BGTask handler do.
        let job = AutoPurgeJob(persistence: p, preferences: prefs)
        let purged = try await job.run()

        #expect(purged == 1)
        await #expect(throws: LillistError.notFound) {
            _ = try await tasks.fetch(id: id)
        }
    }

    @Test("run() at launch is a no-op when the trash is fresh")
    func launchPurgeSparesFreshTrash() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let prefs = PreferencesStore(persistence: p)
        try await prefs.update { $0.trashRetentionDays = 30 }

        let id = try await tasks.create(title: "recent-trash")
        try await tasks.softDelete(id: id)

        let job = AutoPurgeJob(persistence: p, preferences: prefs)
        let purged = try await job.run()
        #expect(purged == 0)
        _ = try await tasks.fetch(id: id)
    }
}
