import Foundation
import CoreData

/// Reacts to `NSPersistentStoreRemoteChange` notifications by diffing the
/// persistent-history stream and enqueuing notification reconciliation for the
/// tasks whose `NotificationSpec.lastFiredAt` a *CloudKit import* changed.
///
/// Why this exists (review notif-2, persist-2 §92): when device A delivers a
/// notification it writes `lastFiredAt`. Device B only learns of that fire via
/// CloudKit; without a remote-change-driven reconcile, B keeps its now-stale
/// pending request and the user gets a duplicate. This reconciler closes that
/// loop. It deliberately ignores self-authored transactions — matched against
/// `persistence.transactionAuthor`, this specific controller's own stamped
/// value, never a hardcoded default (data-sync-hardening H6: a controller
/// constructed with a non-default author, e.g. the macOS app's
/// `macAppTransactionAuthor`, must still recognize its own writes as local) —
/// so an app's own writes don't trigger a redundant reconcile cycle.
///
/// The history watermark advances **only after** the affected-task
/// computation and the consuming callback have both completed (H6) —
/// mirroring `LocalBackupCoordinator.processRemoteChange`, the verified-
/// correct pattern in this codebase. A kill/crash/termination between the
/// history fetch and the watermark write leaves the watermark unmoved, so the
/// same range is safely reprocessed next time instead of being silently
/// skipped forever. A computation failure is logged and surfaced via
/// `diagnosticLog` rather than swallowed — it must never be treated as "no
/// affected tasks."
///
/// Concurrent notification delivery is serialized through a `DrainGate` (M3):
/// overlapping `processPendingHistory()` calls collapse into one in-flight
/// drain plus at most one coalesced rerun, so the token read (inside
/// `ctx.perform`) and the watermark write (after it) stay atomic with respect
/// to other drains despite the intervening suspension points.
///
/// `@unchecked Sendable`: the only mutable state (the observer token and the
/// token watermark) is touched on the main actor in `start()`/`stop()` and the
/// token store is itself thread-safe.
public final class RemoteChangeReconciler: @unchecked Sendable {
    /// A flattened, Sendable view of one persistent-history change — either
    /// extracted from a real `NSPersistentHistoryChange` or constructed by a
    /// test. Keeps the diffing core pure and container-free.
    public struct SyntheticChange: Sendable {
        public let changedObjectID: NSManagedObjectID
        public let entityName: String
        public let changedProperties: Set<String>
        public let author: String?
        /// X9: distinguishes insert/update/delete. Defaults to `.update` so
        /// every pre-existing call site (all of which describe update
        /// scenarios — a `lastFiredAt`/`snoozedUntil` change) compiles and
        /// behaves unchanged.
        public let changeType: NSPersistentHistoryChangeType

        public init(
            changedObjectID: NSManagedObjectID,
            entityName: String,
            changedProperties: Set<String>,
            author: String?,
            changeType: NSPersistentHistoryChangeType = .update
        ) {
            self.changedObjectID = changedObjectID
            self.entityName = entityName
            self.changedProperties = changedProperties
            self.author = author
            self.changeType = changeType
        }
    }

    private let persistence: PersistenceController
    private let tokenStore: PersistentHistoryTokenStore
    private let onAffectedTasks: @Sendable ([UUID]) async -> Void
    /// X9: fires when a foreign-authored `NotificationSpec` DELETE is seen
    /// in a drained batch. A deleted spec's row is gone, and per the plan
    /// doc's tombstone investigation there's no attribute flagged
    /// `preservesValueInHistoryOnDeletion` in this model (relationships are
    /// never tombstoned regardless), so there's no taskID to key
    /// `onAffectedTasks` with. The app wires this to
    /// `scheduler.reconcileOrphanedPendingRequests()`, a set-difference
    /// sweep (mirrors `LocalBackupCoordinator`'s own tombstone-free
    /// deletion handling) rather than a per-id lookup.
    private let onOrphanedSpecDeletions: @Sendable () async -> Void
    private var observer: NSObjectProtocol?

    /// Optional diagnostic sink. When non-nil, a failure computing affected
    /// tasks (H6) emits a structured `DiagnosticEvent` in addition to the
    /// unconditional `os.Logger` line — mirrors `TaskDuplicateReconciler`'s
    /// property-injected `diagnosticLog` (M5).
    public var diagnosticLog: DiagnosticSink?

    /// M3: serializes and coalesces overlapping `processPendingHistory()`
    /// calls — see `DrainGate`'s own doc comment for the full rationale.
    private let drainGate = DrainGate()

    /// - Parameters:
    ///   - persistence: the live controller (its `viewContext` is used to fetch
    ///     history and resolve `NotificationSpec` → `taskID`).
    ///   - tokenStore: watermark persistence so diffing resumes across launches.
    ///   - onAffectedTasks: callback invoked with the unique affected task ids.
    ///     The app wires this to `scheduler.reconcile(taskID:)` per id.
    ///   - onOrphanedSpecDeletions: callback invoked when a foreign-authored
    ///     `NotificationSpec` DELETE was seen. Defaults to a no-op so
    ///     existing callers (and every pre-X9 test) compile unchanged.
    public init(
        persistence: PersistenceController,
        tokenStore: PersistentHistoryTokenStore,
        onAffectedTasks: @escaping @Sendable ([UUID]) async -> Void,
        onOrphanedSpecDeletions: @escaping @Sendable () async -> Void = {}
    ) {
        self.persistence = persistence
        self.tokenStore = tokenStore
        self.onAffectedTasks = onAffectedTasks
        self.onOrphanedSpecDeletions = onOrphanedSpecDeletions
    }

    /// Begin observing `NSPersistentStoreRemoteChange`. Call once at bootstrap.
    public func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: persistence.container.persistentStoreCoordinator,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.processPendingHistory() }
        }
    }

    /// Stop observing. Optional in production (`[weak self]` makes a stale token
    /// a no-op), but lets tests/teardown be deterministic.
    public func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    deinit { stop() }

    /// Walk history since the last watermark, compute affected task ids, advance
    /// the watermark, and fire the callback. Public so the app can also call it
    /// once at launch (catch-up for changes that arrived while not running).
    ///
    /// M3: reentrancy-safe. A burst of `NSPersistentStoreRemoteChange`
    /// notifications spawns several concurrent calls; only one drain ever
    /// runs at a time, and calls that arrive mid-drain are coalesced into a
    /// single guaranteed rerun rather than running (and re-reading the
    /// watermark) concurrently. See `DrainGate`.
    public func processPendingHistory() async {
        guard await drainGate.tryAcquire() else { return }
        while true {
            await drainOnce()
            if await drainGate.finishOrRerun() { continue }   // a change landed mid-drain; sweep again
            return
        }
    }

    /// One serialized read-fetch-reconcile-advance pass. Only ever called by
    /// the single owning `processPendingHistory` loop, so the token read
    /// (inside `ctx.perform`) and the watermark advance (after the callback)
    /// stay atomic w.r.t. other drains despite the intervening suspension
    /// points.
    private func drainOnce() async {
        let ctx = persistence.container.viewContext
        let (changes, newToken): ([SyntheticChange], NSPersistentHistoryToken?)
        do {
            (changes, newToken) = try await ctx.perform { [weak self] in
                guard let self else { return ([], nil) }
                // Read the watermark inside the perform block so the non-Sendable
                // NSPersistentHistoryToken is never captured across the @Sendable
                // boundary (Swift 6 strict concurrency).
                let after = self.tokenStore.lastToken
                let request = NSPersistentHistoryChangeRequest.fetchHistory(after: after)
                guard let result = try ctx.execute(request) as? NSPersistentHistoryResult,
                      let transactions = result.result as? [NSPersistentHistoryTransaction]
                else { return ([], nil) }
                var flattened: [SyntheticChange] = []
                for txn in transactions {
                    for change in txn.changes ?? [] {
                        let name = change.changedObjectID.entity.name ?? ""
                        flattened.append(
                            SyntheticChange(
                                changedObjectID: change.changedObjectID,
                                entityName: name,
                                changedProperties: change.updatedProperties.map { Set($0.map(\.name)) } ?? [],
                                author: txn.author,
                                changeType: change.changeType
                            )
                        )
                    }
                }
                return (flattened, transactions.last?.token)
            }
        } catch {
            return   // transient store error; next remote change retries
        }

        let affected: [UUID]
        do {
            affected = try await Self.affectedTaskIDs(
                from: changes,
                localAuthor: persistence.transactionAuthor,
                in: ctx
            )
        } catch {
            // H6: a computation failure must never be treated as "no
            // affected tasks" (the old `try? ... ?? []` swallow) — fail
            // loud, and — critically — leave the watermark untouched so the
            // next remote change retries this exact history range instead
            // of silently losing it.
            LillistLog.store.error("RemoteChangeReconciler failed to compute affected tasks: \(String(describing: error), privacy: .public)")
            if let sink = diagnosticLog {
                await sink.log(DiagnosticEvent(
                    at: Date(),
                    seq: 0,
                    process: .app,
                    category: .data,
                    name: "remoteChangeReconciler.affectedTaskIDsFailed",
                    payload: ["error": .string(String(describing: error))]
                ))
            }
            return
        }

        if affected.isEmpty == false {
            await onAffectedTasks(affected)
        }

        // X9: a foreign spec DELETE has no taskID to key onAffectedTasks
        // with (see the type's onOrphanedSpecDeletions doc comment) — swept
        // separately, after the taskID-keyed callback, still before the
        // watermark advances (same H6 ordering guarantee: a crash here
        // leaves the watermark unmoved, so this drain is safely retried).
        if Self.hasForeignSpecDeletions(in: changes, localAuthor: persistence.transactionAuthor) {
            await onOrphanedSpecDeletions()
        }

        // H6: advance the watermark only after the affected-task computation
        // AND the callback have both completed — mirrors
        // LocalBackupCoordinator.processRemoteChange, the verified-correct
        // pattern (review: "advances only after successful apply"). A
        // kill/crash between here and the callback returning leaves the
        // watermark unmoved, so the same history range is safely reprocessed
        // next time instead of being silently skipped forever.
        if let newToken {
            tokenStore.lastToken = newToken
        }
    }

    /// Pure-ish diffing core (no NotificationCenter, no live CloudKit): given a
    /// flat change list, return the de-duplicated, order-stable list of task
    /// ids that need a notification reconcile because of a foreign-author
    /// change to either a `NotificationSpec` or a `LillistTask`.
    ///
    /// `LIL-90` widened the UPDATE gate from `lastFiredAt` alone to
    /// ``scheduleAffectingSpecProperties``. The residual was filed as latent —
    /// nothing could edit an existing spec in place from another device — but
    /// `LIL-83`'s time-zone-change prompt is exactly that caller, so leaving the
    /// gate narrow would mean a user who accepts "reschedule to the new zone" on
    /// one device keeps firing on the old zone everywhere else.
    ///
    /// X9 widened this beyond the original `lastFiredAt`-only filter:
    /// - `NotificationSpec` INSERT (a reminder added on another device) —
    ///   the row still exists, so `spec.task?.id` resolves directly.
    /// - `NotificationSpec` UPDATE — narrowly still gated on
    ///   ``scheduleAffectingSpecProperties`` — widened from `lastFiredAt` alone
    ///   by `LIL-90` (see above). Note `snoozedUntil` is deliberately **absent**
    ///   from that set: snooze is device-local now
    ///   (``SnoozeStateStore``), so a remote snooze edit cannot exist.
    /// - `NotificationSpec` DELETE — deliberately **excluded**: the row is
    ///   gone and (per the plan doc's tombstone investigation) unresolvable
    ///   to a taskID from history alone. Handled by `hasForeignSpecDeletions`/
    ///   `onOrphanedSpecDeletions` instead, a taskID-free mechanism.
    /// - `LillistTask` UPDATE touching `deletedAt` (soft-delete OR restore —
    ///   both are property updates on a row that still exists) — the change
    ///   *is* the task, so its own `id` resolves directly, no relationship
    ///   traversal needed.
    ///
    /// `nonisolated static` so XCTest / background callers can use it without
    /// crossing an actor boundary (CLAUDE.md UI-layer note generalizes here).
    /// The `NotificationSpec` properties whose remote change can move *when* a
    /// notification fires — and therefore the only ones worth a reconcile.
    ///
    /// A named allow-list rather than "any property" on purpose: this set is a
    /// claim about scheduling semantics, so a future non-scheduling attribute
    /// must not silently start triggering reconciles. Adding an attribute here
    /// is a deliberate act.
    ///
    /// `snoozedUntil` is absent by design — it is device-local (`LIL-90`), so a
    /// remote edit to it is not merely ignored but impossible.
    public nonisolated static let scheduleAffectingSpecProperties: Set<String> = [
        "lastFiredAt",
        "scheduledTimeZoneID",
        "offsetMinutes",
        "fireDate",
        "kindRaw"
    ]

    public nonisolated static func affectedTaskIDs(
        from changes: [SyntheticChange],
        localAuthor: String,
        in ctx: NSManagedObjectContext
    ) async throws -> [UUID] {
        await ctx.perform {
            var ordered: [UUID] = []
            var seen: Set<UUID> = []
            for change in changes {
                guard change.author != localAuthor else { continue }
                var taskID: UUID?
                switch change.entityName {
                case "NotificationSpec":
                    guard change.changeType != .delete else { continue }
                    if change.changeType == .update {
                        guard change.changedProperties
                            .isDisjoint(with: Self.scheduleAffectingSpecProperties) == false
                        else { continue }
                    }
                    guard let spec = try? ctx.existingObject(with: change.changedObjectID) as? NotificationSpec
                    else { continue }
                    taskID = spec.task?.id
                case "LillistTask":
                    guard change.changeType == .update,
                          change.changedProperties.contains("deletedAt") else { continue }
                    guard let task = try? ctx.existingObject(with: change.changedObjectID) as? LillistTask
                    else { continue }
                    taskID = task.id
                default:
                    continue
                }
                guard let taskID else { continue }
                if seen.insert(taskID).inserted {
                    ordered.append(taskID)
                }
            }
            return ordered
        }
    }

    /// X9: true if `changes` contains at least one foreign-authored
    /// `NotificationSpec` DELETE. Pure and synchronous — every field it
    /// reads (`entityName`/`changeType`/`author`) is already flattened into
    /// `SyntheticChange`, so no context access is needed (unlike
    /// `affectedTaskIDs`, which must resolve still-live rows). Drives
    /// `onOrphanedSpecDeletions`, the set-difference sweep that replaces a
    /// per-id lookup history can't provide for a deleted row.
    public nonisolated static func hasForeignSpecDeletions(
        in changes: [SyntheticChange],
        localAuthor: String
    ) -> Bool {
        changes.contains { change in
            change.entityName == "NotificationSpec"
                && change.changeType == .delete
                && change.author != localAuthor
        }
    }
}
