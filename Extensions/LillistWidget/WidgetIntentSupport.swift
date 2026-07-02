import Foundation

import LillistCore

/// Gated App-Group persistence for the widget extension: the configuration
/// picker (`SmartFilterEntityQuery`), the cold-cache snapshot rebuild, and the
/// interactive complete intent all resolve the store through here.
///
/// A trimmed copy of ShortcutsActions' `IntentSupport` — the widget is a
/// separate target and can't link that one. Consults `MigrationGate` (so a
/// foreground sync-mode migration is never raced) and caches one
/// `PersistenceController` per process, keyed on the resolved `syncMode`.
enum WidgetIntentSupport {
    static let appGroupID = "group.app.lillist"

    private actor Cache {
        static let shared = Cache()
        private var mode: SyncMode?
        private var controller: PersistenceController?
        private var inFlight: (mode: SyncMode, task: Task<PersistenceController, Error>)?

        func controller(for configuration: StoreConfiguration) async throws -> PersistenceController {
            let wanted = configuration.syncMode
            if let controller, self.mode == wanted { return controller }
            if let inFlight, inFlight.mode == wanted { return try await inFlight.task.value }
            let build = Task {
                try await PersistenceController(
                    configuration: configuration,
                    transactionAuthor: PersistenceController.widgetTransactionAuthor
                )
            }
            self.inFlight = (wanted, build)
            do {
                let fresh = try await build.value
                self.mode = wanted
                self.controller = fresh
                if self.inFlight?.mode == wanted { self.inFlight = nil }
                return fresh
            } catch {
                if self.inFlight?.mode == wanted { self.inFlight = nil }
                throw error
            }
        }
    }

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
