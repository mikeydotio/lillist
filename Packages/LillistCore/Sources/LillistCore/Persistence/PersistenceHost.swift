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

    /// Test seam: when set, the next `flushAndSwap` re-adds the
    /// original store but then *throws* to simulate an
    /// `addPersistentStore` failure, exercising the rollback path
    /// without corrupting a real on-disk store. Reset after one use.
    private var failAddOnNextSwap = false

    /// Test seam: the `NSPersistentStoreDescription` the last rollback
    /// re-added (or *would* re-add). Lets a unit test assert that the
    /// rollback path preserves `cloudKitContainerOptions` even when the
    /// live container can't be inspected for them (the framework does
    /// not surface CloudKit options back through `NSPersistentStore`).
    /// Roadmap #1: this is the value-object proof that mirroring is
    /// restored, not silently downgraded to a plain local store.
    private(set) var lastRollbackDescription: NSPersistentStoreDescription?

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

    /// Test seam (see `failAddOnNextSwap`). Arms a single simulated
    /// add-failure on the next `reconfigure`.
    func simulateAddFailureOnNextSwap() {
        failAddOnNextSwap = true
    }

    /// Test seam (see `lastRollbackDescription`). Reads the description
    /// the most recent rollback re-added, so a test can assert its
    /// `cloudKitContainerOptions` round-tripped.
    func rollbackDescriptionForTesting() -> NSPersistentStoreDescription? {
        lastRollbackDescription
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
    /// the target mode. Transactional: captures the *original mode's
    /// description* (which carries `cloudKitContainerOptions` when the
    /// store was mirroring), removes + re-adds inside one
    /// `viewContext.perform` critical section, and on add-failure
    /// re-adds the original description so the coordinator is never left
    /// store-less *and* never silently downgraded from iCloud to plain
    /// local (sync-4, conc-4, Roadmap #1). Private helper of the public
    /// entry point `reconfigure(to:)`; `MigrationCoordinator` drives the
    /// larger phase sequence through `reconfigure`, never this directly.
    private func flushAndSwap(to newMode: SyncMode) async throws {
        let ctx = controller.container.viewContext
        let coordinator = controller.container.persistentStoreCoordinator
        let shouldSimulateFailure = failAddOnNextSwap
        failAddOnNextSwap = false
        // Capture the ORIGINAL mode before the swap so we can rebuild a
        // faithful rollback description. `currentMode` is the mode the
        // store is attached as right now; `reconfigure` only advances it
        // after we return successfully.
        let originalMode = currentMode

        // Capture the original and target *configurations* (Sendable
        // value types) rather than the descriptions: an
        // `NSPersistentStoreDescription` is not `Sendable`, so it can't be
        // captured into the `@Sendable perform` closure. The pure static
        // factory `makeStoreDescription` runs *inside* the closure to
        // build the real descriptions. The rollback path is the only one
        // that carries `cloudKitContainerOptions` through — the live
        // `store.options` dictionary does NOT expose them (see
        // StoreLevelModeSwapSpike.swapMutatesDescription) — so we rebuild
        // from the original configuration, never snapshot the store.
        let originalConfig = configuration(for: originalMode)
        let newConfig = configuration(for: newMode)

        // The swap runs inside one `perform` critical section. On
        // add-failure it re-adds the ORIGINAL description (so a half-added
        // iCloud store rolls back to a *mirroring* store, not a downgraded
        // plain-local one — Roadmap #1) and signals the caller via
        // `RollbackOccurred`, carrying both the rebuilt rollback
        // description and the underlying error. The
        // `self.lastRollbackDescription` write is HOISTED out of the
        // closure (below): mutating an actor-isolated property from inside
        // the `@Sendable perform` closure is rejected by strict
        // concurrency, so the closure hands the description back through
        // the thrown error and the actor-isolated body records it.
        do {
            try await ctx.perform { [shouldSimulateFailure] in
                if ctx.hasChanges {
                    try ctx.save()
                }
                // We only support a single attached store in production; in
                // tests there may be zero (in-memory) — bail in that case.
                guard let store = coordinator.persistentStores.first else { return }

                let rollbackDesc = PersistenceController.makeStoreDescription(for: originalConfig)
                let desc = PersistenceController.makeStoreDescription(for: newConfig)

                try coordinator.remove(store)

                do {
                    if shouldSimulateFailure {
                        throw LillistError.storeUnavailable(reason: "simulated add failure (test seam)")
                    }
                    _ = try coordinator.addPersistentStore(
                        type: NSPersistentStore.StoreType(rawValue: desc.type),
                        configuration: nil,
                        at: desc.url!,
                        options: desc.options
                    )
                } catch {
                    // Roll back: re-add the ORIGINAL store via the
                    // description-taking API so `cloudKitContainerOptions`
                    // are honored — re-adding with
                    // `(type:configuration:at:options:)` would drop them
                    // and leave a plain local store. If even the rollback
                    // fails, surface storeUnavailable — the caller's
                    // journal is left .failed and recovery can restore a
                    // backup.
                    do {
                        try Self.addStore(rollbackDesc, to: coordinator)
                    } catch let rollbackError {
                        throw LillistError.storeUnavailable(
                            reason: "Store swap failed and rollback also failed: \(error); rollback: \(rollbackError)"
                        )
                    }
                    throw RollbackOccurred(underlying: error)
                }
            }
        } catch let rollback as RollbackOccurred {
            // The rollback re-added the description built from
            // `originalConfig` inside the closure. Rebuild the *same*
            // description from that Sendable config here on the actor and
            // record it so a unit test can assert the options round-tripped
            // (Roadmap #1) — `makeStoreDescription` is a pure function of
            // its config, so this rebuild is value-equal to the instance
            // the closure handed to `coordinator.addPersistentStore(with:)`.
            // We rebuild rather than carry the description through the
            // thrown error because `Error: Sendable` forbids a non-Sendable
            // `NSPersistentStoreDescription` payload under strict
            // concurrency.
            lastRollbackDescription = PersistenceController.makeStoreDescription(for: originalConfig)
            throw rollback.underlying
        }
    }

    /// Signals that `flushAndSwap` hit an add-failure and the rollback
    /// re-add already succeeded, so the actor-isolated body can record
    /// `lastRollbackDescription` (a write the `@Sendable` closure can't
    /// perform) and rethrow the original error. Never escapes
    /// `flushAndSwap`.
    private struct RollbackOccurred: Error {
        let underlying: Error
    }

    /// Re-add a store from a full `NSPersistentStoreDescription` so
    /// `cloudKitContainerOptions` (and every other description-level
    /// field) is honored. `addPersistentStore(with:completionHandler:)`
    /// is `NS_SWIFT_DISABLE_ASYNC`, so we bridge its completion handler;
    /// for SQLite stores it fires synchronously on the calling queue,
    /// keeping the call inside the one `perform` critical section.
    private nonisolated static func addStore(
        _ description: NSPersistentStoreDescription,
        to coordinator: NSPersistentStoreCoordinator
    ) throws {
        var addError: Error?
        coordinator.addPersistentStore(with: description) { _, error in
            addError = error
        }
        if let addError { throw addError }
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
