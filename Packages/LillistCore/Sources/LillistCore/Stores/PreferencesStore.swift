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

    /// M4: genuinely read-only — never inserts or saves. Reads the
    /// canonical `singletonID` row if present; falls back to reading (never
    /// adopting) the first legacy row for backward-compatible display; if
    /// the store has no `AppPreferences` row at all yet (a fresh install
    /// before the bootstrap maintenance pass has run), returns in-memory
    /// defaults built from the same literals `Self.defaultPrefs` uses for
    /// row creation, so a caller sees sensible values rather than a thrown
    /// error — without ever writing as a side effect of asking. Creation
    /// happens only in `normalizeSingletons()` (the explicit maintenance
    /// path both apps' bootstraps call) or, implicitly, in `update(_:)`
    /// (already an explicit mutation).
    public func read() async throws -> Prefs {
        try await context.perform { [self] in
            if let row = try fetchCanonicalOrLegacySingleton(in: context) {
                return Self.prefs(from: row)
            }
            return Self.defaultPrefs
        }
    }

    public func update(_ block: @escaping @Sendable (inout Prefs) -> Void) async throws {
        let updated: Prefs = try await withMutationRollback(context: context) { [self] in
            let row = try ensureSingleton(in: context)
            var prefs = Self.prefs(from: row)
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

    /// M4: pure read. Returns the canonical `singletonID` row if present,
    /// else the first legacy row (read, never adopted/mutated), else `nil`
    /// on a completely empty store. Never inserts, never saves.
    private func fetchCanonicalOrLegacySingleton(in ctx: NSManagedObjectContext) throws -> AppPreferences? {
        let canonical = NSFetchRequest<AppPreferences>(entityName: "AppPreferences")
        canonical.predicate = NSPredicate(format: "id == %@", Self.singletonID as CVarArg)
        canonical.fetchLimit = 1
        if let existing = try ctx.fetch(canonical).first {
            return existing
        }
        let anyReq = NSFetchRequest<AppPreferences>(entityName: "AppPreferences")
        anyReq.fetchLimit = 1
        return try ctx.fetch(anyReq).first
    }

    /// `update(_:)`'s create-if-missing path — legitimate here since
    /// `update` is already an explicit mutation, unlike `read()`. Adopts a
    /// legacy row's identity in place if one exists (so we don't strand a
    /// CloudKit record; `normalizeSingletons` handles the multi-row case),
    /// otherwise creates a fresh canonical row via `Self.populateDefaults`.
    private func ensureSingleton(in ctx: NSManagedObjectContext) throws -> AppPreferences {
        if let existing = try fetchCanonicalOrLegacySingleton(in: ctx) {
            existing.id = Self.singletonID
            return existing
        }
        let row = AppPreferences(context: ctx)
        Self.populateDefaults(row)
        return row
    }

    /// The single source of truth for "what a brand-new `AppPreferences`
    /// row looks like" — shared by `ensureSingleton`'s creation path,
    /// `normalizeSingletons`'s empty-store creation path, and
    /// `Self.defaultPrefs`'s in-memory fallback, so the three can never
    /// drift apart.
    private static func populateDefaults(_ row: AppPreferences) {
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
    }

    /// In-memory defaults `read()` returns when no `AppPreferences` row
    /// exists yet (a fresh install before the bootstrap maintenance pass
    /// has run) — the same values `populateDefaults` writes to a real row.
    private static var defaultPrefs: Prefs {
        Prefs(
            defaultAllDayHour: 9,
            defaultAllDayMinute: 0,
            morningSummaryEnabled: true,
            morningSummaryHour: 9,
            morningSummaryMinute: 0,
            trashRetentionDays: 30,
            defaultTaskListSort: .manualPosition,
            crashPromptsEnabled: true,
            hasCompletedOnboarding: false,
            quickCaptureEnabled: true,
            quickCaptureHotkey: "ctrl+opt+space",
            statusBarItemVisible: true,
            defaultTagTintHex: "#7F8FA6"
        )
    }

    private static func prefs(from row: AppPreferences) -> Prefs {
        Prefs(
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

    /// One-time-per-launch convergence pass: collapse every `AppPreferences`
    /// row down to a single canonical row carrying `singletonID` — and, on a
    /// completely empty store, create that canonical row (M4: the only
    /// non-`update` path allowed to do so).
    ///
    /// X20: survivor selection is a deterministic total order, not a raw-byte
    /// `id` sort (which could pick a legacy row over the canonical one — ~32%
    /// of legacy UUIDs sort below the fixed singleton id — and had no
    /// tie-break at all for two rows that both already carry `singletonID`,
    /// the concurrent-create race shape). `AppPreferences` has no timestamp
    /// attribute (verified against the model) and adding one is a real
    /// CloudKit-schema change requiring Development→Production redeployment
    /// — out of this plan's scope per the same binding constraint `4b` hit
    /// for `LIL-83` (flag to the orchestrator first, don't add unilaterally).
    /// The order instead is:
    ///   1. A row already carrying `singletonID` always wins over any row
    ///      that doesn't — preserves the canonical identity outright rather
    ///      than reassigning it away from a row that already has it.
    ///   2. Among rows tied on (1) — either two canonical rows from a
    ///      concurrent-create race, or an all-legacy store — `Self
    ///      .contentKey`, a canonical string built from every settings
    ///      field in a fixed order, ascending.
    ///   3. `id.uuidString` ascending as the final, purely mechanical
    ///      tie-break (identical content — the rows are indistinguishable
    ///      in every user-visible way, so any deterministic pick is
    ///      correct).
    /// Every input to this ordering (the settings fields themselves, `id`)
    /// is a regular synced `AppPreferences` attribute, so once CloudKit has
    /// propagated every row to every device, every device computes the
    /// identical ordering and picks the identical survivor — content-based
    /// rather than creation-time-based, but still a total, convergent order,
    /// which is what "every device picks the same survivor" requires. (A
    /// CloudKit-`recordName`-based tie-break was the other option
    /// considered; rejected — it would need a live `CKContainer` at the call
    /// site, breaking this method's pure-Core-Data testability the same way
    /// `TaskDuplicateReconciler`'s design explicitly worked around via
    /// dependency injection, for a narrow concurrent-race edge case that
    /// doesn't warrant the added complexity.)
    ///
    /// Idempotent: on an already-canonical single-row store this fetches one
    /// row and returns without writing. Safe to call on every bootstrap.
    public func normalizeSingletons() async throws {
        try await withMutationRollback(context: context) { [self] in
            let req = NSFetchRequest<AppPreferences>(entityName: "AppPreferences")
            let rows = try context.fetch(req)
            guard !rows.isEmpty else {
                let row = AppPreferences(context: context)
                Self.populateDefaults(row)
                return
            }
            let sorted = rows.sorted { a, b in
                let aCanonical = a.id == Self.singletonID
                let bCanonical = b.id == Self.singletonID
                if aCanonical != bCanonical { return aCanonical }
                let aKey = Self.contentKey(a)
                let bKey = Self.contentKey(b)
                if aKey != bKey { return aKey < bKey }
                return (a.id?.uuidString ?? "") < (b.id?.uuidString ?? "")
            }
            let survivor = sorted[0]
            if sorted.count == 1 && survivor.id == Self.singletonID {
                return                                            // already canonical
            }
            survivor.id = Self.singletonID
            for extra in sorted.dropFirst() {
                context.delete(extra)
            }
        }
    }

    /// A canonical, deterministic string encoding every settings field in a
    /// fixed order — used only as `normalizeSingletons`'s content-based
    /// tie-break (X20) when `id` alone can't distinguish two rows. Not a
    /// hash; a direct field concatenation, so it's trivially reproducible
    /// and debuggable.
    private static func contentKey(_ row: AppPreferences) -> String {
        [
            String(row.defaultAllDayNotificationHour),
            String(row.defaultAllDayNotificationMinute),
            String(row.morningSummaryEnabled),
            String(row.morningSummaryHour),
            String(row.morningSummaryMinute),
            String(row.trashRetentionDays),
            row.defaultTaskListSortRaw ?? "",
            String(row.crashPromptsEnabled),
            String(row.hasCompletedOnboarding),
            String(row.quickCaptureEnabled),
            row.quickCaptureHotkey ?? "",
            String(row.statusBarItemVisible),
            row.defaultTagTintHex ?? "",
        ].joined(separator: "\u{1}")
    }
}
