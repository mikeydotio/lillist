import Foundation

/// One device's self-published entry in the roster — a display name and
/// last-seen timestamp so confirmation/diagnostic copy can say "Reset
/// requested by Nephele" instead of a bare identifier.
public struct RosterEntry: Sendable, Equatable, Codable {
    public let id: String
    public let displayName: String
    public let lastSeenAt: Date

    public init(id: String, displayName: String, lastSeenAt: Date) {
        self.id = id
        self.displayName = displayName
        self.lastSeenAt = lastSeenAt
    }
}

/// Self-registering roster of devices on this iCloud account, backed by
/// `KeyValueSyncStore` (issue #71).
///
/// Each device writes **only its own** `device.<id>` entry — never
/// another device's — so registration is race-free by construction: KVS
/// has no compare-and-swap and resolves same-key conflicts by
/// last-writer-wins, which would silently drop updates if two devices
/// ever wrote the same key. A single-writer-per-key discipline sidesteps
/// that entirely (the same principle `ControlInbox` uses for events).
///
/// There is no explicit "leave the group" — a device that's retired
/// just stops refreshing its entry. Roster entries are small and device
/// counts stay in the single digits for a personal account, so stale
/// entries are a negligible, undocumented-but-acceptable residual
/// against KVS's 1 MB / 1024-key budget.
public struct DeviceRoster: Sendable {
    private static let keyPrefix = "device."

    private let kv: any KeyValueSyncStore

    public init(kv: any KeyValueSyncStore) {
        self.kv = kv
    }

    private static func key(for id: String) -> String {
        keyPrefix + id
    }

    /// Publish (or refresh) this device's own roster entry. Safe to call
    /// repeatedly — each call simply overwrites this device's own key.
    public func register(id: String, displayName: String, now: Date = Date()) {
        let entry = RosterEntry(id: id, displayName: displayName, lastSeenAt: now)
        guard let data = try? Self.encode(entry) else { return }
        kv.set(data, forKey: Self.key(for: id))
        kv.synchronize()
    }

    /// Every other device's currently-published roster entry. Reads a
    /// local cache (`KeyValueSyncStore.keys(withPrefix:)`) — no network
    /// round-trip.
    public func knownPeers(excluding selfID: String) -> [RosterEntry] {
        let selfKey = Self.key(for: selfID)
        return kv.keys(withPrefix: Self.keyPrefix)
            .filter { $0 != selfKey }
            .compactMap { key in kv.data(forKey: key).flatMap { try? Self.decode($0) } }
    }

    private static func encode(_ entry: RosterEntry) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(entry)
    }

    private static func decode(_ data: Data) throws -> RosterEntry {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RosterEntry.self, from: data)
    }
}
