---
module: "Packages/LillistCore/Sources/LillistCore/Stores (chunk 2)"
summary: "TaskStore — the async CRUD/hierarchy/reorder/status gateway over the LillistTask Core Data graph"
read_when: "TaskStore CRUD/reorder"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift
    blob: d6550bd426a2e84b71525b65fa4905e743804429
references_modules: [Packages-LillistCore-Sources-LillistCore-Persistence, Packages-LillistCore-Sources-LillistCore-Ordering, Packages-LillistCore-Sources-LillistCore-Recurrence, Packages-LillistCore-Sources-LillistCore-Notifications, Packages-LillistCore-Sources-LillistCore-CrashReporting, Packages-LillistCore-Sources-LillistCore-Diagnostics, Packages-LillistCore-Sources-LillistCore-ManagedObjects, Packages-LillistCore-Sources-LillistCore-Model, Packages-LillistCore-Sources-LillistCore-misc]
generator: cartographer/1
baseline: 34dfea7772679dbabc08fabd6fbba53f6ad5856b
---

# Module: Packages/LillistCore/Sources/LillistCore/Stores (chunk 2)

## Purpose

`TaskStore` is the single async gateway for every mutation and query of the
`LillistTask` Core Data graph. It exists to keep `NSManagedObject` from leaking:
callers only ever see the value-type `TaskRecord` DTO. Every public method runs
its work inside `context.perform`, saves-or-rolls-back atomically, then (outside
the perform block) reconciles notifications and emits breadcrumb/diagnostic
side-channels. The fractional-position reorder logic and its self-healing
recompaction are the load-bearing heart of the file.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `TaskStore` | class | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:18` | The task data gateway; `@unchecked Sendable`, one per `PersistenceController` |
| `TaskStore.TaskRecord` | struct | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:71` | Sendable value DTO returned by all reads; never an `NSManagedObject` |
| `TaskStore.TaskDraft` | struct | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:130` | Mutable view handed to the `update` closure |
| `TaskStore.archive(ids:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:632` | Stamps `archivedAt`; returns only the IDs actually flipped |
| `TaskStore.assignTag(taskID:tagID:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:829` | Idempotently adds a `Tag` to a task |
| `TaskStore.children(of:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:262` | Non-trashed children in position/createdAt order |
| `TaskStore.children(of:limit:offset:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:284` | Paged children; `limit <= 0` means no limit |
| `NewTaskPlacement` | enum | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:13` | `.top` (insert before first sibling) / `.bottom` (append after last); default `.bottom` |
| `TaskStore.create(title:notes:parent:placement:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:143` | Validates title, assigns next position (top/bottom via `NewTaskPlacement`), returns new UUID |
| `TaskStore.fetch(id:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:196` | Single record; throws `notFound` if absent |
| `TaskStore.hardDelete(id:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:245` | Permanently removes one task (Core Data cascade) |
| `TaskStore.init(persistence:)` | init | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:66` | Sole initializer; scheduler/sinks are property-injected |
| `TaskStore.normalizeSiblingsIfDegenerate(ofParent:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:967` | Compacts a sibling set only if positions are tied/inverted |
| `TaskStore.purgeAll()` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:734` | Hard-deletes all trashed tasks + descendants; returns count |
| `TaskStore.reorder(id:after:before:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:360` | Places a task between anchors; heals ties/underflow |
| `TaskStore.reparent(id:newParent:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:314` | Moves a task under a new parent; rejects cycles |
| `TaskStore.restore(id:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:698` | Clears soft-delete matching the original `deletedAt` |
| `TaskStore.softDelete(id:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:679` | Stamps `deletedAt` on the task and its children |
| `TaskStore.tagIDs(forTask:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:861` | Tag UUIDs attached to a task |
| `TaskStore.transition(id:to:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:533` | Changes status, logs a journal entry, spawns recurrence on close |
| `TaskStore.trashed()` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:717` | All soft-deleted records, newest-deleted first |
| `TaskStore.unarchive(ids:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:658` | Clears `archivedAt`; idempotent |
| `TaskStore.unassignTag(taskID:tagID:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:846` | Removes a `Tag` from a task |
| `TaskStore.update(id:_:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:205` | Applies a draft mutation, validates, reconciles notifications |
| `TaskStore.breadcrumbs` | property | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:34` | Optional crumb sink; mutations record verb-only entries |
| `TaskStore.diagnosticLog` | property | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:40` | Optional structured diagnostic sink |
| `TaskStore.isCommittableTitle(_:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:1004` | `nonisolated static`; sync-safe empty-title check for SwiftUI disabled states |
| `TaskStore.notificationScheduler` | property | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:29` | Property-injected reconciler; nil disables reconcile calls |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `fetchManagedObject(id:in:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:879` | The one id→`LillistTask` lookup every mutation calls; throws `notFound` |
| `record(from:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:1016` | The single `LillistTask`→`TaskRecord` projection enforcing the DTO boundary |
| `childrenFetchRequest(parentID:in:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:298` | Shared paged fetch builder; sets `fetchBatchSize` so reloads fault lazily |
| `nextPositionDetail(forParent:placement:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:903` | Computes next position: `edge + 1.0` for `.bottom`, `edge - 1.0` for `.top`; basis of `create`/`reparent` ordering |
| `recompactSiblings(ofParent:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:939` | Re-spaces siblings to integer gaps in canonical `SiblingOrder` during heals |
| `batchPurge(predicateFormat:arguments:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:766` | Background-context batch delete behind `purgeAll`; rebuilds predicate to stay Sendable |
| `applySoftDelete(to:at:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:807` | Recursive soft-delete down the child tree |
| `ReorderCapture` | class | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:511` | Carries anchor/computed positions out of `perform` for diagnostics |
| `emitReorderDiag(...)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:518` | Emits the reorder RCA payload on both success and throw paths |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceController (reads)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.LillistTask (owns)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.JournalEntry (writes)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.Tag (reads)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore -> Packages-LillistCore-Sources-LillistCore-Ordering.FractionalPosition (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore -> Packages-LillistCore-Sources-LillistCore-Ordering.PositionCompactor (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore -> Packages-LillistCore-Sources-LillistCore-Ordering.SiblingOrder (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore -> Packages-LillistCore-Sources-LillistCore-Persistence.CascadeReaper (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore -> Packages-LillistCore-Sources-LillistCore-Recurrence.RecurrenceSpawner (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore -> Packages-LillistCore-Sources-LillistCore-misc.Validators (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore -> Packages-LillistCore-Sources-LillistCore-misc.LillistError (emits)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore -> Packages-LillistCore-Sources-LillistCore-Model.Status (reads)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore -> Packages-LillistCore-Sources-LillistCore-Notifications.NotificationReconciling (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore -> Packages-LillistCore-Sources-LillistCore-CrashReporting.BreadcrumbBuffer (writes)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore -> Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticSink (emits)`

## Type notes

`TaskStore` is a `final class` marked `@unchecked Sendable`; all Core Data work
is funneled through `context.perform` on the main-queue `viewContext`
(`Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:20`). Side-channel
calls (`recordCrumb`, `emitDiag`, `scheduler.reconcile`) run *outside* the
perform block, after the `await` completes. `ReorderCapture` and
`TransitionCapture` are `@unchecked Sendable` carriers written on the context
queue and read only after the await — a happens-after barrier guarantees no
concurrent access (`Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:510`).
The DTO invariant — no `NSManagedObject` escapes — is enforced solely by
`record(from:)`. `scheduler`/`breadcrumbs`/`diagnosticLog` are property-injected
(nil by default) so the many `TaskStore(persistence:)` test call sites need no
change. `restore` only un-deletes children whose `deletedAt` matches the parent's
original stamp, so an independently-trashed child stays trashed
(`Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:817`).
`NewTaskPlacement` (a top-level `public enum`) controls where `create` places a new task within
its sibling group: `.bottom` appends with `edge + 1.0` (historical default, used for subtasks and
import); `.top` inserts with `edge - 1.0` so a just-captured task appears at the head of the list.
The default is `.bottom` for backward compatibility with all existing `create` call sites.

## External deps

- CoreData — `NSManagedObjectContext`, `NSFetchRequest`, `NSPredicate`, `NSBatchDeleteRequest`
- Foundation — `UUID`, `Date`, `JSONSerialization`
- os — `OSSignposter` intervals around the `children` fetch

## Gotchas

- Reorder tie-healing swaps anchor positions to honour drag intent when canonical UUID order conflicts with the caller's after/before; see `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:449`.
- After recompaction, `reorder` uses `afterTask.position + 0.5` (not the midpoint) to avoid collision with integer sibling positions; see `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:462`.
- `batchPurge` rebuilds `NSPredicate` inside the `@Sendable` background-context closure because `NSPredicate` is not `Sendable`; see `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:773`.
