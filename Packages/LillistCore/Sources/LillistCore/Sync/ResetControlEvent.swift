import Foundation

/// A cross-device instruction propagated over `ControlInbox` (issue
/// #71): "converge to current iCloud state" — either because the
/// initiator wiped everything to empty, or because it re-seeded the
/// account from its own data. Peers react identically either way (see
/// `ResetSignalMonitor`); `kind` exists for provenance/diagnostics, not
/// to change the peer's reaction.
public struct ResetControlEvent: Sendable, Equatable, Codable {
    /// What the initiator did before broadcasting. Both cases resolve
    /// to the same peer action (`DataStoreResetService.resetAndRedownload()`)
    /// — the peer just re-imports whatever is in the zone when it runs,
    /// which differs only in *what data* is there by the time it acts.
    public enum Kind: String, Sendable, Equatable, Codable {
        /// The initiator erased local + iCloud data to empty.
        case resetToEmpty
        /// The initiator replaced iCloud with a fresh export of its own
        /// data (issue #71's "restore all from this device").
        case resetAndReseed
    }

    /// Unique per logical event. The same ID is reused across every
    /// recipient a single broadcast fans out to (see `ControlInbox.send`)
    /// so they're correlatable as one event, while still guaranteeing
    /// each `(recipient, id)` pair is a distinct KVS key.
    public let id: UUID
    public let kind: Kind
    public let senderDeviceID: String
    public let senderDisplayName: String
    public let requestedAt: Date

    public init(
        id: UUID = UUID(),
        kind: Kind,
        senderDeviceID: String,
        senderDisplayName: String,
        requestedAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.senderDeviceID = senderDeviceID
        self.senderDisplayName = senderDisplayName
        self.requestedAt = requestedAt
    }
}
