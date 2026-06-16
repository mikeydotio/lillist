---
module: "Packages/LillistCore/Sources/LillistCore/Stores (chunk 2)"
summary: "TaskStore — the async CRUD/hierarchy/reorder/status gateway over the LillistTask Core Data graph"
read_when: TaskStore CRUD/reorder
sources:
  - path: Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift
    blob: 31713a7791397c8cb2de171f3b097900da664826
references_modules: [Packages-LillistCore-Sources-LillistCore-Persistence, Packages-LillistCore-Sources-LillistCore-Ordering, Packages-LillistCore-Sources-LillistCore-Recurrence, Packages-LillistCore-Sources-LillistCore-Notifications, Packages-LillistCore-Sources-LillistCore-CrashReporting, Packages-LillistCore-Sources-LillistCore-Diagnostics, Packages-LillistCore-Sources-LillistCore-ManagedObjects, Packages-LillistCore-Sources-LillistCore-Model, Packages-LillistCore-Sources-LillistCore-misc]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
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
| `TaskStore` | class | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:5` | The task data gateway; `@unchecked Sendable`, one per `PersistenceController` |
| `TaskStore.TaskRecord` | struct | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:58` | Sendable value DTO returned by all reads; never an `NSManagedObject` |
| `TaskStore.TaskDraft` | struct | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:117` | Mutable view handed to the `update` closure |
| `TaskStore.archive(ids:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:618` | Stamps `archivedAt`; returns only the IDs actually flipped |
| `TaskStore.assignTag(taskID:tagID:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:815` | Idempotently adds a `Tag` to a task |
| `TaskStore.children(of:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:248` | Non-trashed children in position/createdAt order |
| `TaskStore.children(of:limit:offset:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:270` | Paged children; `limit <= 0` means no limit |
| `TaskStore.create(title:notes:parent:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:130` | Validates title, assigns next position, returns new UUID |
| `TaskStore.fetch(id:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:182` | Single record; throws `notFound` if absent |
| `TaskStore.hardDelete(id:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:231` | Permanently removes one task (Core Data cascade) |
| `TaskStore.init(persistence:)` | init | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:53` | Sole initializer; scheduler/sinks are property-injected |
| `TaskStore.normalizeSiblingsIfDegenerate(ofParent:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:936` | Compacts a sibling set only if positions are tied/inverted |
| `TaskStore.purgeAll()` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:720` | Hard-deletes all trashed tasks + descendants; returns count |
| `TaskStore.reorder(id:after:before:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:346` | Places a task between anchors; heals ties/underflow |
| `TaskStore.reparent(id:newParent:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:300` | Moves a task under a new parent; rejects cycles |
| `TaskStore.restore(id:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:684` | Clears soft-delete matching the original `deletedAt` |
| `TaskStore.softDelete(id:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:665` | Stamps `deletedAt` on the task and its children |
| `TaskStore.tagIDs(forTask:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:847` | Tag UUIDs attached to a task |
| `TaskStore.transition(id:to:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:519` | Changes status, logs a journal entry, spawns recurrence on close |
| `TaskStore.trashed()` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:703` | All soft-deleted records, newest-deleted first |
| `TaskStore.unarchive(ids:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:644` | Clears `archivedAt`; idempotent |
| `TaskStore.unassignTag(taskID:tagID:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:832` | Removes a `Tag` from a task |
| `TaskStore.update(id:_:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:191` | Applies a draft mutation, validates, reconciles notifications |
| `TaskStore.breadcrumbs` | property | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:21` | Optional crumb sink; mutations record verb-only entries |
| `TaskStore.diagnosticLog` | property | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:27` | Optional structured diagnostic sink |
| `TaskStore.notificationScheduler` | property | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:16` | Property-injected reconciler; nil disables reconcile calls |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `fetchManagedObject(id:in:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:865` | The one id→`LillistTask` lookup every mutation calls; throws `notFound` |
| `record(from:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:975` | The single `LillistTask`→`TaskRecord` projection enforcing the DTO boundary |
| `childrenFetchRequest(parentID:in:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:284` | Shared paged fetch builder; sets `fetchBatchSize` so reloads fault lazily |
| `nextPositionDetail(forParent:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:882` | Computes next position from observed max; basis of `create`/`reparent` ordering |
| `recompactSiblings(ofParent:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:908` | Re-spaces siblings to integer gaps in canonical `SiblingOrder` during heals |
| `batchPurge(predicateFormat:arguments:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:752` | Background-context batch delete behind `purgeAll`; rebuilds predicate to stay Sendable |
| `applySoftDelete(to:at:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:793` | Recursive soft-delete down the child tree |
| `ReorderCapture` | class | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:497` | Carries anchor/computed positions out of `perform` for diagnostics |
| `emitReorderDiag(...)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:504` | Emits the reorder RCA payload on both success and throw paths |

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
(`Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:7`). Side-channel
calls (`recordCrumb`, `emitDiag`, `scheduler.reconcile`) run *outside* the
perform block, after the `await` completes. `ReorderCapture` and
`TransitionCapture` are `@unchecked Sendable` carriers written on the context
queue and read only after the await — a happens-after barrier guarantees no
concurrent access (`Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:494`).
The DTO invariant — no `NSManagedObject` escapes — is enforced solely by
`record(from:)`. `scheduler`/`breadcrumbs`/`diagnosticLog` are property-injected
(nil by default) so the many `TaskStore(persistence:)` test call sites need no
change. `restore` only un-deletes children whose `deletedAt` matches the parent's
original stamp, so an independently-trashed child stays trashed
(`Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:803`).

## External deps

- CoreData — `NSManagedObjectContext`, `NSFetchRequest`, `NSPredicate`, `NSBatchDeleteRequest`
- Foundation — `UUID`, `Date`, `JSONSerialization`
- os — `OSSignposter` intervals around the `children` fetch
