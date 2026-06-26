---
module: Packages/LillistUI/Sources/LillistUI/Editor
summary: "Task editor — TaskEditorModel draft-promote state machine + TaskEditorView quick/full UI + section views"
read_when: "Touching task creation or editing"
sources:
  - path: Packages/LillistUI/Sources/LillistUI/Editor/ReminderEditorSection.swift
    blob: 93caf7cb59e69d0d734a499f5e0b0eeaf18f5222
  - path: Packages/LillistUI/Sources/LillistUI/Editor/TagAssignmentField.swift
    blob: 9c44691f6d951431aeb7a4d066530345a63e180f
  - path: Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorCollectionSections.swift
    blob: 094b5a943ffb15a16bf338a8e184b2f6b16aa1d6
  - path: Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorMode.swift
    blob: 2ae5bdf058a64ebd4870d75e09c0bf70afed1be6
  - path: Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift
    blob: 3cea74d6b328a2b443dfd95957fc880e3e5459e0
  - path: Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorView.swift
    blob: 68e4816db392bbe89b2ef971463dce1a8ee94836
references_modules: [Apps-Lillist-macOS-Sources-Hotkey, Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistCore-Sources-LillistCore-Notifications, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistCore-Sources-LillistCore-Sync-chunk-1, Packages-LillistUI-Sources-LillistUI-Components-chunk-1, Packages-LillistUI-Sources-LillistUI-Recurrence, Packages-LillistUI-Sources-LillistUI-Settings, Packages-LillistUI-Sources-LillistUI-Status, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistUI/Sources/LillistUI/Editor

## Purpose

This module is the unified task-editing surface for Lillist: a `@MainActor @Observable` state machine (`TaskEditorModel`) that drives both quick capture and full editing from a single backing object, plus the cross-platform `TaskEditorView` that renders those two modes and all section views (tags, reminders, subtasks, journal, attachments). The unifying design idea is the draft-then-promote lifecycle — new tasks live entirely in memory until a relational operation forces them into Core Data, with concurrent promote attempts serialized through a single stored `Task`. Without this module the app has no create or edit path for tasks.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `EditorAttachmentsSection` | struct | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorCollectionSections.swift:118` | Callers pass current `AttachmentRecord`s and `onDelete`; omit `onAddTapped` to hide the add button (platform-picker is host-owned). |
| `EditorJournalSection` | struct | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorCollectionSections.swift:76` | Read-only presenter of `JournalRecord` entries; callers pass entries, view formats timestamps with a stable POSIX-locale formatter. |
| `EditorSubtasksSection` | struct | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorCollectionSections.swift:7` | Callers pass subtask `TaskRecord`s, an `onAdd` callback, and an optional `onOpen`; omit `onOpen` to disable tapping into a child. |
| `OpenIntent` | enum | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:154` | Sealed `Sendable` input to `TaskEditorModel.init`; `.newCapture` spawns an in-memory draft, `.existing(UUID)` opens a live row. |
| `Phase` | enum | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:65` | Internal four-case lifecycle state machine; `(set)` is `private(set)` — external observers see `taskID` and `mode` instead of `phase` directly. |
| `ReminderEditorSection` | struct | `Packages/LillistUI/Sources/LillistUI/Editor/ReminderEditorSection.swift:10` | Callers supply existing `SpecRecord`s and `onAdd`/`onDelete` closures; the view manages its own picker/date state and never touches stores directly. |
| `Stores` | struct | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:33` | `Sendable` value bundle of six LillistCore stores; `attachments` is optional — pass `nil` on platforms that don't support attachments. |
| `TagAssignmentField` | struct | `Packages/LillistUI/Sources/LillistUI/Editor/TagAssignmentField.swift:10` | Callers pass current `tagNames` and `onAdd`/`onRemove` closures; no store access — safe to use in snapshot tests with frozen data. |
| `TaskEditorError` | enum | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:597` | Three `Equatable` error cases thrown by the commit/ensureLive path: `emptyTitle`, `inconsistentPromotion`, `editorClosed`. |
| `TaskEditorMode` | enum | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorMode.swift:13` | `Sendable, Equatable` two-case enum; `.quick` shows a single capture field, `.full` shows all editor sections. |
| `TaskEditorModel` | class | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:26` | `@MainActor @Observable` class; callers init with `Stores` + `OpenIntent`, call `load()` on appear, then bind views to its published fields and call async mutating methods. |
| `TaskEditorPresentation` | enum | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorMode.swift:23` | `Sendable, Equatable` two-case enum; `.capture` starts an in-memory draft, `.existing` opens a persisted row for live-save editing. |
| `TaskEditorView` | struct | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorView.swift:14` | Cross-platform presenter bound to a `TaskEditorModel`; `onOpenSubtask` and `onAddAttachment` are optional host seams for platform-specific navigation and pickers. |
| `addImageAttachment` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:490` | No-ops silently when `stores.attachments` is nil; auto-promotes draft first, then persists via `AttachmentStore.addImage`. |
| `addJournalNote` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:474` | Auto-promotes the draft if needed, then appends a note via `JournalStore.appendNote` and reloads `journal`. |
| `addReminder` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:461` | Auto-promotes draft first; exactly one of `offsetMinutes` or `fireDate` should be non-nil depending on `kind`. |
| `addSubtask` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:482` | Auto-promotes draft first, then creates a child task with `parent: id` via `TaskStore.create` and reloads `subtasks`. |
| `addTag` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:408` | Phase-aware: buffers name in `draftTagNames` while a draft (no Tag row minted); finds-or-creates and assigns when live. |
| `commitDraft` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:248` | Commits the in-memory draft to Core Data and returns its UUID; idempotent with `ensureLive` — both funnel through the same promote path. |
| `commitQuickCapture` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:239` | Parses `captureText` via `ingestCaptureText()` then commits via `ensureLive`; returns the new task UUID. |
| `commitRecurrence` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:444` | Auto-promotes when setting a rule; creates/updates/deletes the `SeriesStore` series; clearing a rule on a draft is a no-op. |
| `deleteAttachment` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:497` | No-ops silently when `stores.attachments` is nil; removes the record via `AttachmentStore.delete` and reloads if live. |
| `deleteReminder` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:467` | Removes the spec via `NotificationSpecStore.delete`; reloads `reminders` only when the model is currently live. |
| `deleteTask` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:525` | Only effective while live; soft-deletes the task to Trash via `TaskStore.softDelete` and transitions phase to `.abandoned`. |
| `discard` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:510` | Safe to call at any phase — draft abandons cleanly with no writes; promoting awaits then soft-deletes; live soft-deletes; always ends `.abandoned`. |
| `ensureLive` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:258` | Returns the live UUID, committing the draft first if needed; serializes concurrent callers via a shared stored `Task`; throws `TaskEditorError` on empty title, inconsistency, or closed state. |
| `expandToFull` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:229` | Parses quick-capture text into structured fields then sets `mode = .full`; purely in-memory, no store access, no auto-promote. |
| `ingestCaptureText` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:209` | Parses `#tag ^date` syntax from `captureText` into `title`, `draftTagNames`, and `deadline`; no-op when the parsed title is empty. |
| `load` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:188` | Fetches scalars and all relational collections for a live task; no-op for a draft; call from the host's `.task`/`onAppear`. |
| `note` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:305` | Local closure inside `runCommit` — records the first failing enrichment step name; subsequent calls are no-ops; result surfaces as `lastCommitWarning`. |
| `removeTag` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:425` | Phase-aware: removes from `draftTagNames` while a draft; calls `TaskStore.unassignTag` and reloads `assignedTags` when live. |
| `saveScalarsNow` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:385` | Persists start/deadline/pin state to the live row immediately via `TaskStore.update`; no-op while a draft. |
| `saveTextNow` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:375` | Persists title + notes to the live row immediately via `TaskStore.update`; no-op while a draft; host calls after debounce and on blur. |
| `setStatus` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorModel.swift:399` | Updates `status` mirror always; calls `TaskStore.transition` and reloads `journal` (a status change writes a journal entry) when live. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `add` | func | `Packages/LillistUI/Sources/LillistUI/Editor/ReminderEditorSection.swift:104` | Sole translator from picker UI state (`Choice` + `fireDate`/`offsetMinutes`) to the `(NotificationKind, Int32?, Date?)` signature of `onAdd`; removing it would require inlining the three-case mapping at the call site (ReminderEditorSection.swift:104–113). |
| `commit` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TagAssignmentField.swift:65` | Sole path from text field submission/button tap to tag creation in `TagAssignmentField`; trims, guards empty, fires `onAdd`, clears draft, and retains focus (TagAssignmentField.swift:65–71). |
| `commit` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorCollectionSections.swift:65` | Sole path from text field submission/button tap to subtask creation in `EditorSubtasksSection`; trims, guards empty, fires `onAdd`, and clears draft (TaskEditorCollectionSections.swift:65–70). |
| `expand` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorView.swift:375` | Gates the quick→full animation against `reduceMotion` before calling `model.expandToFull()`; the only entry point for the animated expansion from the UI (TaskEditorView.swift:375–383). |
| `section` | func | `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorView.swift:416` | Private `@ViewBuilder` helper that stamps every labelled content group in the full-mode editor body with a consistent caption header and spacing. All eight section-level sub-views (Tags, Reminders, Subtasks, Attachments, Dates, Repeats, Notes, Journal) are composed through it — making it the structural backbone that gives the editor its uniform visual rhythm. Defined at `Packages/LillistUI/Sources/LillistUI/Editor/TaskEditorView.swift:416`; call sites at lines 105, 113, 123, 131, 185, 248, 269, 287 of the same file. |

## Relationships

- `Packages-LillistUI-Sources-LillistUI-Editor.Choice -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.Choice -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.State (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.Choice -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.accessibilityLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.Choice -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.rainbow (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.EditorAttachmentsSection -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.EditorAttachmentsSection -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.accessibilityLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.EditorAttachmentsSection -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.rainbow (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.EditorJournalSection -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.EditorSubtasksSection -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.EditorSubtasksSection -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1.StatusCubeView (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.EditorSubtasksSection -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.accessibilityLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.EditorSubtasksSection -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.fill (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.QuickCaptureFieldView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.fill (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.TagAssignmentField -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.TagAssignmentField -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.accessibilityLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.TagAssignmentField -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.fill (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorView -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorView -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1.StatusIndicatorView (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorView -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1.TagChipView (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorView -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorView -> Packages-LillistUI-Sources-LillistUI-Status.nextOnClick (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.accessibilityLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.glassSurface (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.rainbow (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.WrapTags -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.WrapTags -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1.TagChipView (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.WrapTags -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.accessibilityLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.add -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.add -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.addImageAttachment -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.addImage (writes)`
- `Packages-LillistUI-Sources-LillistUI-Editor.addJournalNote -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.appendNote (writes)`
- `Packages-LillistUI-Sources-LillistUI-Editor.addTag -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.findOrCreate (writes)`
- `Packages-LillistUI-Sources-LillistUI-Editor.addTag -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.assignTag (writes)`
- `Packages-LillistUI-Sources-LillistUI-Editor.dateRow -> Apps-Lillist-macOS-Sources-Hotkey.toggle (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.dateRow -> Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceEditorView (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.dateRow -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.dateRow -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.fill (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.dateRow -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.rainbow (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.dateRow -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.squish (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.deleteTask -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.softDelete (writes)`
- `Packages-LillistUI-Sources-LillistUI-Editor.discard -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.softDelete (writes)`
- `Packages-LillistUI-Sources-LillistUI-Editor.expand -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.squish (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.note -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.findOrCreate (writes)`
- `Packages-LillistUI-Sources-LillistUI-Editor.note -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.assignTag (writes)`
- `Packages-LillistUI-Sources-LillistUI-Editor.note -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.transition (writes)`
- `Packages-LillistUI-Sources-LillistUI-Editor.reloadAttachments -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.attachments (reads)`
- `Packages-LillistUI-Sources-LillistUI-Editor.reloadJournal -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.entries (reads)`
- `Packages-LillistUI-Sources-LillistUI-Editor.reloadRecurrence -> Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceEditorViewModel (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.reloadReminders -> Packages-LillistCore-Sources-LillistCore-Notifications.specs (reads)`
- `Packages-LillistUI-Sources-LillistUI-Editor.removeTag -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.unassignTag (writes)`
- `Packages-LillistUI-Sources-LillistUI-Editor.setStatus -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.transition (writes)`

## Type notes

`TaskEditorModel` is `@MainActor @Observable final class` — all field mutations are serialized on the main actor with no explicit locks; the only suspension points are `await`s into non-isolated Core Data stores (TaskEditorModel.swift:24–26). Concurrent promote attempts are serialized by storing the in-flight `Task<UUID, Error>` in `promoteTask`; callers in `.promoting` phase all await its `.value` rather than racing a second `create` (TaskEditorModel.swift:150,263–265). `Stores` is `Sendable` (its members are `@unchecked Sendable` store classes) to allow injection without importing the app's `AppEnvironment` (TaskEditorModel.swift:33). `attachments` is optional in `Stores`; macOS historically did not wire it, so the attachment section is designed to be inert when `nil` rather than crashing (TaskEditorModel.swift:40–41). Tag names are buffered in `draftTagNames: [String]` while in the `.draft` phase to avoid minting orphaned `Tag` rows for captures the user abandons; they are flushed only at promote time (TaskEditorModel.swift:118–119). All section views (`ReminderEditorSection`, `TagAssignmentField`, `EditorSubtasksSection`, `EditorJournalSection`, `EditorAttachmentsSection`) are pure presenters — they receive data and action closures, never call stores directly, keeping them snapshot-friendly.

## External deps

- Foundation — imported
- LillistCore — imported
- Observation — imported
- SwiftUI — imported

## Gotchas

The local `note()` closure inside `runCommit` is defined at TaskEditorModel.swift:305 but the extractor attributes lines 305–336 to it, making its fan-in count (30) and cross-module edges misleading — the store calls are in `runCommit`'s body, not inside `note` itself. The `discard()` path for `.promoting` awaits `promoteTask?.value` and silently swallows a promote error before soft-deleting, leaving the editor `.abandoned` with no user-visible feedback if `create` failed mid-discard (TaskEditorModel.swift:514–517). `EditorJournalSection` uses a `private static let` POSIX-locale `DateFormatter` (`yyyy-MM-dd HH:mm:ss`) to keep timestamps stable across user locales — replacing it with a relative formatter would break snapshot baselines (TaskEditorCollectionSections.swift:83–87).
