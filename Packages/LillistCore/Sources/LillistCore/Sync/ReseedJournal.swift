import Foundation

/// Structured, JSON-serializable record of an in-progress
/// `DataStoreResetService.resetAndReseedFromThisDevice()` (data-sync-hardening
/// `S9b`).
///
/// Deliberately a **separate type from `MigrationJournal`**, not a new case
/// grafted onto it: `DataStoreResetService`'s own header comment already
/// states the constraint this journal exists to honor — a reset "must
/// **not** touch the `MigrationJournal`, whose invariants (`previousMode`,
/// restore-reverts-mode) are transition-shaped." A reseed never changes
/// `SyncMode` and its recovery action ("resume importing the staged
/// bundle") is categorically different from a migration's ("restore a
/// quarantined SQLite file and revert `previousMode`") — reusing
/// `MigrationJournal` would force a mode-revert-shaped recovery UI onto an
/// operation that has no mode to revert.
public struct ReseedJournal: Codable, Sendable, Equatable {
    public enum Phase: String, Codable, Sendable {
        case idle
        /// Exporting the current store to `stagedBundlePath`. The live
        /// store has not been touched yet.
        case exporting
        /// Wiping local + iCloud (`DataStoreResetService.performReset`).
        case wiping
        /// Re-importing `stagedBundlePath` into the freshly-wiped store.
        case importing
        case failed
    }

    public var phase: Phase
    public var startedAt: Date?
    public var lastHeartbeatAt: Date?
    /// Durable filesystem path (under `QuarantineManager.rootDirectory`,
    /// NOT `FileManager.default.temporaryDirectory` — see `S9b`) of the
    /// staged export bundle. Present once `.exporting` completes.
    public var stagedBundlePath: String?
    /// True once the destructive wipe step (`performReset`) has
    /// completed. This — not `phase` — is what recovery branches on: it
    /// answers the one question that actually matters ("does the live
    /// store still hold the pre-reseed data, or is `stagedBundlePath` the
    /// only remaining copy?") without depending on `phase`'s exact naming
    /// staying in sync with that meaning across future edits.
    public var localDataWiped: Bool
    public var failureReason: String?

    public init(
        phase: Phase = .idle,
        startedAt: Date? = nil,
        lastHeartbeatAt: Date? = nil,
        stagedBundlePath: String? = nil,
        localDataWiped: Bool = false,
        failureReason: String? = nil
    ) {
        self.phase = phase
        self.startedAt = startedAt
        self.lastHeartbeatAt = lastHeartbeatAt
        self.stagedBundlePath = stagedBundlePath
        self.localDataWiped = localDataWiped
        self.failureReason = failureReason
    }

    public static let idle = ReseedJournal(phase: .idle)

    /// Whether the journal represents an in-flight (or crashed) reseed
    /// that a fresh launch should investigate before assuming steady
    /// state.
    public var isInFlight: Bool { phase != .idle }
}
