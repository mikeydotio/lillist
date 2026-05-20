import Foundation
import AppIntents
import LillistCore

/// Shared helpers for App Intent `perform()` bodies.
enum IntentSupport {
    static let appGroupID = "group.io.mikeydotio.Lillist"

    /// Plan 21: consult `MigrationGate` so the intent doesn't race a
    /// foreground sync-mode migration. When the gate says abort, the
    /// intent throws an `AppIntentError` with the user-facing message
    /// so Shortcuts surfaces "Sync settings are being changed. Try
    /// again in a moment." instead of running against a half-swapped
    /// store.
    static func makePersistence() async throws -> PersistenceController {
        let modeStore = SyncModeStore(appGroupID: appGroupID)
        guard let journal = FileMigrationJournalStore(appGroupID: appGroupID) else {
            throw LillistError.storeUnavailable(reason: "App Group container '\(appGroupID)' is not available.")
        }
        let gate = MigrationGate(journal: journal, modeStore: modeStore)
        let config = try await gate.resolveStoreConfiguration(appGroupID: appGroupID)
        return try await PersistenceController(configuration: config)
    }
}
