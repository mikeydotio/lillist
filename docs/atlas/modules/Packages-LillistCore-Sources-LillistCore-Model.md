---
module: Packages/LillistCore/Sources/LillistCore/Model
summary: "Core Data schema (xcdatamodeld) and the persisted enums that type its raw integer/string columns"
read_when: "Touching Core Data entities, persisted enum raw values, or sort/status/notification semantics"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/Model/AttachmentKind.swift
    blob: 71c49cd3ddb11ee8616dfe2f26f48750b7f72d57
  - path: Packages/LillistCore/Sources/LillistCore/Model/JournalEntryKind.swift
    blob: 93d02c6c8bf56046428b4deeebcd3991b2e03bb5
  - path: Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/.xccurrentversion
    blob: 0b7ad51749d1fec30479832e5654dc4ab039a7bc
  - path: Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/LillistModel.xcdatamodel/contents
    blob: bf6557c0c1cfb21e7dc18cdad51d0fe20a7568ba
  - path: Packages/LillistCore/Sources/LillistCore/Model/NotificationKind.swift
    blob: 19eca0cca8609b9de59145cea207f200f95fbfad
  - path: Packages/LillistCore/Sources/LillistCore/Model/SortField.swift
    blob: 8813896cae4dfd955cc80e81553f4c68b1065893
  - path: Packages/LillistCore/Sources/LillistCore/Model/Status.swift
    blob: 2b474b3b3224e2f4963e5e230484a29ed438478e
references_modules: [Packages-LillistCore-Sources-LillistCore-ManagedObjects, Packages-LillistCore-Sources-LillistCore-Notifications, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistUI-Sources-LillistUI-misc, Packages-LillistUI-Sources-LillistUI-Settings]
generator: cartographer/1
baseline: 34dfea7772679dbabc08fabd6fbba53f6ad5856b
---

# Module: Packages/LillistCore/Sources/LillistCore/Model

## Purpose

This module is the schema layer for all persistent state: the single `LillistModel.xcdatamodeld`
defines every Core Data entity, and the five Swift enums provide the typed view over the raw
integer and string columns that Core Data stores. Nothing here contains business logic; the
module's sole invariant is raw-value stability — every `*Raw` column in the schema is
bridged to one of these enums by a typed accessor in `ManagedObjects/`. If this module
vanished, typed accessors throughout ManagedObjects and every store query that filters or
sorts by status would lose their shared type definitions.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AttachmentKind` | enum | `Packages/LillistCore/Sources/LillistCore/Model/AttachmentKind.swift:3` | Typed over `Attachment.kindRaw` (Int16); cases: `image=0`, `file=1`, `linkPreview=2`; raw values persisted |
| `JournalEntryKind` | enum | `Packages/LillistCore/Sources/LillistCore/Model/JournalEntryKind.swift:3` | Typed over `JournalEntry.kindRaw` (Int16); `isUserEditable` gates edit permission at model layer |
| `JournalEntryKind.isUserEditable` | property | `Packages/LillistCore/Sources/LillistCore/Model/JournalEntryKind.swift:11` | `false` for system-managed entries (`statusChange`, `createdFollowUp`); `true` for `note` and `attachment` |
| `NotificationKind` | enum | `Packages/LillistCore/Sources/LillistCore/Model/NotificationKind.swift:8` | Typed over `NotificationSpec.kindRaw` (Int16); encodes four-layer delivery model; raw values persisted |
| `NotificationKind.Anchor` | enum | `Packages/LillistCore/Sources/LillistCore/Model/NotificationKind.swift:22` | `.start` / `.deadline`; `nil` for `.nudge` kinds that carry their own absolute `fireDate` |
| `NotificationKind.anchor` | property | `Packages/LillistCore/Sources/LillistCore/Model/NotificationKind.swift:27` | Returns the task field a `NotificationKind` is anchored to, or `nil` for `.nudge` |
| `NotificationKind.isOffset` | property | `Packages/LillistCore/Sources/LillistCore/Model/NotificationKind.swift:35` | `true` for Layer-3 user-added offset kinds (`offsetStart`, `offsetDeadline`) |
| `SortField` | enum | `Packages/LillistCore/Sources/LillistCore/Model/SortField.swift:9` | Typed over `SmartFilter.sortFieldRaw` (String); `manualPosition` invalid across parent boundaries |
| `Status` | enum | `Packages/LillistCore/Sources/LillistCore/Model/Status.swift:7` | Typed over `LillistTask.statusRaw` (Int16); `isClosed` identifies terminal state; raw values persisted |
| `Status.isClosed` | property | `Packages/LillistCore/Sources/LillistCore/Model/Status.swift:14` | `true` only for the terminal `.closed` state |

## Load-bearing internals

No internal symbols. Every declaration in this module is public.

## Relationships

- `Packages-LillistCore-Sources-LillistCore-Model.Status -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.LillistTask+CoreData (reads)` — `statusRaw` bridged at `Packages/LillistCore/Sources/LillistCore/ManagedObjects/LillistTask+CoreData.swift:85`
- `Packages-LillistCore-Sources-LillistCore-Model.JournalEntryKind -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.JournalEntry+CoreData (reads)` — `kindRaw` bridged at `Packages/LillistCore/Sources/LillistCore/ManagedObjects/JournalEntry+CoreData.swift:27`
- `Packages-LillistCore-Sources-LillistCore-Model.AttachmentKind -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.Attachment+CoreData (reads)` — `kindRaw` bridged at `Packages/LillistCore/Sources/LillistCore/ManagedObjects/Attachment+CoreData.swift:21`
- `Packages-LillistCore-Sources-LillistCore-Model.NotificationKind -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.NotificationSpec+CoreData (reads)` — `kindRaw` bridged at `Packages/LillistCore/Sources/LillistCore/ManagedObjects/NotificationSpec+CoreData.swift:20`
- `Packages-LillistCore-Sources-LillistCore-Model.SortField -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.SmartFilter+CoreData (reads)` — `sortFieldRaw` bridged at `Packages/LillistCore/Sources/LillistCore/ManagedObjects/SmartFilter+CoreData.swift:22`
- `Packages-LillistCore-Sources-LillistCore-Model.NotificationKind -> Packages-LillistCore-Sources-LillistCore-Notifications.NotificationScheduler (reads)` — referenced in `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift`
- `Packages-LillistCore-Sources-LillistCore-Model.SortField -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SmartFilterStore (reads)` — referenced in `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift`
- `Packages-LillistCore-Sources-LillistCore-Model.Status -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (reads)` — referenced in `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift`
- `Packages-LillistCore-Sources-LillistCore-Model.Status -> Packages-LillistUI-Sources-LillistUI-misc.StatusCycler (reads)` — referenced in `Packages/LillistUI/Sources/LillistUI/Status/StatusCycler.swift`
- `Packages-LillistCore-Sources-LillistCore-Model.SortField -> Packages-LillistUI-Sources-LillistUI-Settings.SortField+DisplayName (extends)` — extension at `Packages/LillistUI/Sources/LillistUI/Settings/SortField+DisplayName.swift`

## Type notes

Raw-value stability is the critical invariant for all enums in this module. `Status`,
`NotificationKind`, `AttachmentKind`, and `JournalEntryKind` are persisted as `Int16` in
Core Data and synced via CloudKit; `SortField` is persisted as a `String`. Adding a case
requires an unused raw value — never reorder or recycle existing values, as documented
at `Packages/LillistCore/Sources/LillistCore/Model/NotificationKind.swift:7` and
`Packages/LillistCore/Sources/LillistCore/Model/Status.swift:5`.

`JournalEntryKind.isUserEditable` is the only computed property in the module; it gates
edit permission at the model layer (`Packages/LillistCore/Sources/LillistCore/Model/JournalEntryKind.swift:11`).

`SortField.manualPosition` is only valid within a single parent's scope. The store layer
rejects cross-parent queries using it with `LillistError.validationFailed`, as described
in the doc comment at `Packages/LillistCore/Sources/LillistCore/Model/SortField.swift:5`.

The xcdatamodeld defines eight entities: `LillistTask`, `Tag`, `JournalEntry`, `Attachment`,
`AppPreferences`, `SmartFilter`, `Series`, and `NotificationSpec`. All are marked
`syncable="YES"` for CloudKit. `Attachment.data` uses `allowsExternalBinaryDataStorage="YES"`.
`LillistTask.children` and `Tag.children` cascade deletes; all other relationships use Nullify.
`.xccurrentversion` pins `LillistModel.xcdatamodel` as the active model version.

## External deps

- Foundation — imported in all five Swift files for base type conformances
- Core Data — `LillistModel.xcdatamodeld` is the persistent store model definition
- CloudKit — schema carries `usedWithCloudKit="YES"`; all entities are `syncable="YES"`
