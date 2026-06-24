import Foundation
import AppIntents
import LillistCore

/// Shared helpers for App Intent `perform()` bodies.
enum IntentSupport {
    static let appGroupID = "group.io.mikey.lillist"

    /// Per-process cache so repeated intent invocations in the same
    /// extension process reuse one `PersistenceController` (and its open
    /// Core Data stack) instead of standing up a fresh container — and a
    /// fresh CloudKit mirroring subscription — on every call. The cache is
    /// keyed on the resolved `StoreConfiguration.syncMode`: the App-Group
    /// store path is fixed for the process, so the only thing that changes
    /// between calls is the mode. If the user flips sync mode between
    /// invocations the key differs and we rebuild rather than serve a
    /// stale-mode controller. (`StoreConfiguration` itself isn't
    /// `Equatable`; `SyncMode` is a raw-value enum and is.)
    private actor Cache {
        static let shared = Cache()
        private var mode: SyncMode?
        private var controller: PersistenceController?
        /// A build already running for `mode`. Concurrent cold callers join
        /// it instead of standing up a second container.
        private var inFlight: (mode: SyncMode, task: Task<PersistenceController, Error>)?

        func controller(
            for configuration: StoreConfiguration
        ) async throws -> PersistenceController {
            let wanted = configuration.syncMode
            if let controller, self.mode == wanted {
                return controller
            }
            // Coalesce concurrent cold builds. Building a PersistenceController
            // suspends (loadPersistentStores + CloudKit bridge attach), and the
            // actor releases isolation across that await — so without this two
            // cold callers would both pass the cache check and both stand up a
            // container (and a CloudKit mirroring subscription), orphaning one.
            // The Task is registered synchronously *before* the first await, so
            // a caller that enters while a build is suspended joins the same Task.
            if let inFlight, inFlight.mode == wanted {
                return try await inFlight.task.value
            }
            // Stamp the App Intents process's distinct author so the diagnostics
            // history observer (in the main app) attributes intent-authored writes.
            let build = Task { try await PersistenceController(configuration: configuration, transactionAuthor: PersistenceController.appIntentsTransactionAuthor) }
            self.inFlight = (wanted, build)
            do {
                let fresh = try await build.value
                self.mode = wanted
                self.controller = fresh
                // Only clear if it's still our build — a concurrent caller may
                // have replaced it with a different-mode build to join.
                if self.inFlight?.mode == wanted { self.inFlight = nil }
                return fresh
            } catch {
                if self.inFlight?.mode == wanted { self.inFlight = nil }
                throw error
            }
        }
    }

    /// Resolve the App-Group persistence stack through the shared
    /// `GatedPersistenceResolver` (introduced by `app-layer-test-rehab`),
    /// which consults `MigrationGate` so the intent doesn't race a
    /// foreground sync-mode migration. When the gate says abort, the
    /// resolver throws `LillistError.storeUnavailable` with the user-facing
    /// message so Shortcuts surfaces "Sync settings are being changed. Try
    /// again in a moment." instead of running against a half-swapped store.
    ///
    /// The gate is consulted on *every* call (cheap; reads the journal +
    /// mode store) so a migration in flight is always caught. Only the
    /// resulting `PersistenceController` is cached — and only while the
    /// resolver keeps resolving the same `syncMode`.
    static func makePersistence() async throws -> PersistenceController {
        guard let resolver = GatedPersistenceResolver(appGroupID: appGroupID) else {
            throw LillistError.storeUnavailable(
                reason: "App Group container '\(appGroupID)' is not available."
            )
        }
        return try await resolver.makePersistence { config in
            try await Cache.shared.controller(for: config)
        }
    }

    /// Process-scoped diagnostic log for the App Intents extension. Explicit
    /// emits (e.g. `task.create`) land in this process's own JSONL file and
    /// honor the shared device toggle.
    static func diagnosticLog() async -> DiagnosticLog {
        DiagnosticLog.shared(
            process: .appIntents,
            appGroupID: appGroupID,
            enabled: await DevicePreferencesStore(appGroupID: appGroupID).diagnosticLoggingEnabled()
        )
    }
}
