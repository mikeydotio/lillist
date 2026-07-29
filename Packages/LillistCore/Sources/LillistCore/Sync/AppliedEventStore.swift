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
    /// Data-sync-hardening `S22`: bounds growth. A personal account's reset
    /// events are rare, deliberate, user-initiated actions — 200 is
    /// generous headroom while guaranteeing this store can never grow
    /// unbounded across a device's whole lifetime. Oldest entries are
    /// evicted first once the cap is exceeded; eviction only ever discards
    /// the crash-recovery/efficiency memory for a long-past event whose
    /// `ControlInbox` entry has almost certainly already been acknowledged
    /// and removed by every recipient anyway — this store is not a
    /// correctness requirement (see the type's own header comment above).
    public static let capacity = 200

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
        ids.removeAll { $0 == id.uuidString }
        ids.append(id.uuidString)
        if ids.count > Self.capacity {
            ids.removeFirst(ids.count - Self.capacity)
        }
        defaults.set(ids, forKey: Self.userDefaultsKey)
    }

    /// Ordered oldest-first so `markApplied` can evict from the front.
    /// `Set` (the prior storage shape) has no ordering to evict by.
    private func storedIDs() -> [String] {
        defaults.stringArray(forKey: Self.userDefaultsKey) ?? []
    }
}
