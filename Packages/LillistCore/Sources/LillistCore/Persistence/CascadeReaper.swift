import Foundation
import CoreData

/// Computes the complete set of `NSManagedObjectID`s that Core Data's
/// `Cascade` delete rules would remove when a set of `LillistTask`s is
/// deleted — so an `NSBatchDeleteRequest` can reproduce those rules,
/// which batch deletes otherwise skip.
///
/// `NSBatchDeleteRequest` bypasses the delete-rule machinery. On the
/// SQLite store the DB rows are still cascaded via foreign keys, but the
/// result set (`resultTypeObjectIDs`) reports only the *explicitly named*
/// IDs — so merging that incomplete set into the `viewContext` leaves the
/// cascaded children as dangling in-memory objects. Enumerating every
/// reachable ID here keeps the merge (and the `viewContext`) consistent.
///
/// Cascade graph (per `LillistModel.xcdatamodel`):
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
    /// including the roots themselves.
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
