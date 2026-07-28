import Foundation
import CoreData

/// Hard-deletes soft-deleted tasks (and their cascades) older than the
/// configured retention. Returns the count of top-level tasks purged.
public final class AutoPurgeJob: @unchecked Sendable {
    private let persistence: PersistenceController
    private let preferences: PreferencesStore

    /// H3: optional-injected, same pattern as `TaskStore.notificationScheduler`
    /// — set by the app's composition root, `nil` in tests that don't care
    /// about notifications, in which case the cancellation call is a no-op.
    public var notificationScheduler: (any NotificationReconciling)?

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
            viewContext: persistence.container.viewContext,
            notificationScheduler: notificationScheduler
        )
    }
}
