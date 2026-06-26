---
module: "Packages/LillistCore/Sources/LillistCore/Stores (chunk 2)"
summary: "Single async gateway for all LillistTask CRUD, status, reorder, and trash operations; returns DTO-only (TaskRecord)."
read_when: "Touching task creation or status transitions"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift
    blob: 5dce5baf177ea06f694ffe7ebc4694ec6c488750
references_modules: [Packages-LillistCore-Sources-LillistCore-Diagnostics, Packages-LillistCore-Sources-LillistCore-ManagedObjects, Packages-LillistCore-Sources-LillistCore-Ordering, Packages-LillistCore-Sources-LillistCore-Persistence, Packages-LillistCore-Sources-LillistCore-Recurrence, Packages-LillistUI-Sources-LillistUI-Recurrence]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistCore/Sources/LillistCore/Stores (chunk 2)

## Purpose

TaskStore is the single async gateway for all LillistTask CRUD, status transitions, hierarchy manipulation, fractional-position reorder, tag assignment, and soft-delete/trash management. It owns the invariant that no NSManagedObject crosses the module boundary: every public API returns TaskRecord DTOs, and every mutation serializes through viewContext.perform with a rollback-on-error guarantee. If it vanished, no caller could create, read, update, reorder, or delete tasks in a type-safe or concurrency-safe way.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `NewTaskPlacement` | enum | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:13` | `.top` inserts a new task before the first sibling (user capture); `.bottom` appends after the last sibling (structural creates and import paths). |
| `ReparentTarget` | enum | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:373` | `.infer` derives the new parent from anchors (historic default); `.explicit(UUID?)` takes a caller-supplied authoritative parent, including `nil` for top-level, bypassing inference. |
| `TaskDraft` | struct | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:130` | Mutable view of a task's editable fields passed to `update`'s closure; mutations are applied back to the managed object and saved after the block returns. |
| `TaskRecord` | struct | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:71` | Sendable, Equatable value-type DTO carrying all fields of a LillistTask; callers outside LillistCore never receive an NSManagedObject. |
| `TaskStore` | class | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:18` | Single async gateway for all LillistTask mutations and reads; all public methods serialize via viewContext.perform, rollback on error, and return only TaskRecord DTOs. |
| `archive` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:668` | Stamps `archivedAt = now` only on IDs that lack it; returns the subset of IDs actually flipped, enabling scoped undo in the caller. |
| `assignTag` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:869` | Associates a Tag (by tagID) with a task; idempotent — silently no-ops if the tag is already assigned. |
| `children` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:264` | Returns all non-trashed direct children of parentID sorted by position/createdAt; uses fetchBatchSize 100 to avoid materializing the full sibling set at once. |
| `children` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:286` | Paged variant: returns at most `limit` rows from `offset` in the same position/createdAt order; `limit <= 0` means no limit; offset beyond the end yields an empty array. |
| `create` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:143` | Creates a new task with a validated title and fractional position; `placement` controls head vs. tail insertion; returns the new UUID. |
| `fetch` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:197` | Returns the TaskRecord for `id` or throws `LillistError.notFound` if absent. |
| `fetchManagedObject` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:921` | Fetches the live LillistTask managed object for `id` within `ctx`; package-internal (non-private) for use by sibling stores; throws `notFound` if absent. |
| `hardDelete` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:247` | Permanently removes the task from the store with no Trash step; prefer `softDelete` for all user-initiated deletion. |
| `nextPosition` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:931` | Returns the next available fractional position for a child of `parent` (nil = top-level); must be called inside a `context.perform` block. |
| `nextPositionDetail` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:945` | Returns `(assigned, observedMax)`: the position to assign and the edge sibling position observed, so `create` can include both in its diagnostic payload for reorder-tie RCA. |
| `normalizeSiblingsIfDegenerate` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:1009` | Compacts sibling positions under `parentID` only when any adjacent pair is non-strictly-increasing; idempotent on healthy data; called at load seams before the first reorder. |
| `purgeAll` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:772` | Hard-deletes every task with `deletedAt != nil` (the full Trash); returns the count removed. Distinct from AutoPurgeJob, which enforces a retention window. |
| `record` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:1058` | Projects a LillistTask managed object to a TaskRecord DTO; package-internal (non-private), called by all read paths in the store. |
| `reorder` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:378` | Repositions a task between afterID and beforeID anchors; heals degenerate sibling positions (ties, inversions, underflows) before computing a new position; honors ReparentTarget for drag-to-reparent. |
| `reparent` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:316` | Moves `id` to a new parent (nil = top-level), appending it at the tail position of the new sibling group; rejects cycles via Validators.wouldCreateCycle. |
| `restore` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:736` | Clears `deletedAt` from a trashed task and any children whose `deletedAt` matches the parent's original timestamp, avoiding unintended restoration of separately-deleted children. |
| `softDelete` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:717` | Sets `deletedAt = now` on `id` and all descendants recursively (only those not already trashed); reconciles notifications after save. |
| `tagIDs` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:903` | Returns an unordered array of UUIDs for all tags currently assigned to `taskID`. |
| `transition` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:568` | Transitions `id` to `newStatus`, writes a journal entry, sets/clears closedAt and archivedAt as appropriate, and spawns the next recurrence instance on close. |
| `trashed` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:755` | Returns all tasks with `deletedAt != nil` sorted by deletedAt descending (most recently trashed first). |
| `unarchive` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:695` | Clears `archivedAt` on every task in `ids`; idempotent — rows already at nil are left untouched. |
| `unassignTag` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:887` | Removes the Tag-to-task association for `tagID` and `taskID`; no-op if the tag was never assigned. |
| `update` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:206` | Applies a mutation closure to a TaskDraft snapshot of `id`, validates the result, saves, and reconciles notifications for anchor-field (start/deadline) changes. |
| `validateTitle` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:1050` | Throws `LillistError.validationFailed` if `title` is empty after whitespace/newline trimming; delegates the rule to `isCommittableTitle`. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `ReorderCapture` | class | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:546` | Mutable carrier that bridges pre-await values (anchor positions, didRecompact, computedPosition) from inside context.perform to both the success and error emitReorderDiag call sites; without it the throwing path of reorder could not emit a full diagnostic payload (TaskStore.swift:546-551). |
| `fetchTag` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:911` | The only Tag-by-UUID lookup path in the store; all tag-mutation operations (assignTag, unassignTag) funnel through it to resolve the managed object before modifying the relationship (TaskStore.swift:911-917). |
| `recompactSiblings` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:981` | Called by reorder on both the anchor-tie/inversion heal path and the underflow path to re-space siblings before position computation; without it reorder cannot recover from degenerate sibling sets and would always throw on tied positions (TaskStore.swift:981-1001). |

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
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.transition -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.stampCurrentSchemaVersion (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.transition -> Packages-LillistCore-Sources-LillistCore-Recurrence.spawnIfNeeded (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.unarchive -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.stampCurrentSchemaVersion (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.unassignTag -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.stampCurrentSchemaVersion (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.update -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.stampCurrentSchemaVersion (calls)`

## Type notes

TaskStore is `@unchecked Sendable` (TaskStore.swift:18); concurrency safety is manually enforced by serializing all mutations and reads inside `context.perform` with `context.rollback()` in each catch block. `notificationScheduler`, `breadcrumbs`, and `diagnosticLog` are property-injected rather than init-injected so the large body of existing `TaskStore(persistence:)` test call sites continue to compile unchanged (TaskStore.swift:24-41). ReorderCapture and TransitionCapture are `@unchecked Sendable` private classes used as mutable carriers across the `perform`/`await` boundary — safe because writes happen on the context queue and reads occur only after `await` completes (TaskStore.swift:546-551, 635-639). TaskDraft exposes no public `init` (TaskStore.swift:130-138): callers cannot construct one outside the store; only `update`'s closure receives a value. `fetchManagedObject` and `record` are non-`private` (package-internal) so sibling stores can share the lookup and projection logic without exposing it publicly (TaskStore.swift:921, 1058). `isCommittableTitle` is `nonisolated static` so SwiftUI button-disabled predicates can call it synchronously without an async round-trip (TaskStore.swift:1046).

## External deps

- CoreData — imported
- Foundation — imported
- os — imported

## Gotchas

Reorder heal-then-recheck: after recompactSiblings runs, the in-memory anchor objects already reflect new positions — do NOT call context.refresh, which would overwrite unsaved changes with stale store values (TaskStore.swift:418-421). Tie-swap: when recompaction assigns positions in uuid-string order that conflicts with drag intent, the two anchor positions are explicitly swapped to honour the caller (TaskStore.swift:475-479); post-heal position uses afterTask.position + 0.5 (not a midpoint) to avoid colliding with an integer sibling that might sit at the midpoint (TaskStore.swift:484-487). applySoftDelete recurses into children but only stamps ones where deletedAt == nil (TaskStore.swift:849-853); clearSoftDelete only undeletes children whose deletedAt matches the parent's exact original timestamp, preventing accidental restoration of separately-deleted children (TaskStore.swift:860-864). batchPurge filters to roots only before passing to CascadeReaper to avoid double-deleting a parent and child (TaskStore.swift:818-821). listFetchBatchSize = 100 limits per-page faulting so large sibling sets are not fully materialized on viewContext at once (TaskStore.swift:47).
