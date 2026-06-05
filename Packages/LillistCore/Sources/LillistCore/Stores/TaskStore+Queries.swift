import Foundation
import CoreData

extension TaskStore {
    /// All tasks anywhere in the tree with `isPinned == true`, excluding
    /// soft-deleted ones. Sorted by `position` within their respective
    /// parents (so the order is stable but may interleave parents).
    ///
    /// Plan 7 reads this for the sidebar's Pinned section.
    public func pinned() async throws -> [TaskRecord] {
        let ctx = persistence.container.viewContext
        return try await ctx.perform { [self] in
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "isPinned == YES AND deletedAt == nil")
            req.sortDescriptors = [
                NSSortDescriptor(key: "position", ascending: true),
                NSSortDescriptor(key: "createdAt", ascending: true)
            ]
            req.fetchBatchSize = TaskStore.listFetchBatchSize
            return try ctx.fetch(req).map(record(from:))
        }
    }

    /// All non-trash tasks tagged with `tagID` (or any descendant tag, if
    /// `includeDescendants` is true). Ordered by the given `SortField`.
    ///
    /// Plan 7 reads this for the middle column when a Tag is selected.
    public func tasks(
        forTag tagID: UUID,
        includeDescendants: Bool = true,
        sort: SortField = .deadline,
        ascending: Bool = true
    ) async throws -> [TaskRecord] {
        let ctx = persistence.container.viewContext
        return try await ctx.perform { [self] in
            // Resolve tagID + descendants → Set<UUID> of relevant tag IDs.
            let tagReq = NSFetchRequest<Tag>(entityName: "Tag")
            tagReq.predicate = NSPredicate(format: "id == %@", tagID as CVarArg)
            guard let rootTag = try ctx.fetch(tagReq).first else {
                return []
            }
            var matchTagIDs: Set<UUID> = []
            if let id = rootTag.id { matchTagIDs.insert(id) }
            if includeDescendants {
                for d in rootTag.descendants {
                    if let id = d.id { matchTagIDs.insert(id) }
                }
            }
            guard !matchTagIDs.isEmpty else { return [] }
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "deletedAt == nil AND ANY tags.id IN %@", Array(matchTagIDs))
            req.sortDescriptors = SmartFilterStore.sortDescriptors(field: sort, ascending: ascending)
            req.fetchBatchSize = TaskStore.listFetchBatchSize
            // De-dup: a task tagged with both a parent and a child tag must
            // appear once, not once per matching tag.
            let raw = try ctx.fetch(req)
            var seen: Set<UUID> = []
            var out: [TaskRecord] = []
            for t in raw {
                guard let id = t.id, !seen.contains(id) else { continue }
                seen.insert(id)
                out.append(record(from: t))
            }
            return out
        }
    }

    /// For each task ID, return the parent-title path leading to (but not
    /// including) that task. A root-level task maps to an empty array.
    /// Missing IDs and orphaned tasks (whose parent was hard-deleted) map
    /// to whatever chain is reachable.
    ///
    /// Plan 7 renders this above each row in flat smart-filter / tag results.
    public func breadcrumbs(for ids: [UUID]) async throws -> [UUID: [String]] {
        guard !ids.isEmpty else { return [:] }
        let ctx = persistence.container.viewContext
        return try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id IN %@", ids)
            let tasks = try ctx.fetch(req)
            var out: [UUID: [String]] = [:]
            for task in tasks {
                guard let id = task.id else { continue }
                var trail: [String] = []
                var cursor = task.parent
                while let p = cursor {
                    trail.append(p.title ?? "")
                    cursor = p.parent
                }
                out[id] = trail.reversed()
            }
            return out
        }
    }
}
