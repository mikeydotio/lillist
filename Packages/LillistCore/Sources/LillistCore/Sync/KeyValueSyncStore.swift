import Foundation

/// Seam over `NSUbiquitousKeyValueStore` — the small, out-of-band iCloud
/// channel `DeviceRoster`/`ControlInbox` use to propagate a "reset
/// everywhere" signal to peer devices (issue #71).
///
/// This is a **separate iCloud subsystem from the Core Data/CloudKit
/// mirror** `NSPersistentCloudKitContainer` drives. That separation is
/// the whole point: issue #66 diagnosed a device whose CloudKit *export*
/// queue wedged for weeks on a bare `CKError.partialFailure`
/// (`CloudKitErrorClassifier.swift:64-71`) while imports kept succeeding
/// silently. A reset signal riding the same mirror would wedge right
/// alongside the data it's trying to help recover from. KVS uses a
/// different daemon and a different sync path, so it keeps working even
/// when the record mirror is stuck.
///
/// Values are opaque `Data` (JSON-encoded by callers) rather than `Any`,
/// so this protocol crosses actor boundaries cleanly under Swift 6
/// strict concurrency without touching non-`Sendable` `Any` payloads.
public protocol KeyValueSyncStore: Sendable {
    /// The raw value at `key`, or `nil` if absent.
    func data(forKey key: String) -> Data?
    /// Write `value` at `key`. Last-writer-wins under KVS's conflict
    /// resolution — callers must never have more than one writer for
    /// the same key (see `ControlInbox`'s per-event-key design).
    func set(_ value: Data, forKey key: String)
    /// Remove the value at `key`. Idempotent — removing an absent key
    /// is a no-op, not an error.
    func removeObject(forKey key: String)
    /// Every key currently present with the given prefix. Backed by a
    /// local cache (`NSUbiquitousKeyValueStore.dictionaryRepresentation`
    /// on the live conformer) — no network round-trip.
    func keys(withPrefix prefix: String) -> [String]
    /// Requests an opportunistic push of pending local changes. Returns
    /// whether a synchronization was queued, not whether it reached
    /// iCloud — KVS gives no synchronous delivery confirmation.
    @discardableResult func synchronize() -> Bool
}

/// Production conformer, backed by `NSUbiquitousKeyValueStore.default`.
///
/// `@unchecked Sendable`: `NSUbiquitousKeyValueStore` is documented safe
/// to call from any thread (like `UserDefaults`), and this wrapper holds
/// only an immutable reference to the shared singleton.
public struct LiveKeyValueSyncStore: KeyValueSyncStore, @unchecked Sendable {
    private let store: NSUbiquitousKeyValueStore

    public init(store: NSUbiquitousKeyValueStore = .default) {
        self.store = store
    }

    public func data(forKey key: String) -> Data? {
        store.data(forKey: key)
    }

    public func set(_ value: Data, forKey key: String) {
        store.set(value, forKey: key)
    }

    public func removeObject(forKey key: String) {
        store.removeObject(forKey: key)
    }

    public func keys(withPrefix prefix: String) -> [String] {
        store.dictionaryRepresentation.keys.filter { $0.hasPrefix(prefix) }
    }

    @discardableResult
    public func synchronize() -> Bool {
        store.synchronize()
    }
}

/// In-memory conformer for unit tests — no real iCloud round-trip.
/// Shipped in the main library (not the test target) so downstream
/// consumers can use it without `@testable import`, matching
/// `InMemoryMigrationJournalStore`'s precedent.
public final class InMemoryKeyValueSyncStore: KeyValueSyncStore, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()

    public init() {}

    public func data(forKey key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    public func set(_ value: Data, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = value
    }

    public func removeObject(forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }

    public func keys(withPrefix prefix: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage.keys.filter { $0.hasPrefix(prefix) }
    }

    @discardableResult
    public func synchronize() -> Bool {
        true
    }
}
