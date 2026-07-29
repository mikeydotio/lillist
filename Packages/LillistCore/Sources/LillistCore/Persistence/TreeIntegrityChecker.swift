import Foundation
import CoreData

/// Class-killer for the trash/restore tree state machine (data-sync-hardening
/// plan `1a`). Local mutation paths (`M1`, `H7`) now guard against every
/// illegal state this type checks for, but a CloudKit property-level merge
/// writes each row's relationships independently and is not bound by any
/// local validator — it can still reconstruct a parent-cycle, a
/// live-under-trashed node, or a position tie that a purely local app could
/// never produce. `TreeIntegrityChecker` is the backstop: a read-only
/// `scan` (test assertion helper) and a mutating `repair` (launch-time
/// self-heal, wired into both apps' `bootstrap()` — see
/// `docs/superpowers/plans/2026-07-28-plan-1a-trash-tree-integrity.md`).
///
/// Both entry points are synchronous and take the caller's
/// `NSManagedObjectContext` directly — call them from inside
/// `context.perform`/`performAndWait`, the same convention every other
/// `LillistCore` Core Data helper uses. `repair` mutates in place; the
/// caller is responsible for `context.save()`.
public enum TreeIntegrityChecker {

    /// A structural or ordering defect `repair` can heal.
    public enum Violation: Sendable, Equatable {
        /// `memberIDs` are the cycle's participants, in walk order.
        case parentCycle(memberIDs: [UUID])
        /// A live (`deletedAt == nil`) task whose immediate parent is
        /// trashed — the same illegal state `C1`'s purge-time barrier and
        /// `C2`'s restore fix defend against locally.
        case liveUnderTrashedAncestor(taskID: UUID, trashedParentID: UUID)
        /// Two or more live siblings under `parentID` (`nil` = root) share
        /// one `position` value.
        case positionTie(parentID: UUID?, taskIDs: [UUID])
    }

    // MARK: - Public API

    /// Read-only scan — reports every violation without mutating anything.
    /// Intended as a test assertion helper (`#expect(try
    /// TreeIntegrityChecker.scan(in: ctx).isEmpty)`) and for diagnostics.
    public static func scan(in context: NSManagedObjectContext) throws -> [Violation] {
        let tasks = try fetchAllTasks(in: context)
        var violations: [Violation] = []
        for cycle in detectCycles(in: tasks) {
            violations.append(.parentCycle(memberIDs: cycle.compactMap(\.id)))
        }
        for task in liveUnderTrashedTasks(in: tasks) {
            guard let taskID = task.id, let parentID = task.parent?.id else { continue }
            violations.append(.liveUnderTrashedAncestor(taskID: taskID, trashedParentID: parentID))
        }
        for (parent, members) in positionTieGroups(in: tasks) {
            violations.append(.positionTie(parentID: parent?.id, taskIDs: members.compactMap(\.id)))
        }
        return violations
    }

    /// Scans and repairs every violation in place, staged so each stage's
    /// fix is visible to the next: cycles are broken first (so descendant/
    /// live-under-trashed checks walk a well-formed tree), live-under-
    /// trashed nodes are promoted to root second (a promotion moves a node
    /// into the root sibling group, which position-tie detection must see
    /// *after* promotion, not before), and position ties are healed last.
    /// Each stage re-fetches current state rather than reusing a
    /// pre-computed list, so this is correct regardless of what the prior
    /// stage changed. Returns every violation found (and fixed, except a
    /// skipped ambiguous cycle — see `breakCycle`). The caller must save.
    @discardableResult
    public static func repair(in context: NSManagedObjectContext) throws -> [Violation] {
        var found: [Violation] = []

        for cycle in detectCycles(in: try fetchAllTasks(in: context)) {
            found.append(.parentCycle(memberIDs: cycle.compactMap(\.id)))
            breakCycle(cycle)
        }

        for task in liveUnderTrashedTasks(in: try fetchAllTasks(in: context)) {
            guard let taskID = task.id, let parentID = task.parent?.id else { continue }
            found.append(.liveUnderTrashedAncestor(taskID: taskID, trashedParentID: parentID))
            TaskTreeRepair.promoteToRoot(task)
        }

        let freshTasks = try fetchAllTasks(in: context)
        var repairedParents: Set<NSManagedObjectID?> = []
        for (parent, members) in positionTieGroups(in: freshTasks) {
            found.append(.positionTie(parentID: parent?.id, taskIDs: members.compactMap(\.id)))
            let key = parent?.objectID
            guard !repairedParents.contains(key) else { continue }
            repairedParents.insert(key)
            recompactLiveSiblings(ofParent: parent, in: freshTasks)
        }

        return found
    }

    // MARK: - Fetch

    private static func fetchAllTasks(in context: NSManagedObjectContext) throws -> [LillistTask] {
        try context.fetch(NSFetchRequest<LillistTask>(entityName: "LillistTask"))
    }

    // MARK: - Cycle detection + repair

    /// Walks every task's `.parent` chain looking for a back-edge. Each
    /// node is added to `globalVisited` once its walk concludes (cyclic or
    /// not), so no node is walked twice across the whole scan — this is
    /// what keeps the scan O(n) rather than O(n·depth) in the worst case,
    /// and (more importantly) is what makes it terminate at all on a graph
    /// that contains a cycle: a plain per-task `while let parent = ...`
    /// with no cross-task memory would re-walk into the same cycle from
    /// every node feeding into it.
    private static func detectCycles(in tasks: [LillistTask]) -> [[LillistTask]] {
        var globalVisited: Set<NSManagedObjectID> = []
        var cycles: [[LillistTask]] = []
        for task in tasks {
            guard !globalVisited.contains(task.objectID) else { continue }
            var path: [LillistTask] = []
            var cursor: LillistTask? = task
            while let node = cursor {
                if globalVisited.contains(node.objectID) { break }
                if let idx = path.firstIndex(where: { $0.objectID == node.objectID }) {
                    cycles.append(Array(path[idx...]))
                    break
                }
                path.append(node)
                cursor = node.parent
            }
            globalVisited.formUnion(path.map(\.objectID))
        }
        return cycles
    }

    /// Council decision (`.council/h7-cycle-break-tiebreaker-rule/DECISION.md`):
    /// sever the cycle member with the lexicographically-greatest
    /// `id.uuidString` — `id` is immutable and present identically on every
    /// replica once a row has synced at all, unlike `modifiedAt` (mutated by
    /// nearly every write, likely still diverging between two uncoordinated
    /// devices repairing the same not-yet-converged cycle) or `createdAt`
    /// (nilable, and imports duplicate-resolution semantics that don't
    /// transfer to a symmetric edge-level defect with no "original" side).
    ///
    /// Binding on implementation, not just the rule: `id.uuidString` is not
    /// provably tie-free in this codebase (see `TaskDuplicateReconciler`'s
    /// doc comment — issue #66's duplicate-row shape is a reachable
    /// precondition). If two-plus members share an id (or any member has a
    /// nil id), this does **not** guess via incidental fetch order — it
    /// skips breaking this specific cycle and logs, deferring to
    /// `TaskDuplicateReconciler` to resolve the duplicate first, after
    /// which the tie clears and a later pass repairs the cycle cleanly.
    private static func breakCycle(_ members: [LillistTask]) {
        let ids = members.compactMap(\.id)
        guard ids.count == members.count, Set(ids).count == members.count else {
            LillistLog.store.error("TreeIntegrityChecker: skipped breaking a parent-cycle — ambiguous member identity (nil or duplicate id); deferring to TaskDuplicateReconciler")
            return
        }
        guard let winner = members.max(by: { $0.id!.uuidString < $1.id!.uuidString }) else { return }
        TaskTreeRepair.promoteToRoot(winner)
    }

    // MARK: - Live-under-trashed detection

    private static func liveUnderTrashedTasks(in tasks: [LillistTask]) -> [LillistTask] {
        tasks.filter { $0.deletedAt == nil && $0.parent?.deletedAt != nil }
    }

    // MARK: - Position-tie detection + repair

    private static func positionTieGroups(in tasks: [LillistTask]) -> [(parent: LillistTask?, members: [LillistTask])] {
        let live = tasks.filter { $0.deletedAt == nil }
        let byParent = Dictionary(grouping: live, by: { $0.parent?.objectID })
        var result: [(LillistTask?, [LillistTask])] = []
        for siblings in byParent.values {
            let byPosition = Dictionary(grouping: siblings, by: { $0.position })
            for tied in byPosition.values where tied.count > 1 {
                result.append((tied.first?.parent, tied))
            }
        }
        return result
    }

    /// Re-spaces every live sibling under `parent` (not just the tied
    /// subset) via the same `PositionCompactor` + `SiblingOrder` building
    /// blocks `TaskStore.recompactSiblings` uses — reimplemented here since
    /// that helper is `private` to `TaskStore` and this type deliberately
    /// has no dependency on it.
    private static func recompactLiveSiblings(ofParent parent: LillistTask?, in tasks: [LillistTask]) {
        let siblings = tasks.filter { $0.deletedAt == nil && $0.parent?.objectID == parent?.objectID }
        let sorted = siblings.sorted { a, b in
            guard let idA = a.id, let idB = b.id else { return false }
            return SiblingOrder.precedes(positionA: a.position, idA: idA, positionB: b.position, idB: idB)
        }
        let respaced = PositionCompactor.recompact(positions: sorted.map(\.position))
        for (sibling, newPosition) in zip(sorted, respaced) {
            sibling.position = newPosition
        }
    }
}
