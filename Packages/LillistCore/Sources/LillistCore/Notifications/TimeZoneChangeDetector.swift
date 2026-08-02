import Foundation
import CoreData

/// Detects that this device has moved to a different time zone, and re-anchors
/// reminders to it when the user says so — `LIL-83`.
///
/// Reminders store the zone the user was in when they scheduled them, so they
/// keep firing at their original wall-clock moment after travel. That is the
/// right default (a 9am medication reminder set in New York should not become
/// 6am because you flew to California), but it is not always what the user
/// wants — hence an offer rather than an automatic rewrite.
///
/// **Offer, never act unasked.** Both answers are legitimate, and the app cannot
/// know which the user means. Silently rewriting would be as wrong as silently
/// refusing.
///
/// Needs no permissions: `TimeZone.current` is free, unlike location.
public struct TimeZoneChangeDetector: Sendable {
    private let persistence: PersistenceController
    private let specStore: NotificationSpecStore
    private let devicePreferences: DevicePreferencesStore

    public init(
        persistence: PersistenceController,
        specStore: NotificationSpecStore,
        devicePreferences: DevicePreferencesStore
    ) {
        self.persistence = persistence
        self.specStore = specStore
        self.devicePreferences = devicePreferences
    }

    /// A pending offer to re-anchor reminders.
    public struct Change: Sendable, Equatable {
        /// The zone the reminders are currently anchored to.
        public let from: TimeZone
        /// The zone this device is in now.
        public let to: TimeZone
        /// Specs that would move. Empty means nothing to offer.
        public let affectedSpecIDs: [UUID]

        public init(from: TimeZone, to: TimeZone, affectedSpecIDs: [UUID]) {
            self.from = from
            self.to = to
            self.affectedSpecIDs = affectedSpecIDs
        }
    }

    /// Check whether an offer is warranted.
    ///
    /// Call on **foreground**, not from `NSSystemTimeZoneDidChange`: a zone
    /// change mid-flight would otherwise prompt while the phone is in a pocket,
    /// and a short layover would prompt for a zone the user is about to leave.
    /// Foregrounding in the new zone is the signal that the user has arrived.
    ///
    /// Returns `nil` when there is nothing to ask about — first launch, no zone
    /// change, or a change that affects no reminder.
    public func check(now: Date = Date(), current: TimeZone = .current) async throws -> Change? {
        let previousID = await devicePreferences.lastKnownTimeZoneID()

        // First observation ever: record and stay silent. There is no "from"
        // zone to move away from, so there is nothing coherent to offer.
        guard let previousID else {
            await devicePreferences.setLastKnownTimeZoneID(current.identifier)
            return nil
        }
        guard previousID != current.identifier,
              let previous = TimeZone(identifier: previousID) else { return nil }

        let affected = try await reanchorableSpecIDs(now: now)
        guard affected.isEmpty == false else {
            // Nothing to move — accept the new zone silently rather than
            // asking a question whose answer changes nothing.
            await devicePreferences.setLastKnownTimeZoneID(current.identifier)
            return nil
        }
        return Change(from: previous, to: current, affectedSpecIDs: affected)
    }

    /// Re-anchor every affected reminder to `change.to`.
    ///
    /// Rewrites the synced `scheduledTimeZoneID`, so peers must reconcile —
    /// which is precisely why `LIL-90` widened
    /// ``RemoteChangeReconciler/scheduleAffectingSpecProperties`` to include it.
    /// Without that widening this method would move reminders on this device
    /// only, and the user's choice would be silently ignored everywhere else.
    @discardableResult
    public func accept(_ change: Change, reconciler: (any NotificationReconciling)? = nil) async throws -> Int {
        var taskIDs: Set<UUID> = []
        for specID in change.affectedSpecIDs {
            let before = try await specStore.fetch(id: specID)
            try await specStore.update(id: specID) { draft in
                draft.scheduledTimeZoneID = change.to.identifier
            }
            taskIDs.insert(before.taskID)
        }
        await devicePreferences.setLastKnownTimeZoneID(change.to.identifier)
        if let reconciler {
            for taskID in taskIDs { await reconciler.reconcile(taskID: taskID) }
        }
        return change.affectedSpecIDs.count
    }

    /// Keep reminders on their original zones, and stop asking about this move.
    public func decline(_ change: Change) async {
        await devicePreferences.setLastKnownTimeZoneID(change.to.identifier)
    }

    /// Specs eligible to be re-anchored: **future and unfired**.
    ///
    /// A reminder that already fired has done its job — moving it would re-arm
    /// it and fire a second time for the same event. A reminder whose anchor is
    /// in the past cannot usefully move either.
    private func reanchorableSpecIDs(now: Date) async throws -> [UUID] {
        let context = persistence.container.viewContext
        return try await context.perform {
            let req = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
            req.predicate = NSPredicate(format: "lastFiredAt == nil")
            req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            return try context.fetch(req).compactMap { spec -> UUID? in
                guard let id = spec.id else { return nil }
                guard let task = spec.task, task.deletedAt == nil else { return nil }
                // A nudge carries its own absolute fireDate; anchored kinds
                // derive theirs from the task, so use whichever exists.
                let anchor = spec.fireDate ?? task.start ?? task.deadline
                guard let anchor, anchor > now else { return nil }
                return id
            }
        }
    }
}
