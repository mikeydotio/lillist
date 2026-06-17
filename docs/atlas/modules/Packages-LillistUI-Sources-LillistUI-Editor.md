---
module: Packages/LillistUI/Sources/LillistUI/Editor
summary: Unified cross-platform task editor (quick-capture + full form) with draft-to-live auto-promotion
read_when: Touching task creation, full task editing, quick capture, or the editor model/view
sources:
  - path: Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorMode.swift
  - path: Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift
  - path: Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorView.swift
  - path: Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorCollectionSections.swift
  - path: Packages/LillistUI/Sources/LillistUI/Editor/ReminderEditorSection.swift
  - path: Packages/LillistUI/Sources/LillistUI/Editor/TagAssignmentField.swift
references_modules:
  - Packages-LillistCore-Sources-LillistCore-Stores-chunk-1
  - Packages-LillistCore-Sources-LillistCore-Stores-chunk-2
  - Packages-LillistCore-Sources-LillistCore-Notifications
  - Packages-LillistCore-Sources-LillistCore-Recurrence
  - Packages-LillistUI-Sources-LillistUI-QuickCapture
  - Packages-LillistUI-Sources-LillistUI-Recurrence
  - Packages-LillistUI-Sources-LillistUI-Theme-chunk-1
  - Packages-LillistUI-Sources-LillistUI-Theme-chunk-2
  - Packages-LillistUI-Sources-LillistUI-misc
generator: cartographer/1 model=claude-sonnet-4-6
---

# Module: Packages/LillistUI/Sources/LillistUI/Editor

## Purpose

This module is the unified task editor that replaced the per-platform Detail tabs. It presents one cross-platform surface in two modes — `quick` (single capture field) and `full` (every editable section) — backed by a single `@MainActor @Observable` model that manages draft-to-live auto-promotion. The core design invariant is that a new capture starts as a pure in-memory draft; operations that require a persisted row (subtask, attachment, journal note, reminder, recurrence) auto-promote the draft exactly once before proceeding, serialized so concurrent triggers share one in-flight commit rather than racing a second `create`. LillistUI remains `AppEnvironment`-free: the model is injected with a `Stores` bundle by the app-layer host.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `TaskEditorModel` | class | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:26` | `@MainActor @Observable` owner of all editor state; inject via `Stores` + `OpenIntent`; never call stores directly from views |
| `TaskEditorModel.Stores` | struct | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:33` | Value bundle of LillistCore stores passed to the model at init; `attachments` is optional (nil → attachment section inert) |
| `TaskEditorModel.OpenIntent` | enum | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:154` | `.newCapture(parentID:placement:)` or `.existing(UUID)`; controls initial `phase` and `mode` |
| `TaskEditorError` | enum | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:597` | `.emptyTitle`, `.inconsistentPromotion`, `.editorClosed`; thrown by commit/promote paths |
| `TaskEditorMode` | enum | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorMode.swift:13` | `.quick` or `.full`; controls which sections render in `TaskEditorView` |
| `TaskEditorPresentation` | enum | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorMode.swift:23` | `.capture` or `.existing`; drives draft-vs-live semantics and footer Delete button visibility |
| `TaskEditorView` | struct | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorView.swift:14` | Pure presenter over a `@Bindable TaskEditorModel`; host provides `onDismiss`, optional `onOpenSubtask`, optional `onAddAttachment` |
| `ReminderEditorSection` | struct | `Packages/LillistUI/Sources/LillistUI/Editor/ReminderEditorSection.swift:10` | Lists `NotificationSpecStore.SpecRecord`s and emits `onAdd(kind, offsetMinutes, fireDate)` / `onDelete(UUID)` |
| `TagAssignmentField` | struct | `Packages/LillistUI/Sources/LillistUI/Editor/TagAssignmentField.swift:10` | Removable tag chips + add field; emits `onAdd(String)` / `onRemove(String)`; no store access |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `TaskEditorModel.Phase` | enum | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:65` | Four-state machine (`.draft`, `.promoting`, `.live(UUID)`, `.abandoned`) that is the un-foolable source of "does a Core Data row exist yet"; all promote and discard logic branches on it |
| `ensureLive` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:258` | The auto-promote gate: concurrent callers share one in-flight `Task` stored in `promoteTask` to prevent a second `create` race; every relational mutation calls through here |
| `runCommit` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:297` | Performs create + best-effort enrichment (dates, status, tags, recurrence); `create` is the only throwing step — post-create failures record `lastCommitWarning` without reverting the row |
| `DraftSnapshot` | struct | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:356` | Immutable `Sendable` copy of model fields at promote time, preventing a subsequent edit from corrupting the in-flight commit's payload |
| `reloadRelations` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:547` | Clears draft tag buffer and refreshes all relational collections after a promote or explicit load; the canonical post-promote reconciliation step |
| `EditorSubtasksSection` | struct | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorCollectionSections.swift:7` | Subtask list + inline add; `onOpen` is the host seam for re-targeting the singleton editor to a child task |
| `EditorJournalSection` | struct | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorCollectionSections.swift:74` | Journal stream + note composer; status transitions also write journal entries (driven by `setStatus` reloading journal) |
| `EditorAttachmentsSection` | struct | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorCollectionSections.swift:136` | Attachment list + delete; "add" is an injected host action because `PhotosPicker`/`NSOpenPanel` are platform-specific |

## Relationships

- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorModel -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (calls)` — `stores.tasks.create`, `update`, `transition`, `softDelete`, `fetch`, `children`, `assignTag`, `unassignTag`, `tagIDs`; evidence: `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:190`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorModel -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TagStore (calls)` — `stores.tags.findOrCreate`, `fetch`; evidence: `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:325`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorModel -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SeriesStore (calls)` — `stores.series.create`, `update`, `delete`, `fetch`; evidence: `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:449`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorModel -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.JournalStore (calls)` — `stores.journal.appendNote`, `entries`; evidence: `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:476`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorModel -> Packages-LillistCore-Sources-LillistCore-Notifications.NotificationSpecStore (calls)` — `stores.notifications.add`, `delete`, `specs`; evidence: `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:462`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorModel -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.AttachmentStore (calls)` — `attachmentStore.addImage`, `delete`, `attachments`; evidence: `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:491`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorModel -> Packages-LillistUI-Sources-LillistUI-QuickCapture.QuickCaptureParser (calls)` — `QuickCaptureParser.parse(captureText)` in `ingestCaptureText`; evidence: `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:210`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorModel -> Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceEditorViewModel (owns)` — `recurrence: RecurrenceEditorViewModel` field; evidence: `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:130`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorView -> Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceEditorView (calls)` — recurrence sheet binds `$model.recurrence`; evidence: `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorView.swift:325`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.LillistColor (reads)` — color tokens throughout; evidence: `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorView.swift:65`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-2.LillistTypography (reads)` — typography tokens throughout; evidence: `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorView.swift:169`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorView -> Packages-LillistUI-Sources-LillistUI-misc.StatusIndicatorView (calls)` — status section embeds `StatusIndicatorView`; evidence: `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorView.swift:178`

## Type notes

`TaskEditorModel` is `@MainActor`-isolated: every `phase` read-modify-write is serialized by the actor; the only suspension points are `await`s into the non-isolated Core Data stores. The `DraftSnapshot` struct freezes the model's field buffer at trigger time so any subsequent user edit cannot corrupt the in-flight commit payload. Concurrent auto-promote calls share one `Task<UUID, Error>` stored in `promoteTask`; a `.promoting` branch with a `nil` `promoteTask` throws `.inconsistentPromotion` (should be unreachable).

Tags follow a distinct flow: while a draft they buffer as `draftTagNames` strings (no `Tag` rows minted) so abandoning a draft never orphans tag objects. After promote, `reloadRelations` materializes them as `assignedTags: [TagStore.TagRecord]`; `displayedTagNames` unifies both views of the same truth.

`discard()` is safe to call at any phase: pure draft → no-op; promoting → awaits the in-flight commit then soft-deletes; live → soft-deletes. All deletions go to Trash (soft-delete), never hard-delete.

`TaskEditorView` wires two separate save triggers: a 500 ms `textEditKey`-keyed `.task` debounce for `title`/`notes`, and an `onChange(of: scalarKey)` immediate flush for dates and pin. Both no-op while still a draft.

## External deps

- `SwiftUI` — `TaskEditorView`, `ReminderEditorSection`, `TagAssignmentField`, and all section views
- `Observation` — `@Observable` macro on `TaskEditorModel`
- `LillistCore` — `TaskStore`, `TagStore`, `SeriesStore`, `JournalStore`, `NotificationSpecStore`, `AttachmentStore`, `Status`, `NotificationKind`, `NewTaskPlacement`, `RecurrenceRule`, `AttachmentKind`

## Gotchas

- `attachments` in `Stores` is optional; macOS historically did not wire it. When nil, `addImageAttachment` and `deleteAttachment` return silently rather than crashing — `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:491`.
- `onAddAttachment` on `TaskEditorView` is also optional; the "Add attachment" button in `EditorAttachmentsSection` only renders when the host provides it — `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorCollectionSections.swift:163`.
- `ingestCaptureText` is a no-op when the parsed title is empty, preventing accidental title wipe on expand of a blank quick field — `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:212`.
