import Foundation

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
    /// every other currently-known device. A no-op (besides the roster
    /// refresh) when this is the only known device — there is nobody to
    /// notify yet. Best-effort: `NSUbiquitousKeyValueStore`'s own API
    /// gives no synchronous delivery confirmation to propagate as a
    /// thrown error, so this never throws.
    public func broadcast(_ kind: ResetControlEvent.Kind, now: Date = Date()) {
        roster.register(id: deviceID, displayName: deviceDisplayName, now: now)
        let peers = roster.knownPeers(excluding: deviceID)
        guard !peers.isEmpty else { return }
        let event = ResetControlEvent(
            kind: kind,
            senderDeviceID: deviceID,
            senderDisplayName: deviceDisplayName,
            requestedAt: now
        )
        inbox.send(event, to: peers)
    }
}
