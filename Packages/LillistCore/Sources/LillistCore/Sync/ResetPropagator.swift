import Foundation

/// What happened when a destructive reset tried to notify peer devices
/// (data-sync-hardening `S20`) — returned by every propagating reset
/// method so the UI can tell the user "no other devices were notified"
/// instead of silently implying every device will converge.
///
/// Also serves data-sync-hardening `S9c`'s distinct failure shape
/// (`.skippedQuiesceTimedOut`): both findings share the same underlying
/// UI-facing need — "the destructive op itself succeeded locally, but
/// peers were not told" — just for different reasons (nobody to tell vs.
/// telling them now would be premature).
public enum BroadcastOutcome: Sendable, Equatable {
    /// No `ResetPropagator` was configured (test/legacy caller) — not
    /// attempted.
    case notConfigured
    /// At least one known peer was sent the event.
    case notified(peerCount: Int)
    /// No other device is known yet (e.g. a fresh install, or every other
    /// device has never registered in the roster) — the wipe/reseed still
    /// completed locally, but nobody was told to converge.
    case rosterEmpty
    /// Data-sync-hardening `S9c`: the re-export never quiesced within the
    /// timeout, so broadcasting was skipped — telling a peer to redownload
    /// now could pull a partial zone, mid-upload. The reset/reseed itself
    /// still completed locally.
    case skippedQuiesceTimedOut
}

/// Bundles "notify the rest of this iCloud account's devices that a
/// reset happened" into one injectable dependency for
/// `DataStoreResetService` (issue #71), instead of threading
/// `DeviceRoster`/`ControlInbox`/device-identity through separately.
public struct ResetPropagator: Sendable {
    private let roster: DeviceRoster
    private let inbox: ControlInbox
    private let deviceID: String
    private let deviceDisplayName: String

    public init(
        roster: DeviceRoster,
        inbox: ControlInbox,
        deviceID: String,
        deviceDisplayName: String
    ) {
        self.roster = roster
        self.inbox = inbox
        self.deviceID = deviceID
        self.deviceDisplayName = deviceDisplayName
    }

    /// Refresh this device's own roster entry, then fan out `kind` to
    /// every other currently-known device. Reports whether anybody was
    /// actually notified (data-sync-hardening `S20`) instead of silently
    /// treating an empty roster as success. Best-effort: `NSUbiquitousKeyValueStore`'s
    /// own API gives no synchronous delivery confirmation to propagate as
    /// a thrown error, so this never throws.
    @discardableResult
    public func broadcast(_ kind: ResetControlEvent.Kind, now: Date = Date()) -> BroadcastOutcome {
        roster.register(id: deviceID, displayName: deviceDisplayName, now: now)
        let peers = roster.knownPeers(excluding: deviceID)
        guard !peers.isEmpty else { return .rosterEmpty }
        let event = ResetControlEvent(
            kind: kind,
            senderDeviceID: deviceID,
            senderDisplayName: deviceDisplayName,
            requestedAt: now
        )
        inbox.send(event, to: peers)
        return .notified(peerCount: peers.count)
    }
}
