import Foundation

extension CLIBridge {
    /// Locates the Lillist Core Data store for CLI / App Intents access.
    ///
    /// The CLI does not own the store path; it inherits it from the shared
    /// App Group container so every client sees the same data. Data-sync-
    /// hardening `X2`: this used to build its own, third, divergent path
    /// (`<group>/Library/Application Support/Lillist/Lillist.sqlite`) —
    /// it now resolves through `StoreLocation`, the single authority every
    /// process shares. If the container does not exist (app never
    /// installed / never run), the locator throws
    /// `LillistError.storeUnavailable` with a friendly install pointer.
    public enum StoreLocator {
        public static let appGroupIdentifier = StoreLocation.defaultAppGroupIdentifier

        public static let sqliteFilename = "Lillist.sqlite"

        public static func openInMemory() async throws -> PersistenceController {
            try await PersistenceController(configuration: .inMemory)
        }

        public static func openOnDisk(at url: URL) async throws -> PersistenceController {
            try await PersistenceController(configuration: .onDisk(url: url), transactionAuthor: PersistenceController.cliTransactionAuthor)
        }

        public static func openAppGroup(identifier: String = appGroupIdentifier) async throws -> PersistenceController {
            let location = try StoreLocation.resolve(role: .cli, appGroupID: identifier)
            guard FileManager.default.fileExists(atPath: location.url.path) else {
                throw LillistError.storeUnavailable(reason: "Lillist store not found at \(location.url.path). Run the Lillist app at least once to initialize the store.")
            }
            // Plan 21: consult the MigrationGate so the CLI doesn't
            // race a foreground sync-mode migration. Non-idle journal
            // throws `LillistError.storeUnavailable(reason:)`; idle
            // proceeds with whichever `SyncMode` the user has on disk.
            let modeStore = SyncModeStore(appGroupID: identifier)
            guard let journal = FileMigrationJournalStore(appGroupID: identifier) else {
                // Falling back to the legacy default if we can't reach
                // the journal directory — the CLI was working before
                // the journal existed, no reason to break it now.
                return try await PersistenceController(configuration: location.makeConfiguration(syncMode: .default), transactionAuthor: PersistenceController.cliTransactionAuthor)
            }
            let gate = MigrationGate(journal: journal, modeStore: modeStore)
            switch await gate.evaluate() {
            case .abort(let message):
                throw LillistError.storeUnavailable(reason: message)
            case .proceed(let mode):
                let config = location.makeConfiguration(syncMode: mode)
                return try await PersistenceController(configuration: config, transactionAuthor: PersistenceController.cliTransactionAuthor)
            }
        }
    }
}
