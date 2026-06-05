import Foundation

/// Gate-aware resolution of the App-Group on-disk store configuration.
/// Adopted by the App Intents extension (`IntentSupport`) and the Share
/// Extension (`ShareRootView`) so the `MigrationGate` abort branch lives in
/// exactly one tested place. The App Intents `TaskEntityQuery` is routed
/// through it in Wave 6 (`extension-persistence-unification`). The CLI's
/// `StoreLocator` still builds the gate inline; unifying it through this
/// resolver is an optional follow-up, not currently scoped by any plan.
///
/// Production callers use ``init(appGroupID:)``, which wires the
/// `FileMigrationJournalStore` + `SyncModeStore` rooted at the App Group
/// container. Tests use ``init(appGroupID:journal:modeStore:)`` to inject
/// an `InMemoryMigrationJournalStore` and assert the abort path without a
/// live container.
///
/// Plan 21: when a foreground sync-mode migration is in flight the gate
/// throws `LillistError.storeUnavailable(reason:)` so the caller surfaces
/// "Sync settings are being changed. Try again in a moment." instead of
/// running against a half-swapped store.
public struct GatedPersistenceResolver: Sendable {
    private let appGroupID: String
    private let journal: any MigrationJournalStore
    private let modeStore: SyncModeStore

    /// Test/explicit-injection initializer.
    public init(
        appGroupID: String,
        journal: any MigrationJournalStore,
        modeStore: SyncModeStore
    ) {
        self.appGroupID = appGroupID
        self.journal = journal
        self.modeStore = modeStore
    }

    /// Production initializer. Returns `nil` when the App Group container
    /// is not reachable (so the file-backed journal can't be created).
    public init?(appGroupID: String) {
        guard let journal = FileMigrationJournalStore(appGroupID: appGroupID) else {
            return nil
        }
        self.appGroupID = appGroupID
        self.journal = journal
        self.modeStore = SyncModeStore(appGroupID: appGroupID)
    }

    /// Consult the gate and produce a ready-to-use `StoreConfiguration`,
    /// or throw `LillistError.storeUnavailable(reason:)` when a migration
    /// is in flight or the App Group is unavailable.
    public func resolveStoreConfiguration() async throws -> StoreConfiguration {
        let gate = MigrationGate(journal: journal, modeStore: modeStore)
        return try await gate.resolveStoreConfiguration(appGroupID: appGroupID)
    }

    /// Resolve the configuration through the gate, then build a controller
    /// from it. The `build` closure exists so tests can substitute an
    /// in-memory controller while still exercising the resolution path.
    public func makePersistence(
        build: (StoreConfiguration) async throws -> PersistenceController
    ) async throws -> PersistenceController {
        let config = try await resolveStoreConfiguration()
        return try await build(config)
    }

    /// Production convenience: resolve + build the on-disk controller.
    public func makePersistence() async throws -> PersistenceController {
        try await makePersistence { config in
            try await PersistenceController(configuration: config)
        }
    }
}
