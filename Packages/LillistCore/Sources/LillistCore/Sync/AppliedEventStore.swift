import Foundation

/// Local (never synced) record of which `ResetControlEvent` IDs this
/// device has already applied.
///
/// Purely a crash-recovery/efficiency aid, not a correctness
/// requirement: `resetAndRedownload()` is idempotent, so re-applying an
/// event is harmless, just wasteful and visibly disruptive (a redundant
/// "resetting…" cycle). This lets `ResetSignalMonitor` recognize "I
/// already did this, just retry the acknowledgement" after a crash
/// between applying an event and deleting its `ControlInbox` entry.
///
/// `UserDefaults`-backed, matching `DeviceFingerprint`'s existing
/// `.standard`-suite convention (`Notifications/DeviceFingerprint.swift`)
/// — both are consumed only by the main app process, so no App Group
/// sharing is needed.
public final class AppliedEventStore: @unchecked Sendable {
    private static let userDefaultsKey = "app.lillist.appliedResetEventIDs"

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func hasApplied(_ id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedIDs().contains(id.uuidString)
    }

    public func markApplied(_ id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        var ids = storedIDs()
        ids.insert(id.uuidString)
        defaults.set(Array(ids), forKey: Self.userDefaultsKey)
    }

    private func storedIDs() -> Set<String> {
        Set(defaults.stringArray(forKey: Self.userDefaultsKey) ?? [])
    }
}
