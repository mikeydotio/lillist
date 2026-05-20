import Foundation

/// Persists the user's `SyncMode` choice in App Group `UserDefaults`
/// and exposes change notifications via an `AsyncStream`.
///
/// The store is small on purpose: every read returns the persisted
/// raw value (or the documented default when absent), every write is
/// a single `UserDefaults` set followed by a broadcast to every live
/// stream subscriber. There is no in-memory cache to drift; the
/// underlying defaults are the source of truth and the App Group
/// guarantees cross-process visibility (with the usual UserDefaults
/// flush caveats — extensions reading the value are advised to also
/// consult `MigrationJournal` when high precision matters).
public actor SyncModeStore {
    private let defaults: UserDefaults
    private static let key = "lillist.syncMode"

    private var continuations: [UUID: AsyncStream<SyncMode>.Continuation] = [:]

    public init(appGroupID: String) {
        self.defaults = UserDefaults(suiteName: appGroupID) ?? .standard
    }

    /// Test/preview helper paralleling `DevicePreferencesStore.init(suiteName:)`.
    public init(suiteName: String) {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    /// The persisted mode, or `SyncMode.default` when absent.
    public func currentMode() -> SyncMode {
        guard let raw = defaults.string(forKey: Self.key),
              let mode = SyncMode(rawValue: raw)
        else { return .default }
        return mode
    }

    /// Persist a new mode and notify every subscriber. No-ops if the
    /// new mode equals the current one (subscribers don't get a
    /// duplicate event).
    public func setMode(_ mode: SyncMode) {
        let previous = currentMode()
        defaults.set(mode.rawValue, forKey: Self.key)
        guard mode != previous else { return }
        broadcast(mode)
    }

    /// An async stream of mode changes. Emits the *current* mode on
    /// subscription (so callers don't miss the initial value) and then
    /// every subsequent `setMode(_:)` write that actually changes the
    /// stored value.
    public var modeStream: AsyncStream<SyncMode> {
        AsyncStream { continuation in
            let id = UUID()
            register(id: id, continuation: continuation)
            continuation.yield(currentMode())
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { await self.unregister(id: id) }
            }
        }
    }

    private func register(id: UUID, continuation: AsyncStream<SyncMode>.Continuation) {
        continuations[id] = continuation
    }

    private func unregister(id: UUID) {
        continuations[id] = nil
    }

    private func broadcast(_ mode: SyncMode) {
        for continuation in continuations.values {
            continuation.yield(mode)
        }
    }
}
