import Foundation
import CoreData

/// Seam over "which of these object IDs does the mirror already have a
/// CloudKit record identity for" — the same signal `TaskStore.syncCounts()`
/// reads from `NSPersistentCloudKitContainer.recordIDs(for:)`, wrapped so
/// `TaskDuplicateReconciler`'s merge-selection logic is unit-testable
/// without a live CloudKit container. (A real container returns nil/empty
/// for every ID under unsigned `swift test`, same limitation
/// `TaskStoreQueriesTests.syncCounts` documents for `mirrored > 0`.)
public protocol MirroredObjectIdentifying: Sendable {
    func mirroredObjectIDs(among ids: [NSManagedObjectID]) -> Set<NSManagedObjectID>
}

extension NSPersistentCloudKitContainer: MirroredObjectIdentifying {
    public func mirroredObjectIDs(among ids: [NSManagedObjectID]) -> Set<NSManagedObjectID> {
        Set(recordIDs(for: ids).keys)
    }
}

/// Detects and merges `LillistTask` rows that share one app-level `id` —
/// the shape produced when a local store's CloudKit mirroring bookkeeping is
/// discarded/rebuilt (e.g. by restoring from a local backup, or any other
/// resync) while the CloudKit zone still holds matching records: the zone's
/// existing records re-import as brand-new local rows, because
/// `NSPersistentCloudKitContainer` keys its mirroring bookkeeping on its own
/// record identity, not the app's `id`. Core Data enforces no uniqueness
/// constraint on `id` — CloudKit forbids uniqueness constraints entirely —
/// so nothing else in the stack prevents or heals this. Issue #66 traced a
/// real device (a restore performed with iCloud Sync on) into exactly this
/// state: three tasks each existing as two rows, one a settled
/// CloudKit-backed copy and one a pending-upload tombstone.
///
/// Watches `NSPersistentStoreRemoteChange` (the same notification
/// `RemoteChangeReconciler` observes) and runs a full reconcile pass on each
/// tick. A full scan (rather than an incremental persistent-history diff,
/// `RemoteChangeReconciler`'s approach) is deliberate here: `LillistTask`
/// counts are realistically in the tens-to-low-thousands for a personal task
/// manager, so the scan cost is negligible, and a full scan is also
/// self-healing against duplicates from *any* cause, not only the ones a
/// diff would have flagged as freshly inserted.
///
/// Merge policy, applied only when it's unambiguous:
/// - If **exactly one** row in a duplicate group has a CloudKit record
///   identity (`MirroredObjectIdentifying`), keep that row and delete the
///   others.
/// - If zero or more-than-one rows have an identity, the signal is
///   ambiguous — do nothing and leave the group for a future pass, rather
///   than guess and risk deleting the wrong copy. (A later pass may resolve
///   the ambiguity once one of the rows exports and gains an identity.)
///
/// Deletion goes through plain `context.delete(_:)`, not
/// `NSBatchDeleteRequest`, so the model's configured Cascade delete rules
/// (`LillistTask.children/journalEntries/attachments/notificationSpecs`)
/// apply automatically — no need for `CascadeReaper`, which exists
/// specifically to work around batch-delete bypassing those rules.
///
/// Bursty remote-change delivery (a batch of notifications arriving close
/// together) is serialized through a `DrainGate` (M3): overlapping
/// `reconcileNow` calls collapse into one in-flight full-table scan plus at
/// most a small, bounded number of coalesced reruns, instead of one
/// independent scan per notification.
///
/// `@unchecked Sendable`: the only mutable state (the observer token) is
/// touched on the main actor in `start()`/`stop()`.
public final class TaskDuplicateReconciler: @unchecked Sendable {
    private let persistence: PersistenceController
    private var observer: NSObjectProtocol?

    /// Optional diagnostic sink. When non-nil, a reconcile failure (M5)
    /// emits a structured `DiagnosticEvent` in addition to the
    /// unconditional `os.Logger` line — mirrors `TaskStore`'s
    /// property-injected `diagnosticLog`.
    public var diagnosticLog: DiagnosticSink?

    /// M3: serializes and coalesces overlapping `reconcileNow` calls. Each
    /// full-table scan is individually atomic (one `ctx.perform` block), so
    /// concurrent calls can't corrupt state even without this gate — but
    /// bursty remote-change delivery (e.g. a batch of notifications) would
    /// otherwise spawn one independent full `LillistTask` scan per
    /// notification with no coalescing. See `DrainGate`'s own doc comment.
    private let drainGate = DrainGate()

    public init(persistence: PersistenceController) {
        self.persistence = persistence
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
            Task { await self.reconcileNow() }
        }
    }

    /// Stop observing. Optional in production (`[weak self]` makes a stale
    /// token a no-op), but lets tests/teardown be deterministic.
    public func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    deinit { stop() }

    /// Run one reconcile pass against the live store. Public so the app can
    /// also call it once at launch — the catch-up pass for duplicates that
    /// arrived while the app wasn't running (e.g. a restore, then relaunch).
    public func reconcileNow() async {
        await reconcileNow(mirrorIdentifier: persistence.container as? NSPersistentCloudKitContainer)
    }

    /// Test seam for M5: exercises the real error-handling path with an
    /// injected mirror identifier, since a live `NSPersistentCloudKitContainer`
    /// (what `reconcileNow()` derives its identifier from) isn't available
    /// under unsigned `swift test` / the in-memory test store.
    ///
    /// M3: reentrancy-safe, same as `reconcileNow()` — both route through
    /// this single gated entry point, so a test driving this seam directly
    /// still exercises the real serialization.
    func reconcileNow(mirrorIdentifier: (any MirroredObjectIdentifying)?) async {
        guard await drainGate.tryAcquire() else { return }
        while true {
            await reconcileOnce(mirrorIdentifier: mirrorIdentifier)
            if await drainGate.finishOrRerun() { continue }   // a change landed mid-drain; sweep again
            return
        }
    }

    /// One serialized full-table reconcile pass. Only ever called by the
    /// single owning `reconcileNow` loop.
    private func reconcileOnce(mirrorIdentifier: (any MirroredObjectIdentifying)?) async {
        let ctx = persistence.container.viewContext
        do {
            _ = try await Self.reconcileDuplicates(in: ctx, mirrorIdentifier: mirrorIdentifier)
        } catch {
            // M5: this used to be `_ = try? await ...` — a reconcile
            // failure vanished silently. X19 (5a): `reconcileDuplicates`
            // itself now rolls back on a failed save via
            // `withMutationRollback`, so a failed merge no longer leaves
            // re-pointed relationships and pending deletes dirty on the
            // shared `viewContext` for the next unrelated save to commit —
            // this call site's own job is now only to fail loud, not also
            // to guard against a still-dirty context. Always log, and emit
            // a diagnostic when a sink is wired.
            LillistLog.store.error("TaskDuplicateReconciler.reconcileNow failed: \(String(describing: error), privacy: .public)")
            if let sink = diagnosticLog {
                await sink.log(DiagnosticEvent(
                    at: Date(),
                    seq: 0,
                    process: .app,
                    category: .data,
                    name: "taskDuplicateReconciler.reconcileFailed",
                    payload: ["error": .string(String(describing: error))]
                ))
            }
        }
    }

    /// Pure-ish core: find every `LillistTask` id shared by more than one
    /// row, and — only when the mirror signal is unambiguous — merge each
    /// group down to the CloudKit-backed survivor. Returns the number of
    /// rows deleted.
    ///
    /// `nonisolated static` so tests can drive it directly against an
    /// in-memory context with an injected `MirroredObjectIdentifying` fake,
    /// without a live CloudKit container. Routes through the same
    /// `withMutationRollback` helper every store mutator uses (X19/H5):
    /// before this fix, a failed `ctx.save()` here left every re-pointed
    /// relationship and pending `ctx.delete(loser)` dirty on the shared
    /// `viewContext` with no rollback at all — a second instance of H5's
    /// failure mode, not previously named because this type isn't one of
    /// the five "stores."
    @discardableResult
    public nonisolated static func reconcileDuplicates(
        in ctx: NSManagedObjectContext,
        mirrorIdentifier: (any MirroredObjectIdentifying)?
    ) async throws -> Int {
        try await withMutationRollback(context: ctx) {
            guard let mirrorIdentifier else { return 0 }

            let request = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            let all = try ctx.fetch(request)
            var byID: [UUID: [LillistTask]] = [:]
            for task in all {
                guard let id = task.id else { continue }
                byID[id, default: []].append(task)
            }
            let duplicateGroups = byID.values.filter { $0.count > 1 }
            guard !duplicateGroups.isEmpty else { return 0 }

            var deletedCount = 0
            for group in duplicateGroups {
                let mirrored = mirrorIdentifier.mirroredObjectIDs(among: group.map(\.objectID))
                let survivors = group.filter { mirrored.contains($0.objectID) }
                guard survivors.count == 1, let survivor = survivors.first else {
                    continue   // ambiguous (0 or 2+ mirrored) — do nothing, don't guess
                }
                for loser in group where loser.objectID != survivor.objectID {
                    merge(loser: loser, into: survivor)
                    ctx.delete(loser)
                    deletedCount += 1
                }
            }
            return deletedCount
        }
    }

    /// C3: before `ctx.delete(loser)` runs, re-point every relationship the
    /// model's `Cascade` delete rule would otherwise sweep away with the
    /// loser — children, journal entries, attachments, notification specs —
    /// onto `survivor`. After this, the loser's cascade closure is empty, so
    /// deleting it destroys only the duplicate row itself, not the subtree
    /// hanging off it.
    ///
    /// Also field-merges `survivor`'s content, row-level last-write-wins on
    /// `modifiedAt`: if `loser` was edited more recently, its content
    /// (`title`, `notes`, `status`, `start`/`startHasTime`,
    /// `deadline`/`deadlineHasTime`, `isPinned`, `closedAt`, `archivedAt`,
    /// `deletedAt`) becomes the merged truth; otherwise `survivor`'s own
    /// fields stand. This is a row-granularity LWW, not true per-property
    /// CRDT merge — Core Data tracks one `modifiedAt` per row, not a
    /// per-property version vector, so "per property" in practice means
    /// every field traces back to whichever *row* was edited more recently.
    /// `position` and `parent` are deliberately **excluded**: they describe
    /// the survivor's structural placement, not content, and blending them
    /// from a different row risks reintroducing exactly the
    /// position-collision and tree-consistency defects the rest of this
    /// hardening program fixes.
    private static func merge(loser: LillistTask, into survivor: LillistTask) {
        if let children = loser.children as? Set<LillistTask> {
            for child in children { child.parent = survivor }
        }
        if let entries = loser.journalEntries as? Set<JournalEntry> {
            for entry in entries { entry.task = survivor }
        }
        if let attachments = loser.attachments as? Set<Attachment> {
            for attachment in attachments { attachment.task = survivor }
        }
        if let specs = loser.notificationSpecs as? Set<NotificationSpec> {
            for spec in specs { spec.task = survivor }
        }

        let loserModifiedAt = loser.modifiedAt ?? .distantPast
        let survivorModifiedAt = survivor.modifiedAt ?? .distantPast
        if loserModifiedAt > survivorModifiedAt {
            survivor.title = loser.title
            survivor.notes = loser.notes
            survivor.statusRaw = loser.statusRaw
            survivor.start = loser.start
            survivor.startHasTime = loser.startHasTime
            survivor.deadline = loser.deadline
            survivor.deadlineHasTime = loser.deadlineHasTime
            survivor.isPinned = loser.isPinned
            survivor.closedAt = loser.closedAt
            survivor.archivedAt = loser.archivedAt
            survivor.deletedAt = loser.deletedAt
            survivor.modifiedAt = loser.modifiedAt
        }
        survivor.stampCurrentSchemaVersion()
    }
}
