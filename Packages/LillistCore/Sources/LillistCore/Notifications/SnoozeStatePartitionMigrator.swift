import Foundation
import CoreData

/// Copies any live `NotificationSpec.snoozedUntil` values out of Core Data into
/// the device-local ``SnoozeStateStore``, once.
///
/// `LIL-90`: snooze moved off the synced entity. Without this pass, a user who
/// had a reminder snoozed at upgrade time would find it firing immediately —
/// the new code reads the local store, which is empty, so the snooze silently
/// evaporates. The same partition-then-migrate shape as
/// ``AppPreferencesPartitionMigrator``.
///
/// Idempotent: guarded by a marker in ``DevicePreferencesStore``, so it costs a
/// flag check on every launch after the first.
///
/// Only *live* snoozes are carried over. An elapsed `snoozedUntil` is already
/// inert — copying it would just make ``SnoozeStateStore`` clean it up on first
/// read, so it is skipped here instead.
///
/// The Core Data column is deliberately left in place and untouched. CloudKit
/// cannot remove a field from a deployed schema, and peers still running the
/// previous build continue to write it; this device simply stops reading it
/// after the migration. Their writes become inert rather than harmful.
public struct SnoozeStatePartitionMigrator: Sendable {
    private let persistence: PersistenceController
    private let snoozeState: SnoozeStateStore
    private let devicePreferences: DevicePreferencesStore

    public init(
        persistence: PersistenceController,
        snoozeState: SnoozeStateStore,
        devicePreferences: DevicePreferencesStore
    ) {
        self.persistence = persistence
        self.snoozeState = snoozeState
        self.devicePreferences = devicePreferences
    }

    @discardableResult
    public func runIfNeeded(now: Date = Date()) async throws -> Outcome {
        if await devicePreferences.snoozeMigrationCompleted {
            return .alreadyMigrated
        }

        let context = persistence.container.viewContext
        let live: [(UUID, Date)] = try await context.perform {
            let req = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
            req.predicate = NSPredicate(format: "snoozedUntil != nil AND snoozedUntil > %@", now as NSDate)
            return try context.fetch(req).compactMap { spec in
                guard let id = spec.id, let until = spec.snoozedUntil else { return nil }
                return (id, until)
            }
        }

        for (specID, until) in live {
            await snoozeState.setSnoozedUntil(until, specID: specID, now: now)
        }
        await devicePreferences.markSnoozeMigrationCompleted()
        return .migrated(count: live.count)
    }

    public enum Outcome: Sendable, Equatable {
        case alreadyMigrated
        case migrated(count: Int)
    }
}
