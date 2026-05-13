import Foundation
import CoreData

/// Hard-deletes soft-deleted tasks (and their cascades) older than the
/// configured retention. Returns the count of top-level tasks purged.
public final class AutoPurgeJob: @unchecked Sendable {
    private let persistence: PersistenceController
    private let preferences: PreferencesStore

    public init(persistence: PersistenceController, preferences: PreferencesStore) {
        self.persistence = persistence
        self.preferences = preferences
    }

    @discardableResult
    public func run(now: Date = Date()) async throws -> Int {
        let prefs = try await preferences.read()
        let cutoff = now.addingTimeInterval(-Double(prefs.trashRetentionDays) * 86400)
        let ctx = persistence.container.viewContext
        return try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "deletedAt != nil AND deletedAt < %@", cutoff as NSDate)
            let victims = try ctx.fetch(req)
            for v in victims { ctx.delete(v) }
            try ctx.save()
            return victims.count
        }
    }
}
