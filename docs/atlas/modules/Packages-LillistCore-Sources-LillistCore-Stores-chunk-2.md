---
module: "Packages/LillistCore/Sources/LillistCore/Stores (chunk 2)"
summary: "TaskStore: the single async gateway for all LillistTask CRUD, status, reorder, archive, trash, and tag operations."
read_when: "Touching task creation, status transitions, reorder, archive, trash, or syncCounts"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift
    blob: ec2935e696924801c3e4b1e18dec3a4ac617ad62
references_modules: [Packages-LillistCore-Sources-LillistCore-Diagnostics, Packages-LillistCore-Sources-LillistCore-ManagedObjects, Packages-LillistCore-Sources-LillistCore-Ordering, Packages-LillistCore-Sources-LillistCore-Persistence, Packages-LillistCore-Sources-LillistCore-Recurrence, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistUI-Sources-LillistUI-Recurrence]
generator: cartographer/4
baseline: 99321d774840d17affd02fe2ac63b01b3d8cbec3
---

# Module: Packages/LillistCore/Sources/LillistCore/Stores (chunk 2)

## Purpose

TaskStore is the single async gateway for all LillistTask CRUD, status transitions, reorder, archive, soft/hard delete, and tag assignment. It enforces the DTO boundary — every public API returns value-type TaskRecord structs, never NSManagedObjects — so no Core Data type escapes LillistCore. If it vanished, all layers above would have no safe, concurrency-correct path to read or mutate task data.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `NewTaskPlacement` | enum | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:14` | `.top` inserts a new task before the first sibling (user capture); `.bottom` appends after the last sibling (structural creates and import paths). |
| `ReparentTarget` | enum | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:374` | `.infer` derives the new parent from anchors (historic default); `.explicit(UUID?)` takes a caller-supplied authoritative parent, including `nil` for top-level, bypassing inference. |
| `SyncCounts` | struct | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:766` | Sendable, Equatable snapshot of local vs. mirrored task counts; `mirrored` is 0 in local-only mode (no cloud container). |
| `TaskDraft` | struct | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:131` | Mutable view of a task's editable fields passed to `update`'s closure; mutations are applied back to the managed object and saved after the block returns. |
| `TaskRecord` | struct | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:72` | Sendable, Equatable value-type DTO carrying all fields of a LillistTask; callers outside LillistCore never receive an NSManagedObject. |
| `TaskStore` | class | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:19` | Single async gateway for all LillistTask mutations and reads; all public methods serialize via viewContext.perform, rollback on error, and return only TaskRecord DTOs. |
| `archive` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:669` | Stamps `archivedAt = now` only on IDs that lack it; returns the subset of IDs actually flipped, enabling scoped undo in the caller. |
| `assignTag` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:907` | Associates a Tag (by tagID) with a task; idempotent — silently no-ops if the tag is already assigned. |
| `children` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:265` | Returns all non-trashed direct children of parentID sorted by position/createdAt; uses fetchBatchSize 100 to avoid materializing the full sibling set at once. |
| `children` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:287` | Paged variant: returns at most `limit` rows from `offset` in the same position/createdAt order; `limit <= 0` means no limit; offset beyond the end yields an empty array. |
| `create` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:144` | Creates a new task with a validated title and fractional position; `placement` controls head vs. tail insertion; returns the new UUID. |
| `fetch` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:198` | Returns the TaskRecord for `id` or throws `LillistError.notFound` if absent. |
| `fetchManagedObject` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:959` | Fetches the live LillistTask managed object for `id` within `ctx`; package-internal (non-private) for use by sibling stores; throws `notFound` if absent. |
| `hardDelete` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:248` | Permanently removes the task from the store with no Trash step; prefer `softDelete` for all user-initiated deletion. |
| `nextPosition` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:969` | Returns the next available fractional position for a child of `parent` (nil = top-level); must be called inside a `context.perform` block. |
| `nextPositionDetail` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:983` | Returns `(assigned, observedMax)`: the position to assign and the edge sibling position observed, so `create` can include both in its diagnostic payload for reorder-tie RCA. |
| `normalizeSiblingsIfDegenerate` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:1047` | Compacts sibling positions under `parentID` only when any adjacent pair is non-strictly-increasing; idempotent on healthy data; called at load seams before the first reorder. |
| `purgeAll` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:810` | Hard-deletes every task with `deletedAt != nil` (the full Trash); returns the count removed. Distinct from AutoPurgeJob, which enforces a retention window. |
| `record` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:1096` | Projects a LillistTask managed object to a TaskRecord DTO; package-internal (non-private), called by all read paths in the store. |
| `reorder` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:379` | Repositions a task between afterID and beforeID anchors; heals degenerate sibling positions (ties, inversions, underflows) before computing a new position; honors ReparentTarget for drag-to-reparent. |
| `reparent` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:317` | Moves `id` to a new parent (nil = top-level), appending it at the tail position of the new sibling group; rejects cycles via Validators.wouldCreateCycle. |
| `restore` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:737` | Clears `deletedAt` from a trashed task and any children whose `deletedAt` matches the parent's original timestamp, avoiding unintended restoration of separately-deleted children. |
| `softDelete` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:718` | Sets `deletedAt = now` on `id` and all descendants recursively (only those not already trashed); reconciles notifications after save. |
| `syncCounts` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:787` | Returns a SyncCounts with total local LillistTask rows and how many carry a CloudKit record identity; throws on Core Data errors. |
| `tagIDs` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:941` | Returns an unordered array of UUIDs for all tags currently assigned to `taskID`. |
| `transition` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:569` | Transitions `id` to `newStatus`, writes a journal entry, sets/clears closedAt and archivedAt as appropriate, and spawns the next recurrence instance on close. |
| `trashed` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:756` | Returns all tasks with `deletedAt != nil` sorted by deletedAt descending (most recently trashed first). |
| `unarchive` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:696` | Clears `archivedAt` on every task in `ids`; idempotent — rows already at nil are left untouched. |
| `unassignTag` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:925` | Removes the Tag-to-task association for `tagID` and `taskID`; no-op if the tag was never assigned. |
| `update` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:207` | Applies a mutation closure to a TaskDraft snapshot of `id`, validates the result, saves, and reconciles notifications for anchor-field (start/deadline) changes. |
| `validateTitle` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:1088` | Throws `LillistError.validationFailed` if `title` is empty after whitespace/newline trimming; delegates the rule to `isCommittableTitle`. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `ReorderCapture` | class | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:547` | Mutable carrier that bridges pre-await values (anchor positions, didRecompact, computedPosition) from inside context.perform to both the success and error emitReorderDiag call sites; without it the throwing path of reorder could not emit a full diagnostic payload (TaskStore.swift:546-551). |
| `fetchTag` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:949` | The only Tag-by-UUID lookup path in the store; all tag-mutation operations (assignTag, unassignTag) funnel through it to resolve the managed object before modifying the relationship (TaskStore.swift:911-917). |
| `recompactSiblings` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:1019` | Called by reorder on both the anchor-tie/inversion heal path and the underflow path to re-space siblings before position computation; without it reorder cannot recover from degenerate sibling sets and would always throw on tied positions (TaskStore.swift:981-1001). |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore -> Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticEvent (emits)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.applySoftDelete -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.stampCurrentSchemaVersion (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.archive -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.stampCurrentSchemaVersion (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.assignTag -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.stampCurrentSchemaVersion (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.batchPurge -> Packages-LillistCore-Sources-LillistCore-Persistence.batchDelete (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.batchPurge -> Packages-LillistCore-Sources-LillistCore-Persistence.makeBackgroundContext (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.batchPurge -> Packages-LillistCore-Sources-LillistCore-Persistence.objectIDs (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.clearSoftDelete -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.stampCurrentSchemaVersion (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.create -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.stampCurrentSchemaVersion (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.create -> Packages-LillistCore-Sources-LillistCore-Ordering.position (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.create -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.emitReorderDiag -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.emitTransitionDiag -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.nextPositionDetail -> Packages-LillistCore-Sources-LillistCore-Ordering.position (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.normalizeSiblingsIfDegenerate -> Packages-LillistCore-Sources-LillistCore-Diagnostics.zip (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.normalizeSiblingsIfDegenerate -> Packages-LillistCore-Sources-LillistCore-Ordering.precedes (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.normalizeSiblingsIfDegenerate -> Packages-LillistCore-Sources-LillistCore-Ordering.recompact (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.recompactSiblings -> Packages-LillistCore-Sources-LillistCore-Diagnostics.zip (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.recompactSiblings -> Packages-LillistCore-Sources-LillistCore-Ordering.position (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.recompactSiblings -> Packages-LillistCore-Sources-LillistCore-Ordering.precedes (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.recompactSiblings -> Packages-LillistCore-Sources-LillistCore-Ordering.recompact (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.reorder -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.stampCurrentSchemaVersion (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.reorder -> Packages-LillistCore-Sources-LillistCore-Ordering.anchorsAreOutOfOrder (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.reorder -> Packages-LillistCore-Sources-LillistCore-Ordering.needsCompaction (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.reorder -> Packages-LillistCore-Sources-LillistCore-Ordering.position (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.reparent -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.stampCurrentSchemaVersion (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.reparent -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.syncCounts -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.count (reads)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.transition -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.stampCurrentSchemaVersion (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.transition -> Packages-LillistCore-Sources-LillistCore-Recurrence.spawnIfNeeded (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.unarchive -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.stampCurrentSchemaVersion (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.unassignTag -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.stampCurrentSchemaVersion (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.update -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.stampCurrentSchemaVersion (calls)`

## Type notes

TaskStore is `public final class TaskStore: @unchecked Sendable` (TaskStore.swift:19); it uses the main-queue `viewContext` for most reads and the sync surface, and background contexts only for batch-delete paths (`batchPurge`, TaskStore.swift:846). Three optional property-injected sinks — `notificationScheduler` (TaskStore.swift:30), `breadcrumbs` (TaskStore.swift:35), and `diagnosticLog` (TaskStore.swift:41) — are nil in tests that don't need them; callers must set them after init, not at init time (TaskStore.swift:67). `TaskDraft` (TaskStore.swift:131) is the mutation carrier for `update`; `TaskRecord` (TaskStore.swift:72) is the immutable DTO returned by every read. `SyncCounts` (TaskStore.swift:766) pairs a local row count with the mirrored count from `NSPersistentCloudKitContainer.recordIDs(for:)`; `mirrored` is always 0 in local-only mode. `listFetchBatchSize = 100` (TaskStore.swift:48) pages Core Data faults to avoid faulting the full sibling set on the main queue at once.

## External deps

- CloudKit — imported
- CoreData — imported
- Foundation — imported
- os — imported

## Gotchas

`batchPurge` rebuilds `NSPredicate` inside its `@Sendable` background-context closure from a format string + `[any Sendable]` arguments, because `NSPredicate` is not `Sendable` and cannot be captured across the actor boundary (TaskStore.swift:829–840). `syncCounts` uses `NSPersistentCloudKitContainer.recordIDs(for:)` as the closest available "mirrored" signal; there is no per-record server-confirmation flag in NSPCC — see engineering-notes 2026-06-27 (TaskStore.swift:782–786). The three diagnostic/breadcrumb sinks are property-injected post-init so the 100+ existing `TaskStore(persistence:)` test call sites need no change (TaskStore.swift:26–41).
