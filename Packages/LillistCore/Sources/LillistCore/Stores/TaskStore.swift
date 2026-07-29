import Foundation
import CoreData
import CloudKit
import os

/// Where a freshly created task lands within its sibling group.
///
/// - `bottom`: appended after the last sibling (the historical default).
///   Used by structural creates (subtasks, inline outline rows) and
///   order-preserving paths (backup import).
/// - `top`: inserted before the first sibling. Used by user-facing
///   capture entry points so a just-captured task is visible immediately
///   at the head of the list rather than buried at the end.
public enum NewTaskPlacement: Sendable {
    case top
    case bottom
}

public final class TaskStore: @unchecked Sendable {
    let persistence: PersistenceController
    private var context: NSManagedObjectContext { persistence.container.viewContext }

    /// Notification reconciler. Set by the app's composition root; left
    /// `nil` in tests that don't care about notifications, in which case
    /// the reconcile calls in mutation methods are no-ops.
    ///
    /// Property-injected (rather than init-injected) so the 100+ existing
    /// `TaskStore(persistence:)` test call sites continue to work without
    /// modification.
    public var notificationScheduler: (any NotificationReconciling)?

    /// Optional breadcrumb sink. When non-nil, successful and failed
    /// mutations record verb-only entries for crash diagnostics.
    /// See design Section 8 / Plan 9.
    public var breadcrumbs: BreadcrumbBuffer?

    /// Optional diagnostic sink. When non-nil, semantic row-manipulations emit
    /// structured `DiagnosticEvent`s (full payloads, incl. the throwing reorder
    /// path) to the per-process JSONL log. The concrete `DiagnosticLog` stamps
    /// the authoritative process + seq, so emits here pass placeholders.
    public var diagnosticLog: DiagnosticSink?

    /// Page size for list fetches. Core Data returns rows as faults in
    /// pages of this size and only realizes each page when touched, so a
    /// reload over a large sibling set doesn't fault+project every row on
    /// the main-queue `viewContext` at once. See the foundation review's
    /// "unbounded TaskStore fetch" finding and `docs/engineering-notes.md`.
    static let listFetchBatchSize = 100

    /// Fire-and-forget breadcrumb recorder. Drops silently if the
    /// buffer rejects the verb (e.g. would-be PII in `action`).
    fileprivate func recordCrumb(_ action: String, success: Bool) async {
        if let b = breadcrumbs {
            try? await b.record(action: action, success: success)
        }
    }

    /// Fire-and-forget diagnostic emit. Awaited (like `recordCrumb`) so it is
    /// deterministic and ordered, but the underlying `DiagnosticLog` swallows all
    /// I/O failures — it can never throw into or stall a mutation. No-op when no
    /// sink is wired. `process`/`seq` are placeholders the log overwrites.
    fileprivate func emitDiag(_ name: String, category: DiagCategory = .ui, _ payload: [String: DiagValue]) async {
        guard let log = diagnosticLog else { return }
        await log.log(DiagnosticEvent(at: Date(), seq: 0, process: .app, category: category, name: name, payload: payload))
    }

    public init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    /// A value-type DTO callers see — never an `NSManagedObject`.
    public struct TaskRecord: Sendable, Equatable {
        public var id: UUID
        public var title: String
        public var notes: String
        public var status: Status
        public var start: Date?
        public var startHasTime: Bool
        public var deadline: Date?
        public var deadlineHasTime: Bool
        public var position: Double
        public var isPinned: Bool
        public var parentID: UUID?
        public var createdAt: Date?
        public var modifiedAt: Date?
        public var closedAt: Date?
        public var archivedAt: Date?
        public var deletedAt: Date?
        public var seriesID: UUID?

        public init(
            id: UUID,
            title: String,
            notes: String,
            status: Status,
            start: Date?,
            startHasTime: Bool,
            deadline: Date?,
            deadlineHasTime: Bool,
            position: Double,
            isPinned: Bool,
            parentID: UUID?,
            createdAt: Date?,
            modifiedAt: Date?,
            closedAt: Date?,
            archivedAt: Date? = nil,
            deletedAt: Date?,
            seriesID: UUID? = nil
        ) {
            self.id = id
            self.title = title
            self.notes = notes
            self.status = status
            self.start = start
            self.startHasTime = startHasTime
            self.deadline = deadline
            self.deadlineHasTime = deadlineHasTime
            self.position = position
            self.isPinned = isPinned
            self.parentID = parentID
            self.createdAt = createdAt
            self.modifiedAt = modifiedAt
            self.closedAt = closedAt
            self.archivedAt = archivedAt
            self.deletedAt = deletedAt
            self.seriesID = seriesID
        }
    }

    /// Mutable view passed to `update`'s closure.
    public struct TaskDraft {
        public var title: String
        public var notes: String
        public var start: Date?
        public var startHasTime: Bool
        public var deadline: Date?
        public var deadlineHasTime: Bool
        public var isPinned: Bool
    }

    // MARK: - Create

    @discardableResult
    public func create(
        title: String,
        notes: String = "",
        parent: UUID? = nil,
        placement: NewTaskPlacement = .bottom
    ) async throws -> UUID {
        do {
            let result: (id: UUID, assigned: Double, observedMax: Double?) = try await withMutationRollback(context: context) { [self] in
                try validateTitle(title)
                let parentTask = try parent.map { try fetchManagedObject(id: $0, in: context) }
                try assertParentNotTrashed(parentTask)
                // Compute the position BEFORE inserting the new row, so the
                // observed-edge fetch reflects real siblings — not the new task's
                // own default 0.0. Behavior-preserving for `assigned`:
                // position(after: nil) == position(after: 0.0) == 1.0.
                let detail = try nextPositionDetail(forParent: parentTask, placement: placement)
                let task = LillistTask(context: context)
                let id = UUID()
                task.id = id
                task.title = title
                task.notes = notes
                task.status = .todo
                task.startHasTime = false
                task.deadlineHasTime = false
                task.isPinned = false
                task.createdAt = Date()
                task.modifiedAt = task.createdAt
                task.stampCurrentSchemaVersion()
                task.parent = parentTask
                task.position = detail.assigned
                return (id: id, assigned: detail.assigned, observedMax: detail.observedMax)
            }
            await recordCrumb("task.create", success: true)
            await emitDiag("task.create", [
                "taskID": .string(result.id.uuidString),
                "parentID": parent.map { .string($0.uuidString) } ?? .null,
                "assignedPosition": .double(result.assigned),
                "observedMaxPosition": result.observedMax.map(DiagValue.double) ?? .null,
                "threwError": .bool(false),
            ])
            return result.id
        } catch {
            await recordCrumb("task.create", success: false)
            await emitDiag("task.create", [
                "parentID": parent.map { .string($0.uuidString) } ?? .null,
                "threwError": .bool(true),
            ])
            throw error
        }
    }

    // MARK: - Read

    public func fetch(id: UUID) async throws -> TaskRecord {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            return record(from: m)
        }
    }

    // MARK: - Update

    public func update(id: UUID, _ block: @escaping @Sendable (inout TaskDraft) -> Void) async throws {
        do {
            try await withMutationRollback(context: context) { [self] in
                let m = try fetchManagedObject(id: id, in: context)
                var draft = TaskDraft(
                    title: m.title ?? "",
                    notes: m.notes ?? "",
                    start: m.start,
                    startHasTime: m.startHasTime,
                    deadline: m.deadline,
                    deadlineHasTime: m.deadlineHasTime,
                    isPinned: m.isPinned
                )
                block(&draft)
                try validateTitle(draft.title)
                m.title = draft.title
                m.notes = draft.notes
                m.start = draft.start
                m.startHasTime = draft.startHasTime
                m.deadline = draft.deadline
                m.deadlineHasTime = draft.deadlineHasTime
                m.isPinned = draft.isPinned
                m.modifiedAt = Date()
                m.stampCurrentSchemaVersion()
            }
            // Anchor fields (start/deadline) and their time flags affect
            // notification scheduling. Reconcile after save.
            if let scheduler = notificationScheduler {
                await scheduler.reconcile(taskID: id)
            }
            await recordCrumb("task.update", success: true)
        } catch {
            await recordCrumb("task.update", success: false)
            throw error
        }
    }

    // MARK: - Hard delete

    public func hardDelete(id: UUID) async throws {
        do {
            let doomedTaskIDs: [UUID] = try await withMutationRollback(context: context) { [self] in
                let m = try fetchManagedObject(id: id, in: context)
                // H3: collect the full cascade closure's task ids BEFORE
                // deleting, so pending OS notifications can be cancelled
                // once the delete is durable. Unconditional traversal
                // (unlike CascadeReaper.planPurge's trash-bounded barrier)
                // — hardDelete permanently removes `m` and everything under
                // it regardless of each descendant's own deletedAt state;
                // there is no "spare a live descendant" concept here the
                // way there is for a Trash purge.
                let doomedTaskIDs: [UUID] = CascadeReaper.objectIDs(forDeleting: [m])
                    .filter { $0.entity.name == "LillistTask" }
                    .compactMap { (try? context.existingObject(with: $0) as? LillistTask)?.id }
                context.delete(m)
                return doomedTaskIDs
            }
            if let notificationScheduler, !doomedTaskIDs.isEmpty {
                await notificationScheduler.cancelPending(forTaskIDs: doomedTaskIDs)
            }
            await recordCrumb("task.purge", success: true)
        } catch {
            await recordCrumb("task.purge", success: false)
            throw error
        }
    }

    // MARK: - Hierarchy

    public func children(of parentID: UUID?) async throws -> [TaskRecord] {
        let signpostID = LillistLog.signposter.makeSignpostID()
        let interval = LillistLog.signposter.beginInterval("taskFetch", id: signpostID)
        defer { LillistLog.signposter.endInterval("taskFetch", interval) }

        let records = try await context.perform { [self] in
            let req = try childrenFetchRequest(parentID: parentID, in: context)
            return try context.fetch(req).map(record(from:))
        }

        LillistLog.store.debug("children fetch rows=\(records.count, privacy: .public)")
        return records
    }

    /// Paged variant of `children(of:)`. Returns at most `limit` rows
    /// starting at `offset`, in the same `position`/`createdAt` order.
    ///
    /// The UI uses this so a reload faults and DTO-projects only the
    /// visible window instead of the whole sibling set (see the
    /// `fetchBatchSize` policy in `docs/engineering-notes.md`). `offset`
    /// beyond the end yields an empty array; `limit <= 0` is treated as
    /// "no limit" (parity with `NSFetchRequest.fetchLimit == 0`).
    public func children(of parentID: UUID?, limit: Int, offset: Int) async throws -> [TaskRecord] {
        try await context.perform { [self] in
            let req = try childrenFetchRequest(parentID: parentID, in: context)
            req.fetchLimit = max(0, limit)
            req.fetchOffset = max(0, offset)
            return try context.fetch(req).map(record(from:))
        }
    }

    /// Shared builder for the `children` fetch. `fetchBatchSize` makes Core
    /// Data return faults in pages of `Self.listFetchBatchSize` and only
    /// realize each page as it's touched — so even the unbounded overload no
    /// longer fully materializes a huge sibling set up front. Must be called
    /// inside `context.perform`.
    private func childrenFetchRequest(parentID: UUID?, in ctx: NSManagedObjectContext) throws -> NSFetchRequest<LillistTask> {
        let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
        if let parentID {
            let parent = try fetchManagedObject(id: parentID, in: ctx)
            req.predicate = NSPredicate(format: "parent == %@ AND deletedAt == nil", parent)
        } else {
            req.predicate = NSPredicate(format: "parent == nil AND deletedAt == nil")
        }
        req.sortDescriptors = [
            NSSortDescriptor(key: "position", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true)
        ]
        req.fetchBatchSize = Self.listFetchBatchSize
        return req
    }

    public func reparent(id: UUID, newParent newParentID: UUID?) async throws {
        do {
            let outcome: (oldParentID: UUID?, assigned: Double) = try await withMutationRollback(context: context) { [self] in
                let m = try fetchManagedObject(id: id, in: context)
                let oldParentID = m.parent?.id
                let newParent: LillistTask?
                if let newParentID {
                    let candidate = try fetchManagedObject(id: newParentID, in: context)
                    try assertParentNotTrashed(candidate)
                    if Validators.wouldCreateCycle(candidate: m, newParent: candidate) {
                        throw LillistError.validationFailed([
                            .init(field: "parent", message: "would create a cycle")
                        ])
                    }
                    newParent = candidate
                } else {
                    newParent = nil
                }
                m.parent = newParent
                let assigned = try nextPosition(forParent: newParent)
                m.position = assigned
                m.modifiedAt = Date()
                m.stampCurrentSchemaVersion()
                return (oldParentID: oldParentID, assigned: assigned)
            }
            await recordCrumb("task.move", success: true)
            await emitDiag("task.reparent", [
                "taskID": .string(id.uuidString),
                "oldParentID": outcome.oldParentID.map { .string($0.uuidString) } ?? .null,
                "newParentID": newParentID.map { .string($0.uuidString) } ?? .null,
                "assignedPosition": .double(outcome.assigned),
                "threwError": .bool(false),
            ])
        } catch {
            await recordCrumb("task.move", success: false)
            await emitDiag("task.reparent", [
                "taskID": .string(id.uuidString),
                "newParentID": newParentID.map { .string($0.uuidString) } ?? .null,
                "threwError": .bool(true),
            ])
            throw error
        }
    }

    // MARK: - Reorder

    /// How `reorder` should determine the dragged row's parent.
    ///
    /// - `infer` — derive the parent from the anchors
    ///   (`afterParent ?? beforeParent ?? currentParent`). This is the historic
    ///   behavior; it cannot express "top level" distinctly from "no anchor
    ///   information", so a de-parent-to-root resolves back to the current
    ///   parent. Kept as the default so existing callers/tests are unaffected.
    /// - `explicit` — the caller supplies the authoritative parent (`nil` = top
    ///   level). The drag system resolves this from the drop target, so the
    ///   store must honor it rather than re-infer.
    public enum ReparentTarget: Equatable, Sendable {
        case infer
        case explicit(UUID?)
    }

    public func reorder(
        id: UUID,
        after afterID: UUID?,
        before beforeID: UUID?,
        parent reparent: ReparentTarget = .infer
    ) async throws {
        // Surfaces values captured *inside* the perform block to the emit calls
        // on both the success and throwing paths. The anchor positions are
        // recorded before the out-of-order guard, so the RCA path (a degenerate
        // tie that throws) still logs the equal anchors that caused it.
        let cap = ReorderCapture()
        do {
            try await withMutationRollback(context: context) { [self] in
                let m = try fetchManagedObject(id: id, in: context)
                let afterTask = try afterID.map { try fetchManagedObject(id: $0, in: context) }
                let beforeTask = try beforeID.map { try fetchManagedObject(id: $0, in: context) }

                // Capture the observed anchor positions BEFORE any validation or
                // recompaction mutates them — this is the diagnostic evidence.
                cap.afterPosition = afterTask?.position
                cap.beforePosition = beforeTask?.position

                // Soft-deleted-anchor guard: an anchor that has been trashed is
                // logically absent — treat it as notFound rather than attempting
                // to reorder relative to a deleted row.
                if let a = afterTask, a.deletedAt != nil { throw LillistError.notFound }
                if let b = beforeTask, b.deletedAt != nil { throw LillistError.notFound }

                let afterParent = afterTask?.parent
                let beforeParent = beforeTask?.parent
                if let a = afterTask, let b = beforeTask, a.parent?.objectID != b.parent?.objectID {
                    throw LillistError.validationFailed([
                        .init(field: "neighbors", message: "must share the same parent")
                    ])
                }

                // M6: the check above only fires when BOTH anchors are
                // present. A single anchor under `.explicit(parent)` needs
                // the same guard against the target parent — an anchor's
                // `position` is only meaningful within its OWN sibling
                // group, so computing a position from an anchor in a
                // DIFFERENT group (relative to the explicit target) is
                // never correct: it can silently collide with an existing
                // sibling there, or land at a value with no relation to
                // that group's numbering. Mirrors the both-anchors case's
                // own behavior exactly — unconditional throw, no heal
                // attempt — and runs before the tie/inversion heal below so
                // a wrong-group anchor never reaches recompaction.
                if case .explicit(let pid) = reparent {
                    if let a = afterTask, beforeTask == nil, a.parent?.id != pid {
                        throw LillistError.validationFailed([
                            .init(field: "neighbors", message: "anchor does not belong to the target parent")
                        ])
                    }
                    if let b = beforeTask, afterTask == nil, b.parent?.id != pid {
                        throw LillistError.validationFailed([
                            .init(field: "neighbors", message: "anchor does not belong to the target parent")
                        ])
                    }
                }

                // Heal-then-recheck: if anchors are tied or inverted, attempt to
                // heal by recompacting siblings in canonical SiblingOrder.
                // `recompactSiblings` mutates the managed objects in-memory within
                // this same context, so `afterTask` and `beforeTask` (which ARE the
                // same objects in the siblings array) already reflect their new
                // `.position` values immediately after the call — no `context.refresh`
                // needed (and wrong: refresh would overwrite the unsaved in-memory
                // changes with stale store values).
                //
                // After recompaction we re-check. Two cases:
                //
                // • Genuine inversion (after.position > before.position before heal):
                //   Recompaction cannot fix a true ordering disagreement — throw.
                //
                // • Tie (after.position == before.position before heal):
                //   Recompaction assigns distinct positions via `SiblingOrder` (position
                //   asc, then id.uuidString asc on ties). The canonical winner is whichever
                //   has the lower uuidString — but the drag intent specifies which task is
                //   "after" and which is "before", and that intent must be preserved.
                //   If recompaction gave `afterTask` a higher position than `beforeTask`
                //   (because afterTask.uuid > beforeTask.uuid), we swap their positions so
                //   the drag-requested order is maintained. The swap is safe: both tasks were
                //   tied before and their relative order was unspecified; either assignment
                //   is correct, but we must pick the one that honours the caller's intent.
                //
                // Position computation after a heal:
                //   After recompaction all sibling positions are clean integers. Computing
                //   the midpoint `(B + C) / 2` can collide with an existing sibling when
                //   C - B is even (e.g. B=2, C=4 → midpoint=3, colliding with D=3). To
                //   avoid this we use `afterTask.position + 0.5`, which is guaranteed to
                //   not match any integer sibling position. This half-step still satisfies
                //   all test invariants (A lands after B in index order, positions are
                //   strictly increasing), and the normal `needsCompaction` underflow path
                //   is still checked below.
                var healedPositionOverride: Double? = nil
                if FractionalPosition.anchorsAreOutOfOrder(
                    after: afterTask?.position,
                    before: beforeTask?.position
                ) {
                    // Snapshot pre-heal positions to distinguish tie vs. genuine inversion.
                    let preHealAfter = afterTask?.position
                    let preHealBefore = beforeTask?.position
                    let wasATie = preHealAfter == preHealBefore

                    let healParent = afterTask?.parent ?? beforeTask?.parent ?? m.parent
                    recompactSiblings(ofParent: healParent)

                    if FractionalPosition.anchorsAreOutOfOrder(
                        after: afterTask?.position,
                        before: beforeTask?.position
                    ) {
                        if !wasATie {
                            // Genuine inversion that survived recompaction — throw.
                            throw LillistError.validationFailed([
                                .init(field: "neighbors", message: "anchors out of order")
                            ])
                        }
                        // Tie case: recompaction assigned positions in canonical uuid order,
                        // but that order conflicts with the drag intent (afterTask ended up
                        // with a higher position than beforeTask). Swap the two anchor
                        // positions so the drag intent is honoured.
                        if let a = afterTask, let b = beforeTask {
                            let tmp = a.position
                            a.position = b.position
                            b.position = tmp
                        }
                    }

                    // After recompaction, all positions are integers. Use a half-step above
                    // the after-anchor rather than the midpoint to guarantee no collision
                    // with any sibling that might sit at an integer midpoint.
                    if let a = afterTask {
                        healedPositionOverride = a.position + 0.5
                    }
                }

                // `.infer` reproduces the historic anchor-derived parent.
                // `.explicit` is authoritative — the drag system resolved the
                // target parent (nil = top level) and the store must not
                // re-infer it (which would collapse "top level" back into the
                // current parent and silently refuse a de-parent).
                let newParent: LillistTask?
                switch reparent {
                case .infer:
                    newParent = afterParent ?? beforeParent ?? m.parent
                case .explicit(let pid):
                    newParent = try pid.map { try fetchManagedObject(id: $0, in: context) }
                }

                if m.parent?.objectID != newParent?.objectID {
                    try assertParentNotTrashed(newParent)
                    if Validators.wouldCreateCycle(candidate: m, newParent: newParent) {
                        throw LillistError.validationFailed([
                            .init(field: "parent", message: "would create a cycle")
                        ])
                    }
                    m.parent = newParent
                }

                // If the target gap underflows, re-space all siblings evenly,
                // then recompute against the freshly-spaced neighbors. Recompaction
                // and the target update persist together in this one perform block.
                let needsCompaction = FractionalPosition.needsCompaction(
                    after: afterTask?.position,
                    before: beforeTask?.position
                )
                cap.didRecompact = needsCompaction
                if needsCompaction {
                    recompactSiblings(ofParent: newParent)
                }

                let computed = healedPositionOverride ?? FractionalPosition.position(
                    after: afterTask?.position,
                    before: beforeTask?.position
                )
                cap.computedPosition = computed
                m.position = computed
                m.modifiedAt = Date()
                m.stampCurrentSchemaVersion()
            }
            await emitReorderDiag(id: id, afterID: afterID, beforeID: beforeID, capture: cap, threwError: false)
        } catch {
            await emitReorderDiag(id: id, afterID: afterID, beforeID: beforeID, capture: cap, threwError: true)
            throw error
        }
    }

    /// Mutable carrier for reorder values captured inside `perform` so both the
    /// success and catch paths can emit them. `@unchecked Sendable`: written on
    /// the context queue and read only after the `await` completes (a
    /// happens-after barrier), so there is never concurrent access.
    private final class ReorderCapture: @unchecked Sendable {
        var afterPosition: Double?
        var beforePosition: Double?
        var computedPosition: Double?
        var didRecompact = false
    }

    private func emitReorderDiag(id: UUID, afterID: UUID?, beforeID: UUID?, capture cap: ReorderCapture, threwError: Bool) async {
        await emitDiag("task.reorder", [
            "taskID": .string(id.uuidString),
            "afterID": afterID.map { .string($0.uuidString) } ?? .null,
            "beforeID": beforeID.map { .string($0.uuidString) } ?? .null,
            "afterPosition": cap.afterPosition.map(DiagValue.double) ?? .null,
            "beforePosition": cap.beforePosition.map(DiagValue.double) ?? .null,
            "computedPosition": cap.computedPosition.map(DiagValue.double) ?? .null,
            "didRecompact": .bool(cap.didRecompact),
            "threwError": .bool(threwError),
        ])
    }

    // MARK: - Status transitions

    public func transition(id: UUID, to newStatus: Status) async throws {
        let cap = TransitionCapture()
        do {
            let spawnedID: UUID? = try await withMutationRollback(context: context) { [self] in
                let m = try fetchManagedObject(id: id, in: context)
                let oldStatus = m.status
                cap.from = oldStatus
                guard oldStatus != newStatus else {
                    cap.noop = true
                    return nil
                }
                m.status = newStatus
                m.modifiedAt = Date()
                m.stampCurrentSchemaVersion()
                if newStatus == .closed {
                    m.closedAt = m.modifiedAt
                } else if oldStatus == .closed {
                    m.closedAt = nil
                    // Reopening a previously archived task resurfaces it —
                    // a user explicitly un-completing is the signal that
                    // they want it back in the active view.
                    m.archivedAt = nil
                }

                // System journal entry for the transition.
                let entry = JournalEntry(context: context)
                entry.id = UUID()
                entry.task = m
                entry.kind = .statusChange
                entry.createdAt = m.modifiedAt
                entry.body = "\(oldStatus) → \(newStatus)"
                let payload: [String: Int] = ["from": oldStatus.rawValue, "to": newStatus.rawValue]
                entry.payload = try JSONSerialization.data(withJSONObject: payload)

                // Recurrence: spawn next instance ONLY on transition-to-closed.
                // Re-opening (oldStatus == .closed) does NOT undo the spawn,
                // per design Section 8.
                var spawnedID: UUID? = nil
                if newStatus == .closed {
                    spawnedID = try RecurrenceSpawner.spawnIfNeeded(forClosedTask: m, in: context)
                }

                return spawnedID
            }
            // Reconcile *after* the save so the persistent store reflects the
            // new state. The scheduler is property-injected; absent in tests
            // that don't care about notifications.
            if let scheduler = notificationScheduler {
                await scheduler.reconcile(taskID: id)
                if let spawnedID {
                    await scheduler.reconcile(taskID: spawnedID)
                }
            }
            cap.spawned = spawnedID != nil
            await emitTransitionDiag(id: id, to: newStatus, capture: cap, threwError: false)
            await recordCrumb("task.status.change", success: true)
        } catch {
            await emitTransitionDiag(id: id, to: newStatus, capture: cap, threwError: true)
            await recordCrumb("task.status.change", success: false)
            throw error
        }
    }

    /// Mutable carrier for transition values captured inside `perform`,
    /// same happens-after contract as `ReorderCapture`.
    private final class TransitionCapture: @unchecked Sendable {
        var from: Status?
        var noop = false
        var spawned = false
    }

    private func emitTransitionDiag(id: UUID, to newStatus: Status, capture cap: TransitionCapture, threwError: Bool) async {
        // `noop: true` means the store already had the target status. The
        // UI cycle path computes the target FROM the displayed status, so a
        // field log full of noops flags stale UI records — the silent shape
        // of the dead-completion-control bug class.
        await emitDiag("task.transition", [
            "taskID": .string(id.uuidString),
            "from": cap.from.map { .string("\($0)") } ?? .null,
            "to": .string("\(newStatus)"),
            "noop": .bool(cap.noop),
            "spawned": .bool(cap.spawned),
            "threwError": .bool(threwError),
        ])
    }

    // MARK: - Archive

    /// Stamp `archivedAt = now` on every task in `ids` that doesn't already
    /// have a value. Returns just the IDs that were actually flipped, so
    /// callers (notably the iOS pull-to-refresh undo affordance) can scope
    /// "undo" to the rows their action created without trampling earlier
    /// archive batches.
    ///
    /// Note: archive is independent of status. Closing a task does not
    /// auto-archive it; the UI batches and archives explicitly. Reopening a
    /// closed task does, however, clear `archivedAt` (see `transition`).
    @discardableResult
    public func archive(ids: [UUID]) async throws -> [UUID] {
        do {
            let affected: [UUID] = try await withMutationRollback(context: context) { [self] in
                var flipped: [UUID] = []
                let now = Date()
                for id in ids {
                    let m = try fetchManagedObject(id: id, in: context)
                    guard m.archivedAt == nil else { continue }
                    m.archivedAt = now
                    m.modifiedAt = now
                    m.stampCurrentSchemaVersion()
                    flipped.append(id)
                }
                return flipped
            }
            await recordCrumb("task.archive", success: true)
            return affected
        } catch {
            await recordCrumb("task.archive", success: false)
            throw error
        }
    }

    /// Clear `archivedAt` on every task in `ids`. Idempotent — rows already
    /// at `archivedAt == nil` are left untouched.
    public func unarchive(ids: [UUID]) async throws {
        do {
            try await withMutationRollback(context: context) { [self] in
                for id in ids {
                    let m = try fetchManagedObject(id: id, in: context)
                    guard m.archivedAt != nil else { continue }
                    m.archivedAt = nil
                    m.modifiedAt = Date()
                    m.stampCurrentSchemaVersion()
                }
            }
            await recordCrumb("task.unarchive", success: true)
        } catch {
            await recordCrumb("task.unarchive", success: false)
            throw error
        }
    }

    // MARK: - Soft delete

    public func softDelete(id: UUID) async throws {
        do {
            // H2: applySoftDelete cascades deletedAt onto every live descendant
            // (see 1a's H7 cycle-guard fix), so notification reconcile must
            // cover the whole subtree it touched — not just the root id — or a
            // cascaded descendant's reminder keeps firing for a trashed task.
            let affectedIDs: [UUID] = try await withMutationRollback(context: context) { [self] in
                let m = try fetchManagedObject(id: id, in: context)
                let now = Date()
                return applySoftDelete(to: m, at: now)
            }
            if let scheduler = notificationScheduler {
                // Every affected task's desired notification set is
                // unconditionally empty now (computeDesiredRequests excludes
                // deletedAt != nil) — cancelling is a batched OS round trip
                // for the whole subtree, the same H3 primitive purge uses,
                // rather than one reconcile() fetch-and-diff per descendant.
                await scheduler.cancelPending(forTaskIDs: affectedIDs)
            }
            await recordCrumb("task.delete", success: true)
        } catch {
            await recordCrumb("task.delete", success: false)
            throw error
        }
    }

    public func restore(id: UUID) async throws {
        do {
            // H2: clearSoftDelete cascades the restore onto every descendant
            // whose deletedAt matches the root's (see 1a's H7 cycle-guard
            // fix), so every one of them needs a real reconcile — a
            // descendant's specs may now resolve to a future fire date again,
            // which cancelPending's cancel-only shape can't re-install.
            let affectedIDs: [UUID] = try await withMutationRollback(context: context) { [self] in
                let m = try fetchManagedObject(id: id, in: context)
                guard let deletedAt = m.deletedAt else { return [] }
                let affected = clearSoftDelete(from: m, matchingDeletedAt: deletedAt)
                // C2 (binding product decision, 2026-07-28): a child restored
                // while its own parent is still trashed is promoted to root,
                // severing the link — left alone it lands in an unreachable
                // limbo (invisible in the parent's listing, since the parent
                // is still hidden) that becomes C1's next purge victim.
                if let parent = m.parent, parent.deletedAt != nil {
                    m.parent = nil
                }
                // H4: a stale pre-trash position can collide with a live
                // sibling that moved into it via recompaction while this
                // task sat in the trash. Always reassign a fresh position
                // among the (possibly new, per the promotion above) live
                // sibling group — the same edge-placement helper `create`
                // uses, now that `nextPositionDetail` itself ignores trashed
                // siblings when computing the edge.
                m.position = try nextPositionDetail(forParent: m.parent, placement: .bottom).assigned
                return affected
            }
            if let scheduler = notificationScheduler {
                for taskID in affectedIDs {
                    await scheduler.reconcile(taskID: taskID)
                }
            }
            await recordCrumb("task.restore", success: true)
        } catch {
            await recordCrumb("task.restore", success: false)
            throw error
        }
    }

    public func trashed() async throws -> [TaskRecord] {
        try await context.perform { [self] in
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "deletedAt != nil")
            req.sortDescriptors = [NSSortDescriptor(key: "deletedAt", ascending: false)]
            return try context.fetch(req).map(record(from:))
        }
    }

    /// Task counts for the iCloud status surface (reassurance metric).
    public struct SyncCounts: Sendable, Equatable {
        /// Every `LillistTask` row persisted locally, including trashed/tombstoned
        /// ones still tracked for sync.
        public let local: Int
        /// Of those, how many `NSPersistentCloudKitContainer` has mirrored to
        /// iCloud (carry a CloudKit record identity). Equals `local` in steady
        /// state; a gap is rows not yet mirrored. `0` in local-only mode (the live
        /// container isn't a cloud container, so nothing is mirrored).
        public let mirrored: Int
        public init(local: Int, mirrored: Int) {
            self.local = local
            self.mirrored = mirrored
        }
    }

    /// Count local `LillistTask` rows and how many are mirrored to iCloud.
    ///
    /// `mirrored` uses `NSPersistentCloudKitContainer.recordIDs(for:)` — a task
    /// has a CloudKit record identity once the mirror has accepted it for export.
    /// This is the closest supported "is it in iCloud" signal; NSPCC exposes no
    /// per-record server-confirmation flag (see engineering-notes 2026-06-27).
    /// L3: runs on a background context, not the main-queue `viewContext` —
    /// `mirrored`'s `NSPersistentCloudKitContainer.recordIDs(for:)` needs
    /// every task's `NSManagedObjectID` as input (there is no CloudKit-
    /// mirrored-count-only API), so this materializes every id regardless;
    /// moving that unbounded work off `viewContext` keeps it from
    /// contending with UI-driven fetches as the task count grows. `local`'s
    /// count moves to the same background context for one round trip rather
    /// than two. Object IDs are valid across any context sharing this
    /// controller's persistent store coordinator, so passing them to
    /// `cloud.recordIDs(for:)` (itself coordinator-scoped, not
    /// context-scoped) is unaffected by which context fetched them.
    /// L3: runs on a background context, not the main-queue `viewContext` —
    /// `mirrored`'s `NSPersistentCloudKitContainer.recordIDs(for:)` needs
    /// every task's `NSManagedObjectID` as input (there is no CloudKit-
    /// mirrored-count-only API), so this materializes every id regardless;
    /// moving that unbounded work off `viewContext` keeps it from
    /// contending with UI-driven fetches as the task count grows. `local`'s
    /// count moves to the same background context for one round trip rather
    /// than two. Object IDs are valid across any context sharing this
    /// controller's persistent store coordinator, so passing them to
    /// `cloud.recordIDs(for:)` (itself coordinator-scoped, not
    /// context-scoped) is unaffected by which context fetched them.
    /// L3: runs on a background context, not the main-queue `viewContext` —
    /// `mirrored`'s `NSPersistentCloudKitContainer.recordIDs(for:)` needs
    /// every task's `NSManagedObjectID` as input (there is no CloudKit-
    /// mirrored-count-only API), so this materializes every id regardless;
    /// moving that unbounded work off `viewContext` keeps it from
    /// contending with UI-driven fetches as the task count grows. `local`'s
    /// count moves to the same background context for one round trip rather
    /// than two. Object IDs are valid across any context sharing this
    /// controller's persistent store coordinator, so passing them to
    /// `cloud.recordIDs(for:)` (itself coordinator-scoped, not
    /// context-scoped) is unaffected by which context fetched them.
    public func syncCounts() async throws -> SyncCounts {
        let bg = persistence.makeBackgroundContext()
        return try await bg.perform { [self] in
            let countReq = NSFetchRequest<NSFetchRequestResult>(entityName: "LillistTask")
            let local = try bg.count(for: countReq)
            guard local > 0,
                  let cloud = persistence.container as? NSPersistentCloudKitContainer else {
                return SyncCounts(local: local, mirrored: 0)
            }
            let idReq = NSFetchRequest<NSManagedObjectID>(entityName: "LillistTask")
            idReq.resultType = .managedObjectIDResultType
            let ids = try bg.fetch(idReq)
            return SyncCounts(local: local, mirrored: cloud.recordIDs(for: ids).count)
        }
    }

    /// Hard-delete every task currently in the Trash (i.e. with
    /// `deletedAt != nil`), including any descendants. Returns the number
    /// of tasks removed. Plan 11 / design Section 7 ("Trash") — the
    /// "Empty Trash now" affordance in Preferences calls this.
    ///
    /// Distinct from `AutoPurgeJob`, which only removes tasks whose
    /// `deletedAt` is older than the retention window.
    @discardableResult
    public func purgeAll() async throws -> Int {
        do {
            // `deletedAt != nil` takes no arguments, so the args array is empty.
            let count: Int = try await batchPurge(
                predicateFormat: "deletedAt != nil",
                arguments: []
            )
            await recordCrumb("task.purge_all", success: true)
            return count
        } catch {
            await recordCrumb("task.purge_all", success: false)
            throw error
        }
    }

    /// Hard-deletes every `LillistTask` matching `predicateFormat` off the
    /// main-queue `viewContext`, on a background context, via chunked
    /// managed-object-context deletes (`TrashPurger`) — never
    /// `NSBatchDeleteRequest`, which bypasses `NSPersistentCloudKitContainer`'s
    /// export tracking (C4/X4).
    ///
    /// - Parameters:
    ///   - predicateFormat: `NSPredicate(format:)` string selecting the
    ///     victim rows.
    ///   - arguments: The substitution arguments for `predicateFormat`.
    ///     Must be `Sendable` so they survive the actor-boundary capture.
    /// - Returns: The number of `LillistTask` rows removed (roots plus every
    ///   cascade-reachable descendant task).
    private func batchPurge(
        predicateFormat: String,
        arguments: [any Sendable]
    ) async throws -> Int {
        try await TrashPurger.purge(
            predicateFormat: predicateFormat,
            arguments: arguments,
            context: persistence.makeBackgroundContext(),
            viewContext: persistence.container.viewContext,
            notificationScheduler: notificationScheduler
        )
    }

    /// H7: recursing only into children whose `deletedAt` doesn't already
    /// match what this pass is about to stamp is self-limiting against a
    /// mutual cycle in the common case (a revisited node's `deletedAt`
    /// already equals `now` by the time the cycle loops back to it, so the
    /// `where` clause excludes it). The explicit `visited` set is defense in
    /// depth against that guarantee ever being weakened by a future change
    /// to this recursion's shape — see `TreeCycleGuardTests`.
    ///
    /// H2: returns every task id this pass actually touched (root +
    /// cascaded descendants) so the caller can reconcile notifications for
    /// the whole affected subtree, not just the root.
    @discardableResult
    private func applySoftDelete(to m: LillistTask, at now: Date) -> [UUID] {
        var visited: Set<NSManagedObjectID> = []
        var affected: [UUID] = []
        applySoftDelete(to: m, at: now, visited: &visited, affected: &affected)
        return affected
    }

    private func applySoftDelete(
        to m: LillistTask,
        at now: Date,
        visited: inout Set<NSManagedObjectID>,
        affected: inout [UUID]
    ) {
        guard visited.insert(m.objectID).inserted else { return }
        m.deletedAt = now
        m.modifiedAt = now
        m.stampCurrentSchemaVersion()
        if let id = m.id { affected.append(id) }
        if let children = m.children as? Set<LillistTask> {
            for child in children where child.deletedAt == nil {
                applySoftDelete(to: child, at: now, visited: &visited, affected: &affected)
            }
        }
    }

    /// H7: same self-limiting shape and same defense-in-depth rationale as
    /// `applySoftDelete` above. H2: same affected-id-collection shape too.
    @discardableResult
    private func clearSoftDelete(from m: LillistTask, matchingDeletedAt: Date) -> [UUID] {
        var visited: Set<NSManagedObjectID> = []
        var affected: [UUID] = []
        clearSoftDelete(from: m, matchingDeletedAt: matchingDeletedAt, visited: &visited, affected: &affected)
        return affected
    }

    private func clearSoftDelete(
        from m: LillistTask,
        matchingDeletedAt: Date,
        visited: inout Set<NSManagedObjectID>,
        affected: inout [UUID]
    ) {
        guard visited.insert(m.objectID).inserted else { return }
        m.deletedAt = nil
        // M2: a restored task must be unconditionally visible. Clearing
        // only `deletedAt` can leave it in the archived-but-not-deleted
        // state, invisible in the surfaces that don't show the archive.
        // Applied to every node this cascade restores (root + matching
        // descendants) so a subtree that was independently archived before
        // being swept into the trash also resurfaces in full.
        m.archivedAt = nil
        m.modifiedAt = Date()
        m.stampCurrentSchemaVersion()
        if let id = m.id { affected.append(id) }
        if let children = m.children as? Set<LillistTask> {
            for child in children where child.deletedAt == matchingDeletedAt {
                clearSoftDelete(from: child, matchingDeletedAt: matchingDeletedAt, visited: &visited, affected: &affected)
            }
        }
    }

    // MARK: - Tags

    public func assignTag(taskID: UUID, tagID: UUID) async throws {
        try await withMutationRollback(context: context) { [self] in
            let task = try fetchManagedObject(id: taskID, in: context)
            let tag = try fetchTag(id: tagID, in: context)
            let existing = task.tags as? Set<Tag> ?? []
            if existing.contains(tag) { return }
            task.addToTags(tag)
            task.modifiedAt = Date()
            task.stampCurrentSchemaVersion()
        }
    }

    /// L4: mirrors `assignTag`'s no-op guard — unassigning a tag the task
    /// doesn't currently carry must not write (no spurious `modifiedAt`
    /// bump, no meaningless CloudKit export).
    public func unassignTag(taskID: UUID, tagID: UUID) async throws {
        try await withMutationRollback(context: context) { [self] in
            let task = try fetchManagedObject(id: taskID, in: context)
            let tag = try fetchTag(id: tagID, in: context)
            let existing = task.tags as? Set<Tag> ?? []
            guard existing.contains(tag) else { return }
            task.removeFromTags(tag)
            task.modifiedAt = Date()
            task.stampCurrentSchemaVersion()
        }
    }

    public func tagIDs(forTask taskID: UUID) async throws -> [UUID] {
        try await context.perform { [self] in
            let task = try fetchManagedObject(id: taskID, in: context)
            let tags = (task.tags as? Set<Tag>) ?? []
            return tags.compactMap(\.id)
        }
    }

    private func fetchTag(id: UUID, in ctx: NSManagedObjectContext) throws -> Tag {
        let req = NSFetchRequest<Tag>(entityName: "Tag")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        guard let m = try ctx.fetch(req).first else { throw LillistError.notFound }
        return m
    }

    // MARK: - Helpers

    func fetchManagedObject(id: UUID, in ctx: NSManagedObjectContext) throws -> LillistTask {
        let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        guard let m = try ctx.fetch(req).first else {
            throw LillistError.notFound
        }
        return m
    }

    func nextPosition(forParent parent: LillistTask?) throws -> Double {
        try nextPositionDetail(forParent: parent).assigned
    }

    /// As `nextPosition`, but also surfaces the observed edge sibling position
    /// so `create` can record `observedMaxPosition` in its diagnostic — the
    /// value the non-atomic edge allocation saw, central to the reorder-tie RCA.
    ///
    /// Thin wrapper over `SiblingPositioning` (the shared core `RecurrenceSpawner`
    /// also delegates to, so a spawn's placement can never drift from a
    /// manually-created task's — see H1).
    ///
    /// `placement` selects which end the new row lands at:
    /// - `.bottom` (default): the edge is the *max* sibling position and the
    ///   row is placed after it (`edge + 1.0`).
    /// - `.top`: the edge is the *min* sibling position and the row is placed
    ///   before it (`edge - 1.0`).
    /// An empty sibling group yields `1.0` either way.
    func nextPositionDetail(
        forParent parent: LillistTask?,
        placement: NewTaskPlacement = .bottom
    ) throws -> (assigned: Double, observedMax: Double?) {
        try SiblingPositioning.nextPositionDetail(forParent: parent, placement: placement, in: context)
    }

    /// Re-space every non-trashed sibling under `parent` to even 1.0 gaps,
    /// preserving their canonical `SiblingOrder` (position asc, then
    /// `id.uuidString` asc on ties). Mutates the managed objects in place;
    /// the caller's `context.save()` persists them. Must run inside the
    /// reorder `perform` block so recompaction and the target update commit
    /// atomically. The anchor managed objects the caller is holding pick up
    /// their new `position` values, so a post-recompaction
    /// `FractionalPosition.position` call sees the widened gaps.
    ///
    /// Sorting is done in Swift via `SiblingOrder.precedes` rather than via
    /// a secondary `NSSortDescriptor` on `createdAt` — Core Data orders UUID
    /// attributes as raw bytes, which does not match Swift's `uuidString`
    /// lexical order (see `SiblingOrder` doc-comment).
    private func recompactSiblings(ofParent parent: LillistTask?) {
        let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
        if let parent {
            req.predicate = NSPredicate(format: "parent == %@ AND deletedAt == nil", parent)
        } else {
            req.predicate = NSPredicate(format: "parent == nil AND deletedAt == nil")
        }
        req.sortDescriptors = [NSSortDescriptor(key: "position", ascending: true)]
        guard let siblings = try? context.fetch(req) else { return }
        let sorted = siblings.sorted {
            guard let idA = $0.id, let idB = $1.id else { return false }
            return SiblingOrder.precedes(
                positionA: $0.position, idA: idA,
                positionB: $1.position, idB: idB
            )
        }
        let respaced = PositionCompactor.recompact(positions: sorted.map(\.position))
        for (sibling, newPosition) in zip(sorted, respaced) {
            sibling.position = newPosition
        }
    }

    // MARK: - Load-time normalization

    /// Compacts siblings under `parentID` if and only if any adjacent pair has a
    /// non-strictly-increasing position (i.e. a tie or inversion). Idempotent:
    /// healthy sibling sets produce zero writes. Called at load-seams so data
    /// is clean before the first reorder attempt.
    public func normalizeSiblingsIfDegenerate(ofParent parentID: UUID?) async throws {
        try await withMutationRollback(context: context) { [self] in
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            if let parentID {
                let parent = try fetchManagedObject(id: parentID, in: context)
                req.predicate = NSPredicate(format: "parent == %@ AND deletedAt == nil", parent)
            } else {
                req.predicate = NSPredicate(format: "parent == nil AND deletedAt == nil")
            }
            req.sortDescriptors = [NSSortDescriptor(key: "position", ascending: true)]
            let siblings = try context.fetch(req)
            let sorted = siblings.sorted {
                guard let idA = $0.id, let idB = $1.id else { return false }
                return SiblingOrder.precedes(
                    positionA: $0.position, idA: idA,
                    positionB: $1.position, idB: idB
                )
            }
            // Detect-before-write: only compact if degenerate. Pairwise
            // zip is total for 0- and 1-element sets (`1..<count` is not).
            let isDegenerate = zip(sorted, sorted.dropFirst())
                .contains { $0.position >= $1.position }
            guard isDegenerate else { return }
            let respaced = PositionCompactor.recompact(positions: sorted.map(\.position))
            for (sibling, newPosition) in zip(sorted, respaced) {
                sibling.position = newPosition
            }
        }
    }

    /// Whether `title` would survive `validateTitle` — i.e. is non-empty
    /// after trimming whitespace and newlines. Pure value-math, exposed
    /// `nonisolated static` so non-actor callers (a SwiftUI "Add" button's
    /// disabled state, the unified editor's pre-commit gate) can check
    /// committability without an `async` round-trip into the store. This is
    /// the single source of truth for the rule; `validateTitle` delegates.
    public nonisolated static func isCommittableTitle(_ title: String) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// M1: `create`, `reparent`, and `reorder` (both `.infer` and
    /// `.explicit`, at the point where a *new* parent assignment is about to
    /// be made) all reject a soft-deleted target parent — mirroring the
    /// soft-deleted-*anchor* guard in `reorder`. Left unguarded, any of
    /// these entry points could directly construct the live-under-trashed
    /// illegal state `C1`'s purge fix and `C2`'s restore fix exist to
    /// prevent/repair. A CloudKit merge can still create this state (no
    /// local guard reaches a remote write) — `TreeIntegrityChecker`'s
    /// launch-time self-heal is the defense-in-depth backstop for that path.
    func assertParentNotTrashed(_ parent: LillistTask?) throws {
        if let parent, parent.deletedAt != nil {
            throw LillistError.validationFailed([
                .init(field: "parent", message: "parent is trashed")
            ])
        }
    }

    func validateTitle(_ title: String) throws {
        if !Self.isCommittableTitle(title) {
            throw LillistError.validationFailed([
                .init(field: "title", message: "must not be empty")
            ])
        }
    }

    func record(from m: LillistTask) -> TaskRecord {
        TaskRecord(
            id: m.id ?? UUID(),
            title: m.title ?? "",
            notes: m.notes ?? "",
            status: m.status,
            start: m.start,
            startHasTime: m.startHasTime,
            deadline: m.deadline,
            deadlineHasTime: m.deadlineHasTime,
            position: m.position,
            isPinned: m.isPinned,
            parentID: m.parent?.id,
            createdAt: m.createdAt,
            modifiedAt: m.modifiedAt,
            closedAt: m.closedAt,
            archivedAt: m.archivedAt,
            deletedAt: m.deletedAt,
            seriesID: m.series?.id
        )
    }
}
