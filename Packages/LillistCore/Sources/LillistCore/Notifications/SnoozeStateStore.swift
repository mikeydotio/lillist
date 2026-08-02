import Foundation

/// Per-device snooze state, kept in App Group `UserDefaults`.
///
/// `LIL-90`: snooze used to live on the synced `NotificationSpec` row. That was
/// the only thing making a remote **in-place** spec edit reachable — and
/// `RemoteChangeReconciler` does not see in-place spec edits, so a snooze from
/// another device silently failed to reschedule here. Moving snooze off the
/// synced entity makes that failure *unrepresentable* rather than merely
/// unreachable, which is the stronger fix.
///
/// It is also the honest model. A snooze is a statement about *this device's
/// current notification* ("not now, show me again in 10 minutes"), not about
/// what the user wants a reminder to mean. Intent syncs; machinery does not.
///
/// No user-visible regression: `lastFiredAt` already means only one device shows
/// a given reminder. The user snoozes on that device, the snooze re-fires on
/// that device, and the others — already suppressed — stay quiet.
///
/// Same App Group as ``DevicePreferencesStore``, so every process (app,
/// extensions, CLI) agrees on snooze state within one device.
public actor SnoozeStateStore {
    private let defaults: UserDefaults

    private static let keyPrefix = "lillist.snooze."

    /// - Parameter appGroupID: App Group shared by the app, its extensions, and
    ///   the CLI. Falls back to `.standard` when the group is unreachable (e.g.
    ///   tests outside a signed sandbox), matching ``DevicePreferencesStore``.
    public init(appGroupID: String) {
        self.defaults = UserDefaults(suiteName: appGroupID) ?? .standard
    }

    /// Test/preview seam — see ``DevicePreferencesStore/init(suiteName:)`` for
    /// why this takes a name rather than a `UserDefaults` instance.
    public init(suiteName: String) {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    private static func key(_ specID: UUID) -> String { keyPrefix + specID.uuidString }

    /// The instant this spec is snoozed until, or `nil` if it is not snoozed.
    ///
    /// An elapsed snooze is treated as absent *and cleaned up on read*, so a
    /// long-dismissed snooze cannot accumulate. Callers therefore never need to
    /// compare against `Date()` themselves.
    public func snoozedUntil(specID: UUID, now: Date = Date()) -> Date? {
        let key = Self.key(specID)
        guard let stored = defaults.object(forKey: key) as? Date else { return nil }
        guard stored > now else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return stored
    }

    /// Snooze `specID` until `date`. A `nil` or already-elapsed `date` clears it.
    public func setSnoozedUntil(_ date: Date?, specID: UUID, now: Date = Date()) {
        guard let date, date > now else {
            defaults.removeObject(forKey: Self.key(specID))
            return
        }
        defaults.set(date, forKey: Self.key(specID))
    }

    public func clear(specID: UUID) {
        defaults.removeObject(forKey: Self.key(specID))
    }

    /// Drop snooze entries whose spec no longer exists.
    ///
    /// Deleting a reminder cannot reach into this store (the delete happens in
    /// Core Data, possibly on another device), so without a sweep a deleted
    /// spec's key would linger forever. Cheap and idempotent; call it from the
    /// same maintenance pass that reconciles notifications.
    public func prune(liveSpecIDs: Set<UUID>) {
        let live = Set(liveSpecIDs.map(Self.key))
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(Self.keyPrefix) && live.contains(key) == false {
            defaults.removeObject(forKey: key)
        }
    }

    /// Every spec id currently carrying a live snooze. Test/diagnostic use.
    public func snoozedSpecIDs(now: Date = Date()) -> Set<UUID> {
        var out: Set<UUID> = []
        for (key, value) in defaults.dictionaryRepresentation()
        where key.hasPrefix(Self.keyPrefix) {
            guard let date = value as? Date, date > now else { continue }
            let raw = String(key.dropFirst(Self.keyPrefix.count))
            if let id = UUID(uuidString: raw) { out.insert(id) }
        }
        return out
    }
}
