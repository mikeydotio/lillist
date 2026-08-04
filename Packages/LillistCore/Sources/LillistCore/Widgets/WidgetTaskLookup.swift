import CoreData
import Foundation

/// `LIL-95`: the one read ``WidgetSnapshotBuilder`` needs beyond
/// ``WidgetSnapshotSource`` — resolving a **non-matching parent** so a
/// matched subtask can nest under it as a dimmed context row.
///
/// Deliberately separate from `WidgetSnapshotSource`: that seam is scoped to
/// *filter* reads (Interface Segregation — a fake owing the full
/// `SmartFilterStore`/`TaskStore` surface would be unwritable), and task-by-id
/// lookup is `TaskStore`'s responsibility, not `SmartFilterStore`'s.
public protocol WidgetTaskLookup: Sendable {
    /// The non-trashed tasks with these ids, in no particular order. An id
    /// with no matching (or trashed) task is simply absent from the result —
    /// this is a best-effort context lookup, not a strict fetch, so a missing
    /// or deleted parent degrades to "no context available" rather than
    /// throwing.
    func lookupTasks(ids: [UUID]) async throws -> [TaskStore.TaskRecord]
}

/// The production conformance: a single batched fetch, reusing `TaskStore`'s
/// own `record(from:)` mapping.
extension TaskStore: WidgetTaskLookup {
    public func lookupTasks(ids: [UUID]) async throws -> [TaskRecord] {
        guard !ids.isEmpty else { return [] }
        let ctx = persistence.container.viewContext
        return try await ctx.perform { [self] in
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id IN %@ AND deletedAt == nil", ids)
            req.fetchBatchSize = Self.listFetchBatchSize
            return try ctx.fetch(req).map(record(from:))
        }
    }
}
