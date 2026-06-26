---
module: Packages/LillistCore/Sources/LillistCore/ManagedObjects
summary: "Hand-written @NSManaged entity subclasses; the explicit Core Data schema for all LillistCore persistent types."
read_when: "Touching Core Data entity shape"
sources:
  - path: "Packages/LillistCore/Sources/LillistCore/ManagedObjects/AppPreferences+CoreData.swift"
    blob: 45b2c0207922cc1482ecc9454154885f40d6b504
  - path: "Packages/LillistCore/Sources/LillistCore/ManagedObjects/Attachment+CoreData.swift"
    blob: f9c9ef801251fb7cf32a3cf91c777614bb04ffe6
  - path: "Packages/LillistCore/Sources/LillistCore/ManagedObjects/JournalEntry+CoreData.swift"
    blob: 2f5063ad7f2bcad77405aeb1331a14e7715b07d7
  - path: "Packages/LillistCore/Sources/LillistCore/ManagedObjects/LillistTask+CoreData.swift"
    blob: e3db9666871b6e58f3bccbadaf86c0c071badabd
  - path: "Packages/LillistCore/Sources/LillistCore/ManagedObjects/NotificationSpec+CoreData.swift"
    blob: 0d3763da50f713f1f1928b03adec02d8d92b5eb5
  - path: "Packages/LillistCore/Sources/LillistCore/ManagedObjects/Series+CoreData.swift"
    blob: 5571ecb640c8eac0151caf139ba25ac8379f14e4
  - path: "Packages/LillistCore/Sources/LillistCore/ManagedObjects/SmartFilter+CoreData.swift"
    blob: a742d4be2470d4706931d2cb182777f1b3f7bae2
  - path: "Packages/LillistCore/Sources/LillistCore/ManagedObjects/Tag+CoreData.swift"
    blob: 2bdf18d272d768aaeed043a1f3714df7d148a25b
references_modules: [Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistCore-Sources-LillistCore-Model]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistCore/Sources/LillistCore/ManagedObjects

## Purpose

This module is the explicit Core Data schema layer for all of LillistCore: eight hand-written @NSManaged subclasses declare every persistent entity (LillistTask, Tag, Series, Attachment, JournalEntry, NotificationSpec, SmartFilter, AppPreferences) with their properties and relationships. The design keeps Core Data codegen disabled and every field visible in source, so schema changes are always intentional and reviewable. If this module vanished, none of the LillistCore stores could access the object graph — it is the sole definition of what lives in the persistent container.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AppPreferences` | class | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/AppPreferences+CoreData.swift:5` | Single-instance entity for app-wide settings: notification times, sort defaults, trash retention, Quick Capture config, crash prompts, onboarding flag. |
| `AppPreferences` | extension | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/AppPreferences+CoreData.swift:22` | Typed accessor `defaultTaskListSort: SortField` over `defaultTaskListSortRaw`; defaults to `.manualPosition` when the stored string is nil or unrecognised. |
| `Attachment` | class | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/Attachment+CoreData.swift:5` | Entity linking binary data or link-preview JSON to either a task or a journal entry; `uti`, `byteSize`, and `kindRaw` describe the payload. |
| `Attachment` | extension | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/Attachment+CoreData.swift:19` | Typed accessor `kind: AttachmentKind` over `kindRaw` (Int16); defaults to `.file` when the raw value is unrecognised. |
| `JournalEntry` | class | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/JournalEntry+CoreData.swift:5` | Entity for a task's journal timeline entry: text body, binary payload, timestamps; related to a parent LillistTask and an optional set of Attachments. |
| `JournalEntry` | extension | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/JournalEntry+CoreData.swift:17` | KVO-compliant to-many accessors `addToAttachments(_:)` / `removeFromAttachments(_:)` for the JournalEntry–Attachment relationship. |
| `JournalEntry` | extension | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/JournalEntry+CoreData.swift:25` | Typed accessor `kind: JournalEntryKind` over `kindRaw` (Int16); defaults to `.note` when the raw value is unrecognised. |
| `LillistTask` | class | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/LillistTask+CoreData.swift:5` | Central task entity: title, notes, status, date fields, position, hierarchy (parent/children), plus relationships to Tag, JournalEntry, Attachment, NotificationSpec, and Series; `schemaVersion` carries CloudKit schema compatibility. |
| `LillistTask` | extension | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/LillistTask+CoreData.swift:40` | Hand-written KVO-compliant to-many accessors for the children, tags, journalEntries, attachments, and notificationSpecs relationships on LillistTask. |
| `LillistTask` | extension | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/LillistTask+CoreData.swift:90` | Typed accessor `status: Status` over `statusRaw` (defaults `.todo`) and internal `stampCurrentSchemaVersion()` for per-write CloudKit schema versioning. |
| `NotificationSpec` | class | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/NotificationSpec+CoreData.swift:5` | Entity describing a single notification trigger for a task: kind, offset or absolute fire date, last-fired timestamp, snooze tracking, and a back-reference to its LillistTask. |
| `NotificationSpec` | extension | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/NotificationSpec+CoreData.swift:17` | Typed accessor `kind: NotificationKind` over `kindRaw` (Int16); defaults to `.defaultStart` when the raw value is unrecognised. |
| `Series` | class | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/Series+CoreData.swift:5` | Entity for a recurrence series: stores serialised RecurrenceRule as JSON, a `nextOccurrenceAfter` bookmark for the expander, and relationships to a seed task and its spawned instances. |
| `Series` | extension | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/Series+CoreData.swift:14` | KVO-compliant to-many accessors `addToInstances(_:)` / `removeFromInstances(_:)` for the Series–LillistTask (instances) relationship. |
| `Series` | extension | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/Series+CoreData.swift:28` | Typed accessor `rule: RecurrenceRule?` JSON-encodes/decodes `ruleJSON`; returns nil on missing or malformed JSON — callers must treat nil as a data-corruption signal. |
| `SmartFilter` | class | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/SmartFilter+CoreData.swift:5` | Entity for a user-defined smart filter: name, predicate group JSON, tint color, sort field, pinned flag, position, and created/modified timestamps. |
| `SmartFilter` | extension | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/SmartFilter+CoreData.swift:18` | Typed accessor `sortField: SortField` over `sortFieldRaw` (String?); defaults to `.deadline` when the stored string is nil or unrecognised. |
| `Tag` | class | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/Tag+CoreData.swift:5` | Hierarchical tag entity: name, tint color, position; self-referential parent/children for nesting, and a to-many relationship to LillistTask. |
| `Tag` | extension | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/Tag+CoreData.swift:16` | KVO-compliant to-many accessors for the Tag children (Tag) and tasks (LillistTask) relationships. |
| `Tag` | extension | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/Tag+CoreData.swift:30` | Computed traversal helpers: `root` walks the parent chain to the hierarchy root; `descendants` returns a depth-first flattened list of all descendant tags. |
| `stampCurrentSchemaVersion` | func | `Packages/LillistCore/Sources/LillistCore/ManagedObjects/LillistTask+CoreData.swift:104` | Sets `schemaVersion` to `CloudKitSchema.currentVersion`; must be called explicitly at every local write site — never from Core Data lifecycle hooks — to avoid re-dirtying CloudKit-mirrored records. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-ManagedObjects.Attachment -> Packages-LillistCore-Sources-LillistCore-Model.AttachmentKind (calls)`
- `Packages-LillistCore-Sources-LillistCore-ManagedObjects.JournalEntry -> Packages-LillistCore-Sources-LillistCore-Model.JournalEntryKind (calls)`
- `Packages-LillistCore-Sources-LillistCore-ManagedObjects.LillistTask -> Packages-LillistCore-Sources-LillistCore-Model.Status (calls)`
- `Packages-LillistCore-Sources-LillistCore-ManagedObjects.NotificationSpec -> Packages-LillistCore-Sources-LillistCore-Model.NotificationKind (calls)`
- `Packages-LillistCore-Sources-LillistCore-ManagedObjects.Series -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`

## Type notes

All eight entities are `public final class X: NSManagedObject` with `@objc(Name)` for KVC runtime lookup; Core Data codegen is disabled project-wide. Enum-typed fields are stored as raw scalars (`statusRaw: Int16`, `kindRaw: Int16`, `sortFieldRaw: String?`) with typed computed accessors in companion extensions — e.g., `LillistTask.status: Status` at Packages/LillistCore/Sources/LillistCore/ManagedObjects/LillistTask+CoreData.swift:92. `LillistTask.schemaVersion` (Packages/LillistCore/Sources/LillistCore/ManagedObjects/LillistTask+CoreData.swift:28) is an additive Int16 field stamped on every local write; records written before the field existed default to 0 via lightweight migration. `Series.rule` (Packages/LillistCore/Sources/LillistCore/ManagedObjects/Series+CoreData.swift:31) JSON-encodes/decodes a `RecurrenceRule` inline; its internal JSONDecoder/Encoder makes it the only managed object with non-trivial computed logic. `Tag` is self-referential — `parent`/`children` at Packages/LillistCore/Sources/LillistCore/ManagedObjects/Tag+CoreData.swift:11-12 form a hierarchy; `root` and `descendants` in the second extension provide traversal. None of these objects may escape LillistCore; stores expose only value-type DTOs.

## External deps

- CoreData — imported
- Foundation — imported

## Gotchas

stampCurrentSchemaVersion() must never be called from awakeFromInsert/willSave — the inline comment at Packages/LillistCore/Sources/LillistCore/ManagedObjects/LillistTask+CoreData.swift:98-103 explains that a lifecycle hook would re-dirty CloudKit-imported records during mirroring and echo a redundant write back; it must be called only at explicit local-write sites. Series.rule silently returns nil when ruleJSON is missing or malformed (Packages/LillistCore/Sources/LillistCore/ManagedObjects/Series+CoreData.swift:29-30); callers must treat nil as a data-corruption signal, not merely a missing value. Attachment carries two nullable parent relationships (task and journalEntry at Packages/LillistCore/Sources/LillistCore/ManagedObjects/Attachment+CoreData.swift:15-16); the model allows both nil or both non-nil — the constraint that exactly one is set is enforced by store logic, not the entity.
