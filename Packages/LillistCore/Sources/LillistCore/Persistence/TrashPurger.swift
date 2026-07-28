import Foundation
import CoreData

/// Executes a trash purge — hard-deleting every `LillistTask` matching a
/// caller-supplied predicate, off the main-queue `viewContext` — via
/// chunked managed-object-context deletes rather than `NSBatchDeleteRequest`.
///
/// C4/X4: `NSBatchDeleteRequest` bypasses the managed-object graph entirely
/// (it executes as a direct SQL delete via `context.execute(_:)`, never
/// `context.save()`), so `NSPersistentCloudKitContainer` never observes the
/// deletion and never exports a tombstone for it — a purged task can
/// resurrect from the CloudKit zone on the next import. `TaskStore.hardDelete`
/// already deletes correctly (`context.delete(_:)` + `save()`), and is the
/// existence proof that a normal context delete plus the model's `Cascade`
/// delete rules produce the same end state `CascadeReaper`'s manual
/// traversal computes — this type does the same thing at purge scale.
///
/// Shared by `TaskStore.batchPurge` (user-initiated "Empty Trash") and
/// `AutoPurgeJob.run` (retention-window sweep), whose bodies were
/// near-identical before this extraction.
///
/// `fetchCandidateRootObjectIDs` and `purgeChunk` are exposed as separate
/// steps (rather than folded entirely into `purge`) so a test can drive
/// them independently — see `X14PurgeRevalidationTests`, which inserts a
/// restore between the two to prove the delete-time predicate recheck
/// (below) actually closes that window.
enum TrashPurger {
    /// Roots processed, and saved, per chunk. 200 doubles
    /// `TaskStore.listFetchBatchSize` (100, the existing paging precedent in
    /// this module) — few enough that one chunk's `CascadeReaper.planPurge`
    /// call plus its save stays well within interactive latency even on
    /// contended hardware, large enough that a 10k-row "Empty Trash" is tens
    /// of round trips, not thousands. No other numeric precedent exists in
    /// this codebase for a delete-chunk size; revisit if a real-world purge
    /// shows chunk-boundary overhead.
    static let defaultChunkSize = 200

    /// Step 0: snapshot the candidate root objectIDs — matched victims whose
    /// parent doesn't *also* match the predicate (so a nested victim is
    /// reached via its ancestor's cascade rather than independently
    /// processed). `predicateFormat`/`arguments` (not a prebuilt
    /// `NSPredicate`) preserve the existing hoist-and-rebuild pattern:
    /// `NSPredicate` is not `Sendable` and must never be captured across the
    /// `ctx.perform` actor boundary.
    static func fetchCandidateRootObjectIDs(
        predicateFormat: String,
        arguments: [any Sendable],
        context ctx: NSManagedObjectContext
    ) async throws -> [NSManagedObjectID] {
        try await ctx.perform {
            let predicate = NSPredicate(format: predicateFormat, argumentArray: arguments)
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = predicate
            let matched = try ctx.fetch(req)
            let roots = matched.filter { task in
                guard let parent = task.parent else { return true }
                return !predicate.evaluate(with: parent)
            }
            return roots.map(\.objectID)
        }
    }

    /// Processes one chunk of candidate root objectIDs: revalidates each
    /// against the *original* predicate (X14 — not merely "still has
    /// `deletedAt`"; `AutoPurgeJob`'s predicate also bounds by cutoff date,
    /// and `softDelete` unconditionally re-stamps `deletedAt = now` on an
    /// already-trashed task, so a full re-evaluation is required to catch a
    /// re-trash that moves a row back inside the retention window without
    /// `deletedAt` ever becoming nil), re-plans C1's live-descendant barrier
    /// fresh (a descendant could have gone live in the window since Step 0
    /// or an earlier chunk), deletes the surviving roots (Core Data's own
    /// `Cascade` delete rule removes the rest of each root's subtree
    /// automatically), and merges the deletions into `viewContext`.
    ///
    /// - Returns: The number of `LillistTask` rows purged in this chunk
    ///   (roots plus every cascade-reachable descendant task).
    @discardableResult
    static func purgeChunk(
        _ chunk: [NSManagedObjectID],
        predicateFormat: String,
        arguments: [any Sendable],
        context ctx: NSManagedObjectContext,
        viewContext: NSManagedObjectContext
    ) async throws -> Int {
        guard !chunk.isEmpty else { return 0 }

        let (purgedTaskCount, allDeletable): (Int, [NSManagedObjectID]) = try await ctx.perform {
            let predicate = NSPredicate(format: predicateFormat, argumentArray: arguments)

            // X14: re-validate against the ORIGINAL victim predicate at
            // delete time — a task restored, or re-trashed with a fresher
            // deletedAt that now falls outside a retention-window
            // predicate, must survive.
            let liveRoots: [LillistTask] = chunk.compactMap { objectID in
                guard let task = try? ctx.existingObject(with: objectID) as? LillistTask,
                      predicate.evaluate(with: task) else { return nil }
                return task
            }
            guard !liveRoots.isEmpty else { return (0, []) }

            // C1: bound the cascade at any live descendant, promoting it to
            // root (and saving) before the delete below — recomputed fresh
            // per chunk so a descendant that went live in the window since
            // Step 0 (or an earlier chunk) is still caught.
            let plan = CascadeReaper.planPurge(ofTrashedRoots: liveRoots)
            if !plan.liveDescendantsToPromote.isEmpty {
                for objectID in plan.liveDescendantsToPromote {
                    if let child = try? ctx.existingObject(with: objectID) as? LillistTask {
                        TaskTreeRepair.promoteToRoot(child)
                    }
                }
                try ctx.save()
            }

            let purgedTaskCount = plan.deletable.reduce(into: 0) { count, objectID in
                if objectID.entity.name == "LillistTask" { count += 1 }
            }

            for root in liveRoots { ctx.delete(root) }
            try ctx.save()

            return (purgedTaskCount, plan.deletable)
        }

        guard !allDeletable.isEmpty else { return 0 }

        // `plan.deletable` (all four cascade-reachable entity types, not
        // just the roots) is required here: only explicitly deleting the
        // root objects and relying on Core Data's in-memory cascade to
        // remove the rest would otherwise leave viewContext holding
        // dangling faults for the cascaded descendants.
        await viewContext.perform {
            NSManagedObjectContext.mergeChanges(
                fromRemoteContextSave: [NSDeletedObjectsKey: allDeletable],
                into: [viewContext]
            )
        }

        return purgedTaskCount
    }

    /// Composes `fetchCandidateRootObjectIDs` + `purgeChunk` over the full
    /// candidate set, chunked at `chunkSize`.
    ///
    /// - Returns: The total number of `LillistTask` rows purged (roots plus
    ///   every cascade-reachable descendant task, across every chunk).
    static func purge(
        predicateFormat: String,
        arguments: [any Sendable],
        context ctx: NSManagedObjectContext,
        viewContext: NSManagedObjectContext,
        chunkSize: Int = defaultChunkSize
    ) async throws -> Int {
        let rootObjectIDs = try await fetchCandidateRootObjectIDs(
            predicateFormat: predicateFormat,
            arguments: arguments,
            context: ctx
        )

        var purgedCount = 0
        var start = 0
        while start < rootObjectIDs.count {
            let end = Swift.min(start + chunkSize, rootObjectIDs.count)
            let chunk = Array(rootObjectIDs[start..<end])
            purgedCount += try await purgeChunk(
                chunk,
                predicateFormat: predicateFormat,
                arguments: arguments,
                context: ctx,
                viewContext: viewContext
            )
            start = end
        }
        return purgedCount
    }
}
