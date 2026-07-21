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
/// `@unchecked Sendable`: the only mutable state (the observer token) is
/// touched on the main actor in `start()`/`stop()`.
public final class TaskDuplicateReconciler: @unchecked Sendable {
    private let persistence: PersistenceController
    private var observer: NSObjectProtocol?

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
        let ctx = persistence.container.viewContext
        let identifier = persistence.container as? NSPersistentCloudKitContainer
        _ = try? await Self.reconcileDuplicates(in: ctx, mirrorIdentifier: identifier)
    }

    /// Pure-ish core: find every `LillistTask` id shared by more than one
    /// row, and — only when the mirror signal is unambiguous — merge each
    /// group down to the CloudKit-backed survivor. Returns the number of
    /// rows deleted.
    ///
    /// `nonisolated static` so tests can drive it directly against an
    /// in-memory context with an injected `MirroredObjectIdentifying` fake,
    /// without a live CloudKit container.
    @discardableResult
    public nonisolated static func reconcileDuplicates(
        in ctx: NSManagedObjectContext,
        mirrorIdentifier: (any MirroredObjectIdentifying)?
    ) async throws -> Int {
        try await ctx.perform {
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
                    ctx.delete(loser)
                    deletedCount += 1
                }
            }
            if deletedCount > 0 {
                try ctx.save()
            }
            return deletedCount
        }
    }
}
