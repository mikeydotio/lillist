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
        let entry: MigrationJournal
        do {
            entry = try journal.read()
        } catch {
            // A missing file is not an error — FileMigrationJournalStore.read()
            // returns .idle for that case without throwing. Reaching this
            // branch means the file exists but failed to decode (S15):
            // fail closed rather than conflating "unreadable" with "idle,"
            // which would let a caller proceed on top of unknown state.
            return .abort(message: "Sync settings could not be read (the migration journal appears corrupted). Try relaunching Lillist.")
        }
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
    ///
    /// - Parameter role: which process is asking — routed through
    ///   `StoreLocation` so mirroring is only armed for `.mainApp`
    ///   (data-sync-hardening `X15`).
    public func resolveStoreConfiguration(
        appGroupID: String,
        role: StoreLocation.Role
    ) async throws -> StoreConfiguration {
        switch await evaluate() {
        case .abort(let message):
            throw LillistError.storeUnavailable(reason: message)
        case .proceed(let mode):
            let location = try StoreLocation.resolve(role: role, appGroupID: appGroupID)
            return location.makeConfiguration(syncMode: mode)
        }
    }
}
