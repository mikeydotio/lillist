import Foundation
import CoreData

/// Per-phase identifier used by `MigrationCoordinator` to drive UI
/// progress. The host emits a subset of these as it performs the
/// structural swap; the coordinator emits the rest (quarantine, zone
/// erase, sync quiesce) around the host's transition.
public enum MigrationPhase: Sendable, Equatable {
    case preparing
    case backingUp
    case markingJournal(ModeTransitionOp)
    case erasingICloud(progress: Double)
    case removingLocalStore
    case reconfiguringStore
    case uploading(progress: Double?)
    case downloading(progress: Double?)
    case finalizing
    case completed
    case failed(reason: String)
}

/// Indirection between `AppEnvironment` and `PersistenceController`.
///
/// Plan 21 sidesteps the documented races inside
/// `_loadStoreDescriptions` / `PFCloudKitSetupAssistant` by **never
/// re-instantiating `NSPersistentCloudKitContainer`** — the same
/// container instance lives for the app's lifetime, and a mode change
/// is implemented as a store-level remove+re-add on its coordinator
/// with different `cloudKitContainerOptions`. The `PersistenceHost`
/// owns the controller, owns the canonical `currentMode`, and is the
/// only place in the codebase that mutates the coordinator after
/// initial bring-up.
///
/// Other Stores still read `controller.container.viewContext` exactly
/// as before — the context survives a `reconfigure(to:)` swap because
/// it stays attached to the same coordinator.
public actor PersistenceHost: PersistenceReconfiguring {
    public private(set) var controller: PersistenceController
    public private(set) var currentMode: SyncMode

    /// Initial CloudKit container ID, kept so re-adds can attach the
    /// right `cloudKitContainerOptions` when going back to iCloudSync.
    private let cloudKitContainerIdentifier: String
    /// Stored URL of the on-disk store. Captured on init so a
    /// `reconfigure` can re-add the store at the same location. `nil`
    /// for in-memory stores (which never reconfigure).
    private let storeURL: URL?

    /// Build a host from an existing, fully-initialized
    /// `PersistenceController`. The caller is responsible for
    /// constructing the controller with the *initial* mode; the host
    /// records that mode and assumes ownership of all subsequent
    /// mutations.
    public init(controller: PersistenceController, initialMode: SyncMode) {
        self.controller = controller
        self.currentMode = initialMode
        self.cloudKitContainerIdentifier = controller.configuration.cloudKitContainerIdentifier
        switch controller.configuration.storeKind {
        case .inMemory:
            self.storeURL = nil
        case .onDisk(let url):
            self.storeURL = url
        }
    }

    /// Async-friendly factory: build a fresh `PersistenceController`
    /// configured for `initialMode` at the given on-disk URL, then
    /// wrap it in a host.
    public static func make(
        initialMode: SyncMode,
        storeURL: URL,
        cloudKitContainerIdentifier: String = StoreConfiguration.defaultCloudKitContainerIdentifier
    ) async throws -> PersistenceHost {
        var cfg = StoreConfiguration.onDisk(url: storeURL, syncMode: initialMode)
        cfg = cfg.withCloudKitContainer(cloudKitContainerIdentifier)
        let controller = try await PersistenceController(configuration: cfg)
        return PersistenceHost(controller: controller, initialMode: initialMode)
    }

    // MARK: - Structural swap

    /// Switch the underlying store to a new `SyncMode` by removing
    /// the current persistent store and re-adding one with the right
    /// description options.
    ///
    /// This is the **structural** half of a sync-mode change. The
    /// higher-level orchestration (backing up the SQLite file before
    /// the swap, erasing CloudKit zones, waiting for sync to quiesce
    /// afterwards, updating the migration journal) lives in
    /// `MigrationCoordinator` — see Wave 3. `reconfigure` does the
    /// minimum: ensure the in-memory state is flushed, mutate the
    /// coordinator, restore the in-memory state.
    ///
    /// Idempotent: re-running with the current mode is a no-op write.
    public func reconfigure(to newMode: SyncMode) async throws {
        guard newMode != currentMode else { return }
        try await flushAndSwap(to: newMode)
        currentMode = newMode
    }

    /// Flush pending viewContext writes and run a store-level swap to
    /// the target mode. Public so `MigrationCoordinator` can call it
    /// inside a larger phase sequence without re-implementing the
    /// flush + swap recipe.
    private func flushAndSwap(to newMode: SyncMode) async throws {
        let ctx = controller.container.viewContext
        try await ctx.perform {
            if ctx.hasChanges {
                try ctx.save()
            }
        }
        let coordinator = controller.container.persistentStoreCoordinator
        // We only support a single attached store in production; in
        // tests there may be zero (in-memory) — bail in that case.
        guard let store = coordinator.persistentStores.first else { return }
        try coordinator.remove(store)
        let configForNewMode = configuration(for: newMode)
        let desc = PersistenceController.makeStoreDescription(for: configForNewMode)
        _ = try coordinator.addPersistentStore(
            type: NSPersistentStore.StoreType(rawValue: desc.type),
            configuration: nil,
            at: desc.url!,
            options: desc.options
        )
    }

    private func configuration(for newMode: SyncMode) -> StoreConfiguration {
        // We preserve the original CloudKit container identifier and
        // store URL; only syncMode changes. In-memory hosts (no
        // storeURL) shouldn't be passed through reconfigure but we
        // build a safe default in case a future caller does.
        let url = storeURL ?? URL(fileURLWithPath: "/dev/null")
        return StoreConfiguration(
            storeKind: .onDisk(url: url),
            cloudKitContainerIdentifier: cloudKitContainerIdentifier,
            syncMode: newMode
        )
    }
}
