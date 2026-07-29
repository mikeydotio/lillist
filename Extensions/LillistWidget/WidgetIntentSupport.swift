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
        guard let resolver = GatedPersistenceResolver(appGroupID: appGroupID, role: .widget) else {
            throw LillistError.storeUnavailable(
                reason: "App Group container '\(appGroupID)' is not available."
            )
        }
        return try await resolver.makePersistence { config in
            try await Cache.shared.controller(for: config)
        }
    }

    /// data-sync-hardening X8/X10: mirrors `ShortcutsActions.IntentSupport`'s
    /// identical factory (this target can't link that one). Hydrated from
    /// the persisted all-day default, never the hardcoded construction
    /// default. `UNUserNotificationCenter`'s pending-request namespace is
    /// scoped to the containing app, shared automatically by every
    /// extension in its App Group — safely usable from the widget process
    /// with no new entitlement (verified, not assumed — see the plan doc's
    /// X8 investigation; the ~30MB widget memory budget concern in X15 is
    /// about a second CloudKit-mirroring container, which `1c` already
    /// keeps off the widget's `PersistenceController`, not about
    /// constructing a `NotificationScheduler`).
    static func makeNotificationScheduler() async throws -> NotificationScheduler {
        try await makeNotificationScheduler(persistence: try await makePersistence())
    }

    static func makeNotificationScheduler(persistence: PersistenceController) async throws -> NotificationScheduler {
        let prefs = try await PreferencesStore(persistence: persistence).read()
        let registry = SnoozeRegistry(
            defaultAllDayHour: Int(prefs.defaultAllDayHour),
            defaultAllDayMinute: Int(prefs.defaultAllDayMinute),
            timeZone: .current
        )
        return NotificationScheduler(
            persistence: persistence,
            specs: NotificationSpecStore(persistence: persistence),
            center: SystemUserNotificationCenter(),
            snoozeRegistry: registry,
            deviceFingerprint: DeviceFingerprint.current(),
            defaultAllDayHour: Int(prefs.defaultAllDayHour),
            defaultAllDayMinute: Int(prefs.defaultAllDayMinute),
            timeZone: .current
        )
    }

    /// data-sync-hardening X8: a `TaskStore` with its `notificationScheduler`
    /// already assigned — see `IntentSupport.makeTaskStore()`'s identical
    /// doc comment for the class-kill rationale.
    static func makeTaskStore() async throws -> TaskStore {
        let persistence = try await makePersistence()
        let store = TaskStore(persistence: persistence)
        store.notificationScheduler = try await makeNotificationScheduler(persistence: persistence)
        return store
    }
}
