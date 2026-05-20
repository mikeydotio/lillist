import Foundation

/// A high-level sync-mode change. Used by `MigrationJournal` and
/// `MigrationCoordinator` to record what kind of transition is in
/// flight so a crashed-app recovery flow knows what was being attempted.
public enum ModeTransitionOp: String, Codable, Sendable {
    /// Switch LocalOnly → iCloudSync, replacing whatever is in iCloud
    /// with this device's local data.
    case replaceICloudWithLocal
    /// Switch LocalOnly → iCloudSync, replacing this device's local
    /// data with what's in iCloud.
    case replaceLocalWithICloud
    /// Switch iCloudSync → LocalOnly, syncing once before disconnect.
    case syncFirstThenDisable
    /// Switch iCloudSync → LocalOnly without a final sync.
    case disableNow
}

/// Structured, JSON-serializable record of an in-progress sync-mode
/// migration.
///
/// Plan 21 uses a file-backed journal (not a `UserDefaults` bool)
/// because:
///
/// 1. **Atomic cross-process visibility.** `UserDefaults` writes go
///    through a flush boundary that isn't immediate to other processes;
///    a journal file written via `Data.write(to:options: .atomic)` is
///    visible to readers as soon as the rename returns.
/// 2. **Failure-mode richness.** The recovery flow needs to know
///    *which* operation crashed (replace-iCloud vs replace-local vs
///    disable), *when* the heartbeat last fired, and *which*
///    quarantine backup to restore from. A bool can't carry that.
/// 3. **Heartbeat semantics.** A crashed process leaves the journal
///    non-idle. Recovery uses `lastHeartbeatAt > 30s ago` to classify
///    the state as "stale and recoverable" instead of "another
///    in-flight migration; back off."
public struct MigrationJournal: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable {
        case idle
        case preparing
        case quarantining
        case mutatingCloudKit
        case reconfiguringStore
        case awaitingSync
        case finalizing
        case failed
    }

    public var state: State
    public var operation: ModeTransitionOp?
    public var startedAt: Date?
    public var lastHeartbeatAt: Date?
    /// The mode we're transitioning *from*. Recovery uses this to
    /// revert when restoring from the quarantine backup.
    public var previousMode: SyncMode?
    public var failureReason: String?
    /// Identifier of the quarantined backup (created during
    /// `.quarantining`) so the recovery flow knows which archive to
    /// restore.
    public var quarantineBackupID: UUID?

    public init(
        state: State = .idle,
        operation: ModeTransitionOp? = nil,
        startedAt: Date? = nil,
        lastHeartbeatAt: Date? = nil,
        previousMode: SyncMode? = nil,
        failureReason: String? = nil,
        quarantineBackupID: UUID? = nil
    ) {
        self.state = state
        self.operation = operation
        self.startedAt = startedAt
        self.lastHeartbeatAt = lastHeartbeatAt
        self.previousMode = previousMode
        self.failureReason = failureReason
        self.quarantineBackupID = quarantineBackupID
    }

    public static let idle = MigrationJournal(state: .idle)

    /// Whether the journal represents an in-flight (or crashed)
    /// migration that the app should not start a new one on top of.
    public var isInFlight: Bool { state != .idle }
}
