import Foundation

/// Shared decision helper that extensions and the CLI use at startup
/// to decide whether to open the Core Data store or bail out because
/// a sync-mode migration is in flight.
///
/// Production callers pass `MigrationJournalStore` and `SyncModeStore`
/// concretes wired to the App Group container. Tests pass fakes.
public struct MigrationGate: Sendable {
    public enum Decision: Sendable, Equatable {
        /// Safe to open the store. Caller should build a
        /// `StoreConfiguration` whose `syncMode == mode`.
        case proceed(mode: SyncMode)
        /// A migration is in flight. Caller should abort with the
        /// supplied user-facing message.
        case abort(message: String)
    }

    private let journal: any MigrationJournalStore
    private let modeStore: SyncModeStore

    public init(journal: any MigrationJournalStore, modeStore: SyncModeStore) {
        self.journal = journal
        self.modeStore = modeStore
    }

    public func evaluate() async -> Decision {
        let entry = (try? journal.read()) ?? .idle
        if entry.isInFlight {
            return .abort(message: "Sync settings are being changed. Try again in a moment.")
        }
        let mode = await modeStore.currentMode()
        return .proceed(mode: mode)
    }

    /// Convenience for callers that want to skip the explicit
    /// `Decision` pattern-match: produce a ready-to-use
    /// `StoreConfiguration` for the App Group on-disk store, or
    /// throw a `LillistError.storeUnavailable(reason:)` when the
    /// gate says abort.
    public func resolveStoreConfiguration(
        appGroupID: String
    ) async throws -> StoreConfiguration {
        switch await evaluate() {
        case .abort(let message):
            throw LillistError.storeUnavailable(reason: message)
        case .proceed(let mode):
            guard let config = StoreConfiguration.appGroupOnDisk(
                groupID: appGroupID,
                syncMode: mode
            ) else {
                throw LillistError.storeUnavailable(
                    reason: "App Group container '\(appGroupID)' is not available."
                )
            }
            return config
        }
    }
}
