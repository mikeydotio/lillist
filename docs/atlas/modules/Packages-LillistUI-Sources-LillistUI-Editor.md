---
module: Packages/LillistUI/Sources/LillistUI/Editor
summary: "Unified task editor — draft/live lifecycle model, quick/full presentation, and all editor sub-sections"
read_when: "Touching task creation, editing, quick capture, or the editor's draft-promote flow"
sources:
  - path: Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift
    blob: 3cea74d6b328a2b443dfd95957fc880e3e5459e0
  - path: Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorView.swift
    blob: 027bd0b960330456662789459e932cf1f4caaf47
  - path: Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorMode.swift
    blob: 2ae5bdf058a64ebd4870d75e09c0bf70afed1be6
  - path: Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorCollectionSections.swift
    blob: 6138a27882e6de0e3a4ffae8f946f7820be3e879
  - path: Packages/LillistUI/Sources/LillistUI/Editor/ReminderEditorSection.swift
    blob: 93caf7cb59e69d0d734a499f5e0b0eeaf18f5222
  - path: Packages/LillistUI/Sources/LillistUI/Editor/TagAssignmentField.swift
    blob: 9c44691f6d951431aeb7a4d066530345a63e180f
references_modules: [Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistCore-Sources-LillistCore-Notifications, Packages-LillistCore-Sources-LillistCore-Recurrence, Packages-LillistCore-Sources-LillistCore-Model, Packages-LillistUI-Sources-LillistUI-QuickCapture, Packages-LillistUI-Sources-LillistUI-Recurrence, Packages-LillistUI-Sources-LillistUI-Components, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1, Packages-LillistUI-Sources-LillistUI-Theme-chunk-2, Packages-LillistUI-Sources-LillistUI-Accessibility, Packages-LillistUI-Sources-LillistUI-misc]
generator: cartographer/1
baseline: 1a1562b636e43ebbdc35c7939ab6989b387f50e9
verified: true
---

# Module: Packages/LillistUI/Sources/LillistUI/Editor

## Purpose

This module owns the unified task editor: a single `@Observable @MainActor` model (`TaskEditorModel`) plus a cross-platform SwiftUI view (`TaskEditorView`) that adapts between a compact quick-capture mode and a full edit surface. The central design idea is a **draft/live phase machine** — new captures buffer entirely in-memory until the first op that needs a persisted parent, at which point `ensureLive()` auto-promotes with concurrent-commit serialization. Without this module there is no in-app path to create or edit tasks.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `ReminderEditorSection` | struct | `Packages/LillistUI/Sources/LillistUI/Editor/ReminderEditorSection.swift:10` | Presentation-only reminder list + add form; host wires `onAdd`/`onDelete` to the model |
| `TagAssignmentField` | struct | `Packages/LillistUI/Sources/LillistUI/Editor/TagAssignmentField.swift:10` | Removable chip row + add-by-name field; fully `AppEnvironment`-free, snapshot-friendly |
| `TaskEditorError` | enum | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:597` | Thrown by commit path: `emptyTitle`, `inconsistentPromotion`, `editorClosed` |
| `TaskEditorMode` | enum | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorMode.swift:13` | `.quick` (single field) / `.full` (all sections); changing this is the expand operation |
| `TaskEditorModel` | class | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:26` | Single owner of editor state; `@MainActor @Observable`; injected with a `Stores` bundle |
| `TaskEditorModel.OpenIntent` | enum | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:154` | `.newCapture(parentID:placement:)` or `.existing(UUID)` — passed to `init` |
| `TaskEditorModel.Stores` | struct | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:33` | Sendable value bundle injecting `TaskStore`, `TagStore`, `SeriesStore`, `JournalStore`, `NotificationSpecStore`, optional `AttachmentStore` |
| `TaskEditorPresentation` | enum | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorMode.swift:23` | `.capture` (draft semantics) / `.existing` (live-save); controls footer delete affordance |
| `TaskEditorView` | struct | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorView.swift:14` | Pure presentation over `TaskEditorModel`; host seams are `onOpenSubtask` and `onAddAttachment` |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `TaskEditorModel.Phase` | enum | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:65` | Four-state machine: `.draft`, `.promoting`, `.live(UUID)`, `.abandoned`; all public ops gate on it |
| `ensureLive` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:258` | Core auto-promote gate; concurrent callers share one in-flight `Task` via `promoteTask` to prevent double-create |
| `runCommit` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:297` | Creates row then best-effort enriches (dates, status, tags, recurrence); `create` is the only throwing step |
| `DraftSnapshot` | struct | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:356` | Immutable `Sendable` field snapshot captured at promote time; prevents later edits from corrupting in-flight commit |
| `reloadRelations` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:547` | Clears draft tag buffer and refreshes all relational collections after promote or `load()` |
| `setStatus` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:399` | Updates mirror unconditionally; transitions row and reloads journal when live |
| `saveTextNow` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:375` | Debounced live-save of title+notes; called by view's 500 ms `.task(id: textEditKey)` and on dismiss |
| `addImageAttachment` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:490` | Guard-early-outs when `stores.attachments` is nil; auto-promotes before writing |
| `addJournalNote` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:474` | Auto-promotes, then appends via `JournalStore`; reloads journal collection |
| `addReminder` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:461` | Auto-promotes, then delegates to `NotificationSpecStore`; reloads reminders |
| `EditorSubtasksSection` | struct | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorCollectionSections.swift:7` | Subtask list + inline add; `onOpen` is the host seam for re-targeting the singleton editor to a child |
| `EditorJournalSection` | struct | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorCollectionSections.swift:74` | Read-only entry stream + note composer; status transitions also write journal entries |
| `EditorAttachmentsSection` | struct | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorCollectionSections.swift:136` | Attachment list + delete; acquisition is a platform-injected host action |

## Relationships

- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorModel -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (calls)` — `create`, `update`, `transition`, `softDelete`, `fetch`, `children`, `assignTag`, `unassignTag`, `tagIDs`; evidence: `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:190`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorModel -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TagStore (calls)` — `findOrCreate`, `fetch`; evidence: `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:325`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorModel -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SeriesStore (calls)` — `create`, `update`, `delete`, `fetch`; evidence: `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:449`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorModel -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.JournalStore (calls)` — `appendNote`, `entries`; evidence: `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:476`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorModel -> Packages-LillistCore-Sources-LillistCore-Notifications.NotificationSpecStore (calls)` — `add`, `delete`, `specs`; evidence: `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:462`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorModel -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.AttachmentStore (calls)` — `addImage`, `delete`, `attachments`; evidence: `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:491`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorModel -> Packages-LillistUI-Sources-LillistUI-QuickCapture.QuickCaptureParser (calls)` — `QuickCaptureParser.parse(captureText)` in `ingestCaptureText`; evidence: `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:210`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorModel -> Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceEditorViewModel (owns)` — `recurrence: RecurrenceEditorViewModel` field; evidence: `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:130`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorView -> Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceEditorView (calls)` — recurrence sheet; evidence: `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorView.swift:325`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorView -> Packages-LillistUI-Sources-LillistUI-misc.StatusIndicatorView (calls)` — status section; evidence: `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorView.swift:178`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorView -> Packages-LillistUI-Sources-LillistUI-Components.TagChipView (calls)` — quick mode parsed tag display; evidence: `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorView.swift:59`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.LillistColor (reads)` — color tokens throughout; evidence: `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorView.swift:65`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-2.LillistTypography (reads)` — typography tokens throughout; evidence: `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorView.swift:169`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorView -> Packages-LillistUI-Sources-LillistUI-Accessibility.reduceMotionOverride (reads)` — expand animation respects override; evidence: `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorView.swift:24`
- `Packages-LillistUI-Sources-LillistUI-Editor.ReminderEditorSection -> Packages-LillistCore-Sources-LillistCore-Notifications.NotificationSpecStore (reads)` — `SpecRecord` and `NotificationKind`; evidence: `Packages/LillistUI/Sources/LillistUI/Editor/ReminderEditorSection.swift:11`
- `Packages-LillistUI-Sources-LillistUI-Editor.ReminderEditorSection -> Packages-LillistCore-Sources-LillistCore-Model.NotificationKind (reads)` — `kind` enum in `add()` switch; evidence: `Packages/LillistUI/Sources/LillistUI/Editor/ReminderEditorSection.swift:106`

## Type notes

`TaskEditorModel` is `@MainActor`-isolated: every `phase` read-modify-write is serialized by the actor; the only suspension points are `await`s into the non-isolated Core Data stores. The `DraftSnapshot` struct freezes the model's field buffer at trigger time so any subsequent user edit cannot corrupt the in-flight commit payload. Concurrent auto-promote calls share one `Task<UUID, Error>` stored in `promoteTask`; a `.promoting` branch with a `nil` `promoteTask` throws `.inconsistentPromotion` (should be unreachable).

Tags follow a bifurcated flow: while a draft they buffer as `draftTagNames` strings (no `Tag` rows minted) so abandoning a draft never orphans tag objects. After promote, `reloadRelations` materializes them into `assignedTags: [TagStore.TagRecord]`; `displayedTagNames` unifies both views.

`discard()` is safe to call at any phase: pure draft writes nothing; promoting awaits the in-flight commit then soft-deletes; live soft-deletes. All deletions go to Trash, never hard-delete.

`TaskEditorView` wires two save triggers: a 500 ms `textEditKey`-keyed `.task` debounce for `title`/`notes`, and an `onChange(of: scalarKey)` immediate flush for dates and pin. Both no-op while still a draft.

## External deps

- `SwiftUI` — `TaskEditorView`, `ReminderEditorSection`, `TagAssignmentField`, all section views
- `Observation` — `@Observable` macro on `TaskEditorModel`
- `LillistCore` — `TaskStore`, `TagStore`, `SeriesStore`, `JournalStore`, `NotificationSpecStore`, `AttachmentStore`, `Status`, `NotificationKind`, `NewTaskPlacement`, `RecurrenceRule`, `AttachmentKind`

## Gotchas

- `attachments` in `Stores` is optional; macOS historically did not wire it. When nil, `addImageAttachment` and `deleteAttachment` return silently — `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:491`.
- `onAddAttachment` on `TaskEditorView` is also optional; `EditorAttachmentsSection` only renders the "Add" button when the host provides it — `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorCollectionSections.swift:163`.
- `ingestCaptureText` is a no-op when the parsed title is empty, preventing accidental title wipe on expand of a blank quick field — `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:212`.
- `RecurrenceEditorView` commits only when the Save toolbar item is tapped; dismissing the sheet via Cancel discards the change — `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorView.swift:329`.
