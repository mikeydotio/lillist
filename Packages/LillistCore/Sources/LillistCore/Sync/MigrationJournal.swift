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
///    non-idle. Recovery uses `lastHeartbeatAt` against
///    `staleThreshold` (well above the 300s sync-quiesce hard
///    timeout) to classify the state as "stale and recoverable"
///    instead of "another in-flight migration; back off." Only the
///    main-app recovery sheet acts on staleness — `MigrationGate`
///    still aborts headless callers on any non-idle journal.
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
    /// On-disk folder name (under `<root>/Quarantine/`) of the backup
    /// created during `.quarantining`, so the recovery flow can restore
    /// the *exact* archive (sync-7). Replaced the prior opaque
    /// `quarantineBackupID: UUID` which was never tied to the folder.
    public var quarantineFolderName: String?

    public init(
        state: State = .idle,
        operation: ModeTransitionOp? = nil,
        startedAt: Date? = nil,
        lastHeartbeatAt: Date? = nil,
        previousMode: SyncMode? = nil,
        failureReason: String? = nil,
        quarantineFolderName: String? = nil
    ) {
        self.state = state
        self.operation = operation
        self.startedAt = startedAt
        self.lastHeartbeatAt = lastHeartbeatAt
        self.previousMode = previousMode
        self.failureReason = failureReason
        self.quarantineFolderName = quarantineFolderName
    }

    private enum CodingKeys: String, CodingKey {
        case state, operation, startedAt, lastHeartbeatAt
        case previousMode, failureReason
        case quarantineFolderName
        // Legacy key from the pre-hardening build; decoded but ignored
        // (the UUID was never tied to a folder, so it can't drive a
        // restore — recovery falls back to latestQuarantinedStore).
        case quarantineBackupID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.state = try c.decode(State.self, forKey: .state)
        self.operation = try c.decodeIfPresent(ModeTransitionOp.self, forKey: .operation)
        self.startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        self.lastHeartbeatAt = try c.decodeIfPresent(Date.self, forKey: .lastHeartbeatAt)
        self.previousMode = try c.decodeIfPresent(SyncMode.self, forKey: .previousMode)
        self.failureReason = try c.decodeIfPresent(String.self, forKey: .failureReason)
        self.quarantineFolderName = try c.decodeIfPresent(String.self, forKey: .quarantineFolderName)
        // quarantineBackupID is read-tolerant (decoded and discarded) for
        // back-compat with journals written before this rename. The old
        // field was UUID-typed; decode it as such and ignore the value.
        _ = try c.decodeIfPresent(UUID.self, forKey: .quarantineBackupID)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(state, forKey: .state)
        try c.encodeIfPresent(operation, forKey: .operation)
        try c.encodeIfPresent(startedAt, forKey: .startedAt)
        try c.encodeIfPresent(lastHeartbeatAt, forKey: .lastHeartbeatAt)
        try c.encodeIfPresent(previousMode, forKey: .previousMode)
        try c.encodeIfPresent(failureReason, forKey: .failureReason)
        try c.encodeIfPresent(quarantineFolderName, forKey: .quarantineFolderName)
        // quarantineBackupID is intentionally NOT encoded: the legacy key
        // is only read (for back-compat) and never written — clean
        // forward writes, tolerant back-reads.
    }

    public static let idle = MigrationJournal(state: .idle)

    /// Whether the journal represents an in-flight (or crashed)
    /// migration that the app should not start a new one on top of.
    public var isInFlight: Bool { state != .idle }

    /// Default staleness window. Deliberately above the 300s
    /// `waitForQuiesce` hard timeout in `MigrationCoordinator` so a
    /// genuinely-running migration (which can legitimately sit in
    /// `.awaitingSync` for up to 5 minutes) is never misclassified as
    /// crashed. 600s = 2× the quiesce ceiling, leaving slack for the
    /// surrounding phases.
    public static let staleThreshold: TimeInterval = 600

    /// Whether an in-flight journal is *stale* — i.e. its owning process
    /// almost certainly crashed rather than still running. An idle
    /// journal is never stale. Staleness is measured from
    /// `lastHeartbeatAt` when present, falling back to `startedAt`, and
    /// finally treating a timestamp-less in-flight journal as stale
    /// (it can't be a live heartbeat-emitting migration).
    ///
    /// Consumed **only** by the main-app recovery sheet to decide whether
    /// to offer restore-from-backup. `MigrationGate` ignores staleness and
    /// aborts headless callers on any non-idle journal.
    public func isStale(now: Date = Date(), threshold: TimeInterval = MigrationJournal.staleThreshold) -> Bool {
        guard isInFlight else { return false }
        guard let reference = lastHeartbeatAt ?? startedAt else { return true }
        return now.timeIntervalSince(reference) > threshold
    }
}
