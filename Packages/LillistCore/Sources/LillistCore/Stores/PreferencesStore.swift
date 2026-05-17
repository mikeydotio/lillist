import Foundation
import CoreData

public final class PreferencesStore: @unchecked Sendable {
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
        let req = NSFetchRequest<AppPreferences>(entityName: "AppPreferences")
        req.fetchLimit = 1
        if let existing = try ctx.fetch(req).first {
            return existing
        }
        let row = AppPreferences(context: ctx)
        row.id = UUID()
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
}
