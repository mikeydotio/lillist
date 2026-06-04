import Foundation
import CoreData

public final class PreferencesStore: @unchecked Sendable {
    /// Well-known, stable identity for the single `AppPreferences` row.
    ///
    /// Before this, `fetchOrCreateSingleton` minted a fresh `UUID()` on every
    /// device, so CloudKit mirrored *two distinct records* for the "singleton"
    /// and the two devices' preferences flip-flopped (review persist-2). Using
    /// one constant id means both devices converge on the same CloudKit record;
    /// `mergeByPropertyObjectTrump` then reconciles property-by-property instead
    /// of duplicating the whole row. The value is a fixed UUID literal — never
    /// regenerate it; existing stores depend on it.
    public static let singletonID = UUID(uuidString: "5111A570-0000-4000-8000-000000000001")!

    private let persistence: PersistenceController
    private var context: NSManagedObjectContext { persistence.container.viewContext }

    private var continuations: [UUID: AsyncStream<Prefs>.Continuation] = [:]
    private let continuationsLock = NSLock()
    private var remoteChangeObserver: NSObjectProtocol?

    public init(persistence: PersistenceController) {
        self.persistence = persistence
        // Bridge CloudKit / cross-process Core Data writes through the same
        // broadcast path used for local updates. `NSPersistentStoreRemoteChange`
        // fires when the persistent coordinator sees a write that didn't
        // originate from this context — typically a CloudKit pull, or another
        // window/process of the app.
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: persistence.container.persistentStoreCoordinator,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                if let snapshot = try? await self.read() {
                    self.broadcast(snapshot)
                }
            }
        }
    }

    deinit {
        if let remoteChangeObserver {
            NotificationCenter.default.removeObserver(remoteChangeObserver)
        }
    }

    public struct Prefs: Sendable, Equatable {
        public var defaultAllDayHour: Int16
        public var defaultAllDayMinute: Int16
        public var morningSummaryEnabled: Bool
        public var morningSummaryHour: Int16
        public var morningSummaryMinute: Int16
        public var trashRetentionDays: Int16
        public var defaultTaskListSort: SortField
        /// Whether the post-crash report sheet is shown on the next
        /// launch after a crash. Default `true`; see design Section 8.
        public var crashPromptsEnabled: Bool
        /// First-launch onboarding gate (Plan 10).
        public var hasCompletedOnboarding: Bool
        /// macOS: global Quick Capture hotkey active. iOS: floating + button.
        public var quickCaptureEnabled: Bool
        /// macOS-only: textual hotkey spec (e.g. "ctrl+opt+space"). Ignored on iOS.
        public var quickCaptureHotkey: String
        /// macOS-only: status-bar icon visible. Ignored on iOS.
        public var statusBarItemVisible: Bool
        /// Hex-RGB tint applied to newly-created tags. Default "#7F8FA6".
        public var defaultTagTintHex: String
    }

    public func read() async throws -> Prefs {
        try await context.perform { [self] in
            let row = try fetchOrCreateSingleton(in: context)
            return Prefs(
                defaultAllDayHour: row.defaultAllDayNotificationHour,
                defaultAllDayMinute: row.defaultAllDayNotificationMinute,
                morningSummaryEnabled: row.morningSummaryEnabled,
                morningSummaryHour: row.morningSummaryHour,
                morningSummaryMinute: row.morningSummaryMinute,
                trashRetentionDays: row.trashRetentionDays,
                defaultTaskListSort: row.defaultTaskListSort,
                crashPromptsEnabled: row.crashPromptsEnabled,
                hasCompletedOnboarding: row.hasCompletedOnboarding,
                quickCaptureEnabled: row.quickCaptureEnabled,
                quickCaptureHotkey: row.quickCaptureHotkey ?? "ctrl+opt+space",
                statusBarItemVisible: row.statusBarItemVisible,
                defaultTagTintHex: row.defaultTagTintHex ?? "#7F8FA6"
            )
        }
    }

    public func update(_ block: @escaping @Sendable (inout Prefs) -> Void) async throws {
        let updated: Prefs = try await context.perform { [self] in
            let row = try fetchOrCreateSingleton(in: context)
            var prefs = Prefs(
                defaultAllDayHour: row.defaultAllDayNotificationHour,
                defaultAllDayMinute: row.defaultAllDayNotificationMinute,
                morningSummaryEnabled: row.morningSummaryEnabled,
                morningSummaryHour: row.morningSummaryHour,
                morningSummaryMinute: row.morningSummaryMinute,
                trashRetentionDays: row.trashRetentionDays,
                defaultTaskListSort: row.defaultTaskListSort,
                crashPromptsEnabled: row.crashPromptsEnabled,
                hasCompletedOnboarding: row.hasCompletedOnboarding,
                quickCaptureEnabled: row.quickCaptureEnabled,
                quickCaptureHotkey: row.quickCaptureHotkey ?? "ctrl+opt+space",
                statusBarItemVisible: row.statusBarItemVisible,
                defaultTagTintHex: row.defaultTagTintHex ?? "#7F8FA6"
            )
            block(&prefs)
            row.defaultAllDayNotificationHour = prefs.defaultAllDayHour
            row.defaultAllDayNotificationMinute = prefs.defaultAllDayMinute
            row.morningSummaryEnabled = prefs.morningSummaryEnabled
            row.morningSummaryHour = prefs.morningSummaryHour
            row.morningSummaryMinute = prefs.morningSummaryMinute
            row.trashRetentionDays = prefs.trashRetentionDays
            row.defaultTaskListSort = prefs.defaultTaskListSort
            row.crashPromptsEnabled = prefs.crashPromptsEnabled
            row.hasCompletedOnboarding = prefs.hasCompletedOnboarding
            row.quickCaptureEnabled = prefs.quickCaptureEnabled
            row.quickCaptureHotkey = prefs.quickCaptureHotkey
            row.statusBarItemVisible = prefs.statusBarItemVisible
            row.defaultTagTintHex = prefs.defaultTagTintHex
            try context.save()
            return prefs
        }
        broadcast(updated)
    }

    /// An async stream of `Prefs` snapshots. Emits once for every successful
    /// `update(_:)` and once for every CloudKit / cross-process remote change.
    /// Each call returns a fresh stream scoped to its caller; closing the
    /// stream removes the continuation. Pattern modelled on
    /// `AccountStateMonitor.stateStream` / `CloudKitEventBridge.eventStream` —
    /// the store is `@unchecked Sendable` so the continuation registry is
    /// guarded by `NSLock` rather than living on an actor.
    public var prefsStream: AsyncStream<Prefs> {
        AsyncStream { continuation in
            let id = UUID()
            self.register(id: id, continuation: continuation)
            continuation.onTermination = { [weak self] _ in
                self?.unregister(id: id)
            }
        }
    }

    private func register(id: UUID, continuation: AsyncStream<Prefs>.Continuation) {
        continuationsLock.lock()
        continuations[id] = continuation
        continuationsLock.unlock()
    }

    private func unregister(id: UUID) {
        continuationsLock.lock()
        continuations[id] = nil
        continuationsLock.unlock()
    }

    private func broadcast(_ snapshot: Prefs) {
        continuationsLock.lock()
        let snapshotContinuations = Array(continuations.values)
        continuationsLock.unlock()
        for continuation in snapshotContinuations {
            continuation.yield(snapshot)
        }
    }

    /// Convenience: toggle whether the post-crash report sheet is
    /// presented on next launch.
    public func setCrashPromptsEnabled(_ value: Bool) async throws {
        try await update { $0.crashPromptsEnabled = value }
    }

    /// Test helper: count of AppPreferences rows. Asserts singleton invariant.
    public func rowCount() async throws -> Int {
        try await context.perform { [self] in
            let req = NSFetchRequest<AppPreferences>(entityName: "AppPreferences")
            return try context.count(for: req)
        }
    }

    private func fetchOrCreateSingleton(in ctx: NSManagedObjectContext) throws -> AppPreferences {
        // Prefer the canonical well-known-id row. Falling back to "any row"
        // keeps a legacy random-UUID store readable until `normalizeSingletons`
        // collapses it (called once at bootstrap).
        let canonical = NSFetchRequest<AppPreferences>(entityName: "AppPreferences")
        canonical.predicate = NSPredicate(format: "id == %@", Self.singletonID as CVarArg)
        canonical.fetchLimit = 1
        if let existing = try ctx.fetch(canonical).first {
            return existing
        }
        let anyReq = NSFetchRequest<AppPreferences>(entityName: "AppPreferences")
        anyReq.fetchLimit = 1
        if let legacy = try ctx.fetch(anyReq).first {
            // Adopt the legacy row's identity in place so we don't strand a
            // CloudKit record; `normalizeSingletons` handles the multi-row case.
            legacy.id = Self.singletonID
            try ctx.save()
            return legacy
        }
        let row = AppPreferences(context: ctx)
        row.id = Self.singletonID
        row.defaultAllDayNotificationHour = 9
        row.defaultAllDayNotificationMinute = 0
        row.morningSummaryEnabled = true
        row.morningSummaryHour = 9
        row.morningSummaryMinute = 0
        row.trashRetentionDays = 30
        row.defaultTaskListSortRaw = SortField.manualPosition.rawValue
        row.crashPromptsEnabled = true
        row.hasCompletedOnboarding = false
        row.quickCaptureEnabled = true
        row.quickCaptureHotkey = "ctrl+opt+space"
        row.statusBarItemVisible = true
        row.defaultTagTintHex = "#7F8FA6"
        try ctx.save()
        return row
    }

    /// One-time-per-launch convergence pass: collapse every `AppPreferences`
    /// row down to a single canonical row carrying `singletonID`.
    ///
    /// Pre-fix stores (and any device that synced before this fix shipped) can
    /// hold multiple random-UUID rows. We keep the row that sorts first by id
    /// (deterministic across devices), reassign it `singletonID`, and delete the
    /// rest. Idempotent: on an already-canonical store this fetches one row and
    /// returns without writing. Safe to call on every bootstrap.
    public func normalizeSingletons() async throws {
        try await context.perform { [self] in
            let req = NSFetchRequest<AppPreferences>(entityName: "AppPreferences")
            req.sortDescriptors = [NSSortDescriptor(key: "id", ascending: true)]
            let rows = try context.fetch(req)
            guard let survivor = rows.first else { return }       // empty store
            if rows.count == 1 && survivor.id == Self.singletonID {
                return                                            // already canonical
            }
            survivor.id = Self.singletonID
            for extra in rows.dropFirst() {
                context.delete(extra)
            }
            if context.hasChanges {
                try context.save()
            }
        }
    }
}
