---
module: Packages/LillistCore/Sources/LillistCore/ManagedObjects
summary: "Hand-written @NSManaged Core Data subclasses backing every Lillist entity"
read_when: Core Data entity classes
sources:
  - path: "Packages/LillistCore/Sources/LillistCore/ManagedObjects/AppPreferences+CoreData.swift"
    blob: 45b2c0207922cc1482ecc9454154885f40d6b504
  - path: "Packages/LillistCore/Sources/LillistCore/ManagedObjects/Attachment+CoreData.swift"
    blob: f9c9ef801251fb7cf32a3cf91c777614bb04ffe6
  - path: "Packages/LillistCore/Sources/LillistCore/ManagedObjects/JournalEntry+CoreData.swift"
    blob: 2f5063ad7f2bcad77405aeb1331a14e7715b07d7
  - path: "Packages/LillistCore/Sources/LillistCore/ManagedObjects/LillistTask+CoreData.swift"
    blob: cefeac967fc046c6d5551fdb48501d970c2afb30
  - path: "Packages/LillistCore/Sources/LillistCore/ManagedObjects/NotificationSpec+CoreData.swift"
    blob: 0d3763da50f713f1f1928b03adec02d8d92b5eb5
  - path: "Packages/LillistCore/Sources/LillistCore/ManagedObjects/Series+CoreData.swift"
    blob: 5571ecb640c8eac0151caf139ba25ac8379f14e4
  - path: "Packages/LillistCore/Sources/LillistCore/ManagedObjects/SmartFilter+CoreData.swift"
    blob: a742d4be2470d4706931d2cb182777f1b3f7bae2
  - path: "Packages/LillistCore/Sources/LillistCore/ManagedObjects/Tag+CoreData.swift"
    blob: 2bdf18d272d768aaeed043a1f3714df7d148a25b
references_modules: [Packages-LillistCore-Sources-LillistCore-Model, Packages-LillistCore-Sources-LillistCore-Recurrence, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
---

# Module: Packages/LillistCore/Sources/LillistCore/ManagedObjects

## Purpose

Hand-written `@objc(...) public final class ...: NSManagedObject` subclasses, one
per Core Data entity, deliberately replacing Core Data's auto-generated codegen
(a project house rule). Each file declares the entity's `@NSManaged` stored
columns plus an extension exposing typed Swift accessors over raw-stored scalars
(`statusRaw -> Status`, `kindRaw -> AttachmentKind`, JSON-stored
`ruleJSON -> RecurrenceRule`). These classes are the runtime backing for the
`.xcdatamodel` entity descriptions; without them every fetch would return an
untyped `NSManagedObject` and the stores could not map rows to DTOs. They never
escape `LillistCore` — stores convert them to value-type records before any
caller sees them.

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
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TaskStore -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.LillistTask (writes)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.SeriesStore -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.Series (writes)`

## Type notes

All entities are `@objc(...) public final class ... : NSManagedObject`; the
`@objc` name matches the `representedClassName` in
`Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/LillistModel.xcdatamodel/contents`,
binding each subclass to its entity. Stored scalars use raw forms (`*Raw: Int16`,
`*JSON: String?`); the extension accessors are the only sanctioned way to read
typed values, and they always supply a fallback so a missing/unknown raw never
crashes (`LillistTask.status` defaults to `.todo`,
`Packages/LillistCore/Sources/LillistCore/ManagedObjects/LillistTask+CoreData.swift:85`).
`Series.rule` is the exception that returns `nil` rather than a default, so a
`nil` is a data-corruption signal, not an empty state
(`Packages/LillistCore/Sources/LillistCore/ManagedObjects/Series+CoreData.swift:29`).
To-many relationships are exposed as `NSSet?` plus generated `addTo*`/`removeFrom*`
mutators (e.g. `Packages/LillistCore/Sources/LillistCore/ManagedObjects/LillistTask+CoreData.swift:33`).
`LillistTask` is the relationship hub: `parent`/`children` (self-referential),
`tags`, `journalEntries`, `attachments`, `notificationSpecs`, and the dual
`series`/`seriesAsSeed` links to `Series`. Instances are managed-object-context
bound and not `Sendable` — they are confined to their context's queue and must
never cross actor boundaries.

## External deps

- CoreData — `NSManagedObject` base class, `@NSManaged` property/relationship accessors
- Foundation — `UUID`, `Date`, `Data`, `JSONEncoder`/`JSONDecoder` for `Series.rule`
