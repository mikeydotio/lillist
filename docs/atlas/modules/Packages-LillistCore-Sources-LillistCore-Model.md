---
module: Packages/LillistCore/Sources/LillistCore/Model
summary: "Persisted enum vocabulary + the Core Data schema all LillistCore entities are built on"
read_when: "Core Data schema, enums"
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
references_modules: [Packages-LillistCore-Sources-LillistCore-ManagedObjects, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Notifications]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
---

# Module: Packages/LillistCore/Sources/LillistCore/Model

## Purpose

The shared, persisted enum vocabulary of the data layer plus the Core Data
schema (`LillistModel.xcdatamodeld`) every entity is built on. These small
`Int`/`String`-raw enums are the typed faces of the `Int16`/`String` raw
columns that the schema declares — they are the contract that keeps stored
integers meaningful across app launches and CloudKit sync. If this module
vanished, the managed-object typed accessors and every store query that sorts
or filters by status would lose their shared type definitions.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AttachmentKind` | enum | `Packages/LillistCore/Sources/LillistCore/Model/AttachmentKind.swift:3` | `Int`-raw kind of an `Attachment` (image/file/linkPreview); persisted |
| `JournalEntryKind` | enum | `Packages/LillistCore/Sources/LillistCore/Model/JournalEntryKind.swift:3` | `Int`-raw kind of a journal entry; `isUserEditable` gates user edits |
| `JournalEntryKind.isUserEditable` | property | `Packages/LillistCore/Sources/LillistCore/Model/JournalEntryKind.swift:11` | `false` for system entries (statusChange, createdFollowUp) |
| `NotificationKind` | enum | `Packages/LillistCore/Sources/LillistCore/Model/NotificationKind.swift:8` | `Int`-raw kind of a `NotificationSpec`; raw values persisted, never reorder |
| `NotificationKind.Anchor` | enum | `Packages/LillistCore/Sources/LillistCore/Model/NotificationKind.swift:22` | Which task field a kind anchors to (`start`/`deadline`), `nil` for nudge |
| `NotificationKind.anchor` | property | `Packages/LillistCore/Sources/LillistCore/Model/NotificationKind.swift:27` | Maps each kind to its `Anchor?` |
| `NotificationKind.isOffset` | property | `Packages/LillistCore/Sources/LillistCore/Model/NotificationKind.swift:35` | `true` for the Layer-3 offset kinds |
| `SortField` | enum | `Packages/LillistCore/Sources/LillistCore/Model/SortField.swift:9` | `String`-raw task-list sort field; `manualPosition` only valid single-parent |
| `Status` | enum | `Packages/LillistCore/Sources/LillistCore/Model/Status.swift:7` | `Int`-raw task lifecycle state; raw values persisted, never reorder |
| `Status.isClosed` | property | `Packages/LillistCore/Sources/LillistCore/Model/Status.swift:14` | `true` only for the terminal `.closed` state |

## Load-bearing internals

(None — every symbol in this module is public; the Core Data schema is data,
not code.)

## Relationships

- `Packages-LillistCore-Sources-LillistCore-ManagedObjects.LillistTask -> Packages-LillistCore-Sources-LillistCore-Model.Status (reads)`
- `Packages-LillistCore-Sources-LillistCore-ManagedObjects.NotificationSpec -> Packages-LillistCore-Sources-LillistCore-Model.NotificationKind (reads)`
- `Packages-LillistCore-Sources-LillistCore-ManagedObjects.Attachment -> Packages-LillistCore-Sources-LillistCore-Model.AttachmentKind (reads)`
- `Packages-LillistCore-Sources-LillistCore-ManagedObjects.JournalEntry -> Packages-LillistCore-Sources-LillistCore-Model.JournalEntryKind (reads)`
- `Packages-LillistCore-Sources-LillistCore-ManagedObjects.SmartFilter -> Packages-LillistCore-Sources-LillistCore-Model.SortField (reads)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TaskStore -> Packages-LillistCore-Sources-LillistCore-Model.SortField (reads)`
- `Packages-LillistCore-Sources-LillistCore-Notifications.NotificationScheduler -> Packages-LillistCore-Sources-LillistCore-Model.NotificationKind (reads)`

## Type notes

All five enums are `CaseIterable, Codable, Sendable`; the `Int`-raw ones
(`AttachmentKind`, `JournalEntryKind`, `NotificationKind`, `Status`) and the
`String`-raw `SortField` are the typed mirrors of raw columns declared in the
schema. The schema stores them as `Integer 16`/`String`: `statusRaw`,
`kindRaw` (on `JournalEntry`, `Attachment`, `NotificationSpec`),
`sortFieldRaw`/`defaultTaskListSortRaw`. Typed accessors live in the
ManagedObjects module and fall back to a safe default (e.g. `Status` → `.todo`,
`AttachmentKind` → `.file`) on an unknown raw value, so an out-of-range stored
integer never traps.

Persistence invariant: `Status` (`Packages/LillistCore/Sources/LillistCore/Model/Status.swift:6`)
and `NotificationKind` (`Packages/LillistCore/Sources/LillistCore/Model/NotificationKind.swift:6`)
raw values are persisted — cases must never be reordered or removed, and new
cases take an unused raw value. `SortField.manualPosition`
(`Packages/LillistCore/Sources/LillistCore/Model/SortField.swift:5`) is only
meaningful within a single parent; the store layer rejects it with
`LillistError.validationFailed` across parent boundaries.

The schema (`LillistModel.xcdatamodel/contents`) declares entities `LillistTask`,
`Tag`, `JournalEntry`, `Attachment`, `AppPreferences`, `SmartFilter`, `Series`,
and `NotificationSpec` — each `syncable="YES"`, with `usedWithCloudKit="YES"`
set once on the `<model>` element. `LillistTask` self-references via `parent`
(Nullify) and `children` (Cascade) and owns `journalEntries`, `attachments`,
and `notificationSpecs` by Cascade; `Tag.tasks` and `Series.instances` are
Nullify. `.xccurrentversion` pins `LillistModel.xcdatamodel` as the active
model version.

## External deps

- Foundation — base types for the enum declarations
- Core Data — `LillistModel.xcdatamodeld` is the persistent model definition
- CloudKit — schema is `usedWithCloudKit`; entities are CloudKit-syncable
