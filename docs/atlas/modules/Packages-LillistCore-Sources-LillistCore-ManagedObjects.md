---
module: Packages/LillistCore/Sources/LillistCore/ManagedObjects
summary: Hand-written @NSManaged subclasses — the private Core Data row types that stores read/write and DTOs are projected from
read_when: Touching Core Data entity shape, adding attributes, or tracing store-layer NSManagedObject access
sources:
  - path: Packages/LillistCore/Sources/LillistCore/ManagedObjects/AppPreferences+CoreData.swift
  - path: Packages/LillistCore/Sources/LillistCore/ManagedObjects/Attachment+CoreData.swift
  - path: Packages/LillistCore/Sources/LillistCore/ManagedObjects/JournalEntry+CoreData.swift
  - path: Packages/LillistCore/Sources/LillistCore/ManagedObjects/LillistTask+CoreData.swift
  - path: Packages/LillistCore/Sources/LillistCore/ManagedObjects/NotificationSpec+CoreData.swift
  - path: Packages/LillistCore/Sources/LillistCore/ManagedObjects/Series+CoreData.swift
  - path: Packages/LillistCore/Sources/LillistCore/ManagedObjects/SmartFilter+CoreData.swift
  - path: Packages/LillistCore/Sources/LillistCore/ManagedObjects/Tag+CoreData.swift
references_modules:
  - Packages-LillistCore-Sources-LillistCore-Model
  - Packages-LillistCore-Sources-LillistCore-Recurrence
generator: cartographer/1 model=claude-sonnet-4-6
---

# Module: Packages/LillistCore/Sources/LillistCore/ManagedObjects

## Purpose

Hand-written `@objc(...) public final class ...: NSManagedObject` subclasses, one per Core Data entity, deliberately replacing Core Data's auto-generated codegen (a project house rule). Each file declares the entity's `@NSManaged` stored columns plus an extension exposing typed Swift accessors over raw-stored scalars (`statusRaw -> Status`, `kindRaw -> AttachmentKind`, JSON-stored `ruleJSON -> RecurrenceRule`). These classes are the runtime backing for the `.xcdatamodel` entity descriptions; without them every fetch would return an untyped `NSManagedObject` and the stores could not map rows to DTOs. They never escape `LillistCore` — stores convert them to value-type records before any caller sees them.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AppPreferences` | class | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/AppPreferences+CoreData.swift:5` | Singleton-row settings entity; `defaultTaskListSort` typed over `defaultTaskListSortRaw` |
| `Attachment` | class | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/Attachment+CoreData.swift:5` | File/link blob; `kind` typed over `kindRaw`; belongs to a task or journal entry |
| `JournalEntry` | class | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/JournalEntry+CoreData.swift:5` | Note/log row on a task; `kind` typed over `kindRaw`; owns attachments |
| `LillistTask` | class | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/LillistTask+CoreData.swift:5` | Central task entity; `status` typed over `statusRaw`; hub of all relationships |
| `NotificationSpec` | class | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/NotificationSpec+CoreData.swift:5` | Per-task reminder rule; `kind` typed over `kindRaw` |
| `Series` | class | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/Series+CoreData.swift:5` | Recurrence series; `rule` decodes `ruleJSON` to `RecurrenceRule` |
| `SmartFilter` | class | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/SmartFilter+CoreData.swift:5` | Saved predicate view; `sortField` typed over `sortFieldRaw` |
| `Tag` | class | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/Tag+CoreData.swift:5` | Hierarchical label; `root`/`descendants` walk the parent/children tree |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `LillistTask.status` | computed var | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/LillistTask+CoreData.swift:84` | The canonical raw-to-`Status` bridge every task query funnels through |
| `Series.rule` | computed var | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/Series+CoreData.swift:31` | JSON round-trip; returns `nil` on missing/malformed data (corruption signal) |
| `Tag.descendants` | computed var | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/Tag+CoreData.swift:41` | Depth-first subtree walk powering tag-hierarchy filtering |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-ManagedObjects.LillistTask -> Packages-LillistCore-Sources-LillistCore-Model.Status (reads)`
- `Packages-LillistCore-Sources-LillistCore-ManagedObjects.SmartFilter -> Packages-LillistCore-Sources-LillistCore-Model.SortField (reads)`
- `Packages-LillistCore-Sources-LillistCore-ManagedObjects.AppPreferences -> Packages-LillistCore-Sources-LillistCore-Model.SortField (reads)`
- `Packages-LillistCore-Sources-LillistCore-ManagedObjects.Attachment -> Packages-LillistCore-Sources-LillistCore-Model.AttachmentKind (reads)`
- `Packages-LillistCore-Sources-LillistCore-ManagedObjects.JournalEntry -> Packages-LillistCore-Sources-LillistCore-Model.JournalEntryKind (reads)`
- `Packages-LillistCore-Sources-LillistCore-ManagedObjects.NotificationSpec -> Packages-LillistCore-Sources-LillistCore-Model.NotificationKind (reads)`
- `Packages-LillistCore-Sources-LillistCore-ManagedObjects.Series -> Packages-LillistCore-Sources-LillistCore-Recurrence.RecurrenceRule (reads)`

## Type notes

All entities are `@objc(...) public final class ... : NSManagedObject`; the `@objc` name matches the `representedClassName` in the `.xcdatamodeld` contents, binding each subclass to its entity. Stored scalars use raw forms (`*Raw: Int16`, `*JSON: String?`); the extension accessors are the only sanctioned way to read typed values, and they always supply a fallback so a missing/unknown raw never crashes (`LillistTask.status` defaults to `.todo`, `Packages/LillistCore/Sources/LillistCore/ManagedObjects/LillistTask+CoreData.swift:85`). `Series.rule` is the exception that returns `nil` rather than a default, so a `nil` is a data-corruption signal, not an empty state (`Packages/LillistCore/Sources/LillistCore/ManagedObjects/Series+CoreData.swift:29`).

To-many relationships are exposed as `NSSet?` plus generated `addTo*`/`removeFrom*` mutators (e.g. `Packages/LillistCore/Sources/LillistCore/ManagedObjects/LillistTask+CoreData.swift:33`). `LillistTask` is the relationship hub: `parent`/`children` (self-referential subtask tree), `tags`, `journalEntries`, `attachments`, `notificationSpecs`, and the dual `series`/`seriesAsSeed` links to `Series`. `Attachment` may belong to either a `LillistTask` or a `JournalEntry` but not both — enforced by store logic, not by schema constraint (`Packages/LillistCore/Sources/LillistCore/ManagedObjects/Attachment+CoreData.swift:15`). Instances are managed-object-context bound and not `Sendable` — they must never cross actor boundaries.

## External deps

- CoreData — `NSManagedObject` base class, `@NSManaged` property/relationship accessors
- Foundation — `UUID`, `Date`, `Data`, `JSONEncoder`/`JSONDecoder` for `Series.rule`

## Gotchas

- `Series.rule` returns `nil` for missing or malformed JSON — callers must treat nil as a data-corruption signal, not empty state; see comment at `Packages/LillistCore/Sources/LillistCore/ManagedObjects/Series+CoreData.swift:29`.
- `LillistTask.children` and `Tag.children` are `NSSet?` — callers must cast to `Set<LillistTask>` or `Set<Tag>` before iterating; `Tag.descendants` demonstrates the safe cast at `Packages/LillistCore/Sources/LillistCore/ManagedObjects/Tag+CoreData.swift:42`.
