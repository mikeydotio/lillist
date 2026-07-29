import Foundation

/// Local (never synced) record of `ControlInbox` entries that failed to
/// decode as a `ResetControlEvent` (data-sync-hardening `S22`).
///
/// Without this, a corrupt or future-schema payload from a peer would sit
/// in the `NSUbiquitousKeyValueStore` inbox forever: `ControlInbox
/// .pendingEvents(for:)` silently `compactMap`s past anything undecodable
/// (a corrupt entry must never crash a scan), which means nothing ever
/// notices it, and nothing ever removes it — the entry has no `id` to
/// acknowledge by. `ResetSignalMonitor` instead discovers these via
/// `ControlInbox.undecodableKeys(for:)`, discards them from the live
/// inbox, and records a copy here.
///
/// Diagnostic only, matching `AppliedEventStore`'s exact shape
/// (`UserDefaults`-backed, `.standard` suite convention, lock-protected):
/// nothing ever reads this back to retry. It exists so a corrupt-payload
/// class of bug is at least discoverable rather than silently invisible —
/// the actual defect `S22` reports.
public final class ResetEventDeadLetterStore: @unchecked Sendable {
    /// One quarantined entry: the raw `ControlInbox` key (not a decoded
    /// event — by definition, this payload didn't decode) and when it was
    /// discarded.
    public struct Entry: Sendable, Equatable, Codable {
        public let key: String
        public let discardedAt: Date

        public init(key: String, discardedAt: Date) {
            self.key = key
            self.discardedAt = discardedAt
        }
    }

    private static let userDefaultsKey = "app.lillist.resetEventDeadLetters"
    /// Bounds growth the same way `AppliedEventStore.capacity` does, for the
    /// same reason: a personal account's corrupt-payload events should be
    /// vanishingly rare, so this cap is generous headroom, not a
    /// realistically-reachable ceiling.
    public static let capacity = 50

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Record `key` as quarantined. Oldest entries are evicted first once
    /// `capacity` is exceeded.
    public func record(key: String, discardedAt: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        var entries = storedEntries()
        entries.append(Entry(key: key, discardedAt: discardedAt))
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
        persist(entries)
    }

    /// Every currently-recorded dead letter, oldest first.
    public func recent() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return storedEntries()
    }

    private func storedEntries() -> [Entry] {
        guard let data = defaults.data(forKey: Self.userDefaultsKey) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private func persist(_ entries: [Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.userDefaultsKey)
    }
}
