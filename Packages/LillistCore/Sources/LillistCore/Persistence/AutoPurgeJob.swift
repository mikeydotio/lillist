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
        // Chunked managed-object-context deletes (TrashPurger), never
        // NSBatchDeleteRequest — batch deletes bypass
        // NSPersistentCloudKitContainer's export tracking (C4/X4).
        return try await TrashPurger.purge(
            predicateFormat: "deletedAt != nil AND deletedAt < %@",
            arguments: [cutoff],
            context: persistence.makeBackgroundContext(),
            viewContext: persistence.container.viewContext
        )
    }
}
