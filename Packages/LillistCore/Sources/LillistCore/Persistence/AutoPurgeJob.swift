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
        let ctx = persistence.makeBackgroundContext()
        let viewContext = persistence.container.viewContext
        let deletedIDs: [NSManagedObjectID] = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "deletedAt != nil AND deletedAt < %@", cutoff as NSDate)
            let victims = try ctx.fetch(req)
            // Batch delete skips Cascade rules, so expand victims to the full
            // cascade closure and delete it entity-by-entity (a single batch
            // is restricted to one entity). The IDs are merged into the
            // viewContext below.
            let ids = CascadeReaper.objectIDs(forDeleting: victims)
            return try CascadeReaper.batchDelete(objectIDs: ids, in: ctx)
        }
        guard !deletedIDs.isEmpty else { return 0 }
        await viewContext.perform {
            NSManagedObjectContext.mergeChanges(
                fromRemoteContextSave: [NSDeletedObjectsKey: deletedIDs],
                into: [viewContext]
            )
        }
        return await ctx.perform {
            deletedIDs.filter { $0.entity.name == "LillistTask" }.count
        }
    }
}
