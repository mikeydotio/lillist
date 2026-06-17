---
module: "Packages/LillistCore/Sources/LillistCore/Stores (chunk 1)"
summary: "Core Data facades for attachments, journal, preferences, series, smart filters, tags, plus TaskStore query/follow-up extensions"
read_when: "Touching attachments, journal, preferences, recurrence series, smart filters, or tags"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift
  - path: Packages/LillistCore/Sources/LillistCore/Stores/JournalStore.swift
  - path: Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift
  - path: Packages/LillistCore/Sources/LillistCore/Stores/SeriesStore.swift
  - path: "Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore+Defaults.swift"
  - path: Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift
  - path: "Packages/LillistCore/Sources/LillistCore/Stores/TagStore+FindOrCreate.swift"
  - path: Packages/LillistCore/Sources/LillistCore/Stores/TagStore.swift
  - path: "Packages/LillistCore/Sources/LillistCore/Stores/TaskStore+FollowUp.swift"
  - path: "Packages/LillistCore/Sources/LillistCore/Stores/TaskStore+Queries.swift"
references_modules: [Packages-LillistCore-Sources-LillistCore-Persistence, Packages-LillistCore-Sources-LillistCore-ManagedObjects, Packages-LillistCore-Sources-LillistCore-Rules, Packages-LillistCore-Sources-LillistCore-Ordering, Packages-LillistCore-Sources-LillistCore-Recurrence, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistCore-Sources-LillistCore-CrashReporting, Packages-LillistCore-Sources-LillistCore-Diagnostics, Packages-LillistCore-Sources-LillistCore-Notifications, Packages-LillistCore-Sources-LillistCore-misc]
generator: cartographer/1
---

# Module: Packages/LillistCore/Sources/LillistCore/Stores (chunk 1)

## Purpose

The persistence facades for everything except the core task entity: attachments, journal
entries, app preferences, recurring series, saved smart filters, and tags. Each store wraps a
shared `PersistenceController`, runs all Core Data work inside `viewContext.perform`, and returns
value-type `*Record` DTOs so no `NSManagedObject` escapes the module (the project's hard rule).
This chunk also holds three extensions on `TaskStore` (whose base class is in chunk 2):
follow-up creation, and the pinned/by-tag/breadcrumb query surface that backs the sidebar and
flat list views.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AttachmentStore` | class | `Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift:4` | Image/file/link-preview attachment CRUD; each insert also mints a paired attachment `JournalEntry` |
| `AttachmentStore.AttachmentRecord` | struct | `Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift:24` | Value-type attachment DTO; `hasData` reflects whether bytes are local |
| `AttachmentStore.attachments(forTask:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift:177` | All attachments for a task, createdAt-ascending |
| `AttachmentStore.downloadData(id:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift:165` | Forces CloudKit asset materialization; throws `attachmentFetchFailed` when no bytes |
| `AttachmentStore.hardSizeLimit` | static let | `Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift:9` | 500 MB ceiling; larger inserts throw `attachmentTooLarge` |
| `AttachmentStore.updateLinkPreview(id:metadata:thumbnailData:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift:109` | Merges unfurled OG metadata into an existing link-preview row |
| `JournalStore` | class | `Packages/LillistCore/Sources/LillistCore/Stores/JournalStore.swift:4` | Journal entry append/read/edit/delete; system entries are non-editable |
| `JournalStore.JournalRecord` | struct | `Packages/LillistCore/Sources/LillistCore/Stores/JournalStore.swift:21` | Value-type journal DTO |
| `JournalStore.appendNote(taskID:body:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/JournalStore.swift:34` | Appends a `.note` entry to a task; returns its id |
| `JournalStore.entries(forTask:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/JournalStore.swift:64` | All entries for a task, createdAt-ascending |
| `PreferencesStore` | class | `Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift:4` | Single-row app settings; broadcasts changes via `prefsStream` |
| `PreferencesStore.Prefs` | struct | `Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift:51` | Value snapshot of all app preference fields |
| `PreferencesStore.prefsStream` | var | `Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift:140` | Per-caller `AsyncStream`; emits on every update and remote change |
| `PreferencesStore.read()` | func | `Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift:74` | Reads the singleton row, creating defaults if absent |
| `PreferencesStore.singletonID` | static let | `Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift:14` | Fixed UUID for the one prefs row; never regenerate it |
| `PreferencesStore.update(_:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift:95` | Mutates prefs via closure, saves, then broadcasts |
| `PreferencesStore.normalizeSingletons()` | func | `Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift:231` | Bootstrap convergence pass collapsing duplicate prefs rows to one canonical row |
| `SeriesStore` | class | `Packages/LillistCore/Sources/LillistCore/Stores/SeriesStore.swift:4` | Recurring-series CRUD; computes `nextOccurrenceAfter` on create/update/fork |
| `SeriesStore.SeriesRecord` | struct | `Packages/LillistCore/Sources/LillistCore/Stores/SeriesStore.swift:13` | Value-type series DTO |
| `SeriesStore.create(fromSeedTask:rule:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SeriesStore.swift:23` | Roots a series on a seed task and a `RecurrenceRule` |
| `SeriesStore.forkFutureFromInstance(instanceID:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SeriesStore.swift:94` | Edit-all-future: re-roots a new series at an instance, leaving the old intact |
| `SmartFilterStore` | class | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:7` | Saved smart filters; serializes `PredicateGroup` to JSON at `predicateGroupJSON` |
| `SmartFilterStore.SmartFilterRecord` | struct | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:27` | Value-type filter DTO with explicit public init |
| `SmartFilterStore.evaluate(id:now:calendar:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:437` | Runs a saved filter, returns sorted `TaskStore.TaskRecord`s |
| `SmartFilterStore.evaluate(group:sort:ascending:now:calendar:includeArchived:limit:offset:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:469` | Runs an ad-hoc `PredicateGroup` with limit/offset/archived options |
| `SmartFilterStore.count(id:now:calendar:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:497` | Counts matching tasks without materializing records; used for badge counts |
| `SmartFilterStore.installDefaultsIfNeeded()` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore+Defaults.swift:11` | Idempotently installs the five default filters by name |
| `SmartFilterStore.reorder(id:after:before:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:334` | Heal-then-recheck fractional reorder; emits `filter.reorder` diag |
| `TagStore` | class | `Packages/LillistCore/Sources/LillistCore/Stores/TagStore.swift:4` | Hierarchical tag CRUD; enforces sibling-name uniqueness and cycle-free reparenting |
| `TagStore.TagRecord` | struct | `Packages/LillistCore/Sources/LillistCore/Stores/TagStore.swift:21` | Value-type tag DTO |
| `TagStore.children(of:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TagStore.swift:64` | Direct children of a parent (or roots when nil), position-ordered |
| `TagStore.findOrCreate(name:parent:tintColor:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TagStore+FindOrCreate.swift:14` | Atomic case-insensitive lookup-or-insert under a parent |
| `TagStore.reparent(id:newParent:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TagStore.swift:99` | Moves a tag; rejects cycles, re-uniquifies the name under the new parent |
| `TaskStore.breadcrumbs(for:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore+Queries.swift:74` | Parent-title trail per task id for flat list rows |
| `TaskStore.pinned()` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore+Queries.swift:10` | Non-deleted pinned tasks across the tree, position-ordered |
| `TaskStore.scheduleFollowUp(parentTaskID:title:deadline:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore+FollowUp.swift:16` | Creates a sibling follow-up + parent journal entry; reconciles notifications |
| `TaskStore.tasks(forTag:includeDescendants:sort:ascending:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore+Queries.swift:28` | De-duped non-trash tasks for a tag and optionally its descendants |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `SmartFilterStore.record(from:)` | static func | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:529` | Sole `LillistTask` → `TaskStore.TaskRecord` projection used by all evaluate/count paths |
| `SmartFilterStore.sortDescriptors(field:ascending:)` | static func | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:510` | Maps `SortField` to NSSortDescriptors; reused by `TaskStore.tasks(forTag:)` |
| `DefaultSmartFilters` | enum | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore+Defaults.swift:27` | Declares the five seed filters (Today/This Week/No Tags/Recently Closed/Stale) |
| `SeriesStore.computeNextOccurrence(rule:after:)` | static func | `Packages/LillistCore/Sources/LillistCore/Stores/SeriesStore.swift:138` | Single point where series schedule advances via `RecurrenceExpander` |
| `PreferencesStore.fetchOrCreateSingleton(in:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift:185` | Canonical-id-first lookup with legacy-row adoption; defines all default values |
| `TagStore.uniqueNameUnder(parent:desired:excluding:)` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TagStore.swift:174` | Enforces sibling-name uniqueness on create/rename/reparent via `Validators` |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.AttachmentStore -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceController (owns)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.AttachmentStore -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.Attachment (reads)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.AttachmentStore -> Packages-LillistCore-Sources-LillistCore-CrashReporting.BreadcrumbBuffer (writes)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.AttachmentStore -> Packages-LillistCore-Sources-LillistCore-misc.LillistError (emits)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.JournalStore -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.JournalEntry (reads)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.PreferencesStore -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.AppPreferences (reads)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SeriesStore -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SeriesStore -> Packages-LillistCore-Sources-LillistCore-Recurrence.RecurrenceExpander (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SeriesStore -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.Series (reads)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SmartFilterStore -> Packages-LillistCore-Sources-LillistCore-Rules.NSPredicateCompiler (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SmartFilterStore -> Packages-LillistCore-Sources-LillistCore-Ordering.FractionalPosition (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SmartFilterStore -> Packages-LillistCore-Sources-LillistCore-Ordering.PositionCompactor (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SmartFilterStore -> Packages-LillistCore-Sources-LillistCore-Ordering.SiblingOrder (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SmartFilterStore -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (reads)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SmartFilterStore -> Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticEvent (emits)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TagStore -> Packages-LillistCore-Sources-LillistCore-misc.Validators (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TagStore -> Packages-LillistCore-Sources-LillistCore-Ordering.FractionalPosition (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TagStore -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.Tag (reads)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TaskStore -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (extends)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TaskStore -> Packages-LillistCore-Sources-LillistCore-Notifications.NotificationScheduler (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TaskStore -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.LillistTask (reads)`

## Type notes

Every store is a `final class … @unchecked Sendable` that holds the shared `PersistenceController`
and does all work inside `context.perform`; the `@unchecked` is justified because mutable state is
either confined to that serialized context or guarded by a lock. `PreferencesStore` registers an
`NSPersistentStoreRemoteChange` observer in `init` and removes it in `deinit`; its `prefsStream`
continuation registry is guarded by `NSLock` (`continuationsLock`) rather than an actor
(`Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift:19`). The
`AppPreferences` singleton invariant — exactly one row carrying `singletonID` — is established by
`fetchOrCreateSingleton` and reconciled by `normalizeSingletons`
(`Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift:14`). Series ownership is
bidirectional: a `Series` references its `seedTask` and each member `LillistTask.series` points
back (`Packages/LillistCore/Sources/LillistCore/Stores/SeriesStore.swift:30`). `SeriesStore` and
the `TaskStore` extensions instantiate a throwaway `TaskStore(persistence:)` to reach the base
class's internal `fetchManagedObject`/`nextPosition`/`validateTitle` helpers (defined in chunk 2).

## External deps

- CoreData — `NSManagedObjectContext.perform`, `NSFetchRequest`, `NSPredicate`, CloudKit asset materialization
- Foundation — `JSONEncoder`/`JSONDecoder` for predicate-group and link-preview JSON, `NSLock`, `NotificationCenter`

## Gotchas

- `PreferencesStore.singletonID` is a fixed UUID literal; regenerating it duplicates the CloudKit prefs record (`Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift:5`).
- SmartFilter rows sort in Swift via `SiblingOrder.precedes`, not a secondary descriptor — Core Data orders UUID bytes, not `uuidString` lexical order (`Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:222`).
- `installDefaultsIfNeeded` matches by name and never overwrites user edits to an existing default filter (`Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore+Defaults.swift:7`).
- Follow-ups are created as siblings, not children, so collapsing the blocked task doesn't hide them (`Packages/LillistCore/Sources/LillistCore/Stores/TaskStore+FollowUp.swift:5`).
- System journal entries (non-`isUserEditable` kinds) reject edit and delete (`Packages/LillistCore/Sources/LillistCore/Stores/JournalStore.swift:78`).
- `SeriesStore.fetchManagedObject` is `internal` (not `private`) so `RecurrenceSpawner` in the Recurrence module can call it without going through the public API (`Packages/LillistCore/Sources/LillistCore/Stores/SeriesStore.swift:128`).
