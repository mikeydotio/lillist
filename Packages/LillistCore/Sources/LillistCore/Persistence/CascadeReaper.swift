import Foundation
import CoreData

/// Computes the complete set of `NSManagedObjectID`s that Core Data's
/// `Cascade` delete rules would remove when a set of `LillistTask`s is
/// deleted, two ways:
///
/// - `objectIDs(forDeleting:)` — the **unconditional** closure (every
///   descendant, regardless of its own `deletedAt`). Used by
///   `TaskStore.hardDelete` to collect the doomed task-id closure for
///   notification cancellation (H3) before deleting — `hardDelete` has no
///   live/trashed barrier concept of its own; it permanently removes a
///   specific task and everything under it, full stop.
/// - `planPurge(ofTrashedRoots:)` — the **trash-bounded** closure: stops at
///   the first live (`deletedAt == nil`) descendant on each branch and
///   reports it separately for promotion-to-root rather than deletion (C1).
///   Used by `TrashPurger`, which both purge entry points
///   (`TaskStore.batchPurge`, `AutoPurgeJob.run`) delegate to.
///
/// Both traversals mirror the model's actual `Cascade` graph
/// (`LillistModel.xcdatamodel`), so neither can drift from what a real
/// `context.delete(_:)` + `save()` will actually remove:
/// - `LillistTask.children`          → Cascade (recursive)
/// - `LillistTask.journalEntries`    → Cascade
/// - `LillistTask.attachments`       → Cascade
/// - `LillistTask.notificationSpecs` → Cascade
/// - `JournalEntry.attachments`      → Cascade
///
/// `tags`, `series`, `seriesAsSeed`, and `parent` are Nullify and are
/// intentionally excluded.
///
/// - Note: This type performs relationship faults synchronously and must
///   therefore be invoked on the owning context's queue (i.e. inside
///   a `context.perform` or `context.performAndWait` block).
public enum CascadeReaper {

    // MARK: - Public API

    /// Returns every `objectID` that deleting `roots` would cascade to,
    /// including the roots themselves. Unconditional — does not stop at a
    /// live descendant; see `planPurge(ofTrashedRoots:)` for the
    /// trash-bounded variant.
    ///
    /// - Parameter roots: The top-level `LillistTask` objects being deleted.
    /// - Returns: A deduplicated array of `NSManagedObjectID`s covering the
    ///   entire reachable cascade subtree.
    public static func objectIDs(forDeleting roots: [LillistTask]) -> [NSManagedObjectID] {
        var collected: Set<NSManagedObjectID> = []
        for root in roots {
            collect(task: root, into: &collected)
        }
        return Array(collected)
    }

    // MARK: - Purge planning (C1)

    /// The outcome of planning a trash purge: which objectIDs are safe to
    /// hard-delete, and which live descendants must be promoted to root
    /// (`parent = nil`) **before** the delete executes.
    ///
    /// `objectIDs(forDeleting:)` above recurses into every descendant of a
    /// root unconditionally — correct for a fully cascade-trashed subtree,
    /// but wrong when a descendant is live (`deletedAt == nil`): Core Data's
    /// `Cascade` delete rule cascades a `context.delete(_:)` through the
    /// `children` relationship unconditionally too — it has no concept of
    /// `deletedAt` — so merely *excluding* a live descendant's objectID from
    /// the deletion set is not enough. Deleting its still-attached trashed
    /// ancestor would take it down anyway, regardless of what this type
    /// reports. The only way to actually spare it is to sever its `parent`
    /// link first, via a normal managed-object mutation + save, so it is no
    /// longer reachable by the cascade at all.
    public struct PurgePlan: Sendable {
        /// Every objectID (across all reaped entities) safe to hard-delete.
        public let deletable: [NSManagedObjectID]
        /// Live `LillistTask` objectIDs that must have `parent` set to `nil`
        /// and be saved *before* `deletable` is deleted.
        public let liveDescendantsToPromote: [NSManagedObjectID]
    }

    /// Plans a purge of `roots` (top-level trashed `LillistTask`s), bounding
    /// the cascade at the first live descendant encountered on each branch:
    /// that node (and, structurally, its own subtree along with it, live or
    /// trashed) is excluded from `deletable` and reported in
    /// `liveDescendantsToPromote` instead. A promoted node's own descendants
    /// stay attached to it and are never independently walked or reaped —
    /// they aren't reachable from any of `roots` once the barrier node is
    /// detached.
    public static func planPurge(ofTrashedRoots roots: [LillistTask]) -> PurgePlan {
        var deletable: Set<NSManagedObjectID> = []
        var promote: Set<NSManagedObjectID> = []
        for root in roots {
            collectForPurge(task: root, into: &deletable, promote: &promote)
        }
        return PurgePlan(deletable: Array(deletable), liveDescendantsToPromote: Array(promote))
    }

    private static func collectForPurge(
        task: LillistTask,
        into deletable: inout Set<NSManagedObjectID>,
        promote: inout Set<NSManagedObjectID>
    ) {
        guard deletable.insert(task.objectID).inserted else { return }

        if let entries = task.journalEntries as? Set<JournalEntry> {
            for entry in entries {
                collect(entry: entry, into: &deletable)
            }
        }
        if let attachments = task.attachments as? Set<Attachment> {
            for attachment in attachments {
                deletable.insert(attachment.objectID)
            }
        }
        if let specs = task.notificationSpecs as? Set<NotificationSpec> {
            for spec in specs {
                deletable.insert(spec.objectID)
            }
        }
        if let children = task.children as? Set<LillistTask> {
            for child in children {
                if child.deletedAt == nil {
                    // Live-under-trashed barrier: spare it (and, structurally,
                    // everything still attached to it) — do not recurse further.
                    promote.insert(child.objectID)
                    continue
                }
                collectForPurge(task: child, into: &deletable, promote: &promote)
            }
        }
    }

    // MARK: - Private traversal

    private static func collect(task: LillistTask, into set: inout Set<NSManagedObjectID>) {
        // Guard against cycles and already-visited nodes.
        guard set.insert(task.objectID).inserted else { return }

        // LillistTask.journalEntries → Cascade
        if let entries = task.journalEntries as? Set<JournalEntry> {
            for entry in entries {
                collect(entry: entry, into: &set)
            }
        }

        // LillistTask.attachments → Cascade
        if let attachments = task.attachments as? Set<Attachment> {
            for attachment in attachments {
                set.insert(attachment.objectID)
            }
        }

        // LillistTask.notificationSpecs → Cascade
        if let specs = task.notificationSpecs as? Set<NotificationSpec> {
            for spec in specs {
                set.insert(spec.objectID)
            }
        }

        // LillistTask.children → Cascade (recursive)
        if let children = task.children as? Set<LillistTask> {
            for child in children {
                collect(task: child, into: &set)
            }
        }
    }

    private static func collect(entry: JournalEntry, into set: inout Set<NSManagedObjectID>) {
        guard set.insert(entry.objectID).inserted else { return }

        // JournalEntry.attachments → Cascade
        if let attachments = entry.attachments as? Set<Attachment> {
            for attachment in attachments {
                set.insert(attachment.objectID)
            }
        }
    }
}
