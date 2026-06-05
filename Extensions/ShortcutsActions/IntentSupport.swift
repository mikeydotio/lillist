import Foundation
import AppIntents
import LillistCore

/// Shared helpers for App Intent `perform()` bodies.
enum IntentSupport {
    static let appGroupID = "group.io.mikeydotio.Lillist"

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

        func controller(
            for configuration: StoreConfiguration
        ) async throws -> PersistenceController {
            if let controller, self.mode == configuration.syncMode {
                return controller
            }
            let fresh = try await PersistenceController(configuration: configuration)
            self.mode = configuration.syncMode
            self.controller = fresh
            return fresh
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
}
