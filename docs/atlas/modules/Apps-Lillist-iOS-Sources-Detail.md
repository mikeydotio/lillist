---
module: Apps/Lillist-iOS/Sources/Detail
summary: "iOS task-detail surface — segmented Notes/Subtasks/Journal/Attachments tabs plus recurrence sheet"
read_when: "iOS task detail screen"
sources:
  - path: Apps/Lillist-iOS/Sources/Detail/RecurrenceSheet.swift
    blob: 40a4472a16ef4ecfbb2ea527940175da846e0bcf
  - path: Apps/Lillist-iOS/Sources/Detail/TaskAttachmentsTab.swift
    blob: 4d2ba1a4b7f93674337c7dfc1330a8f36da30ad8
  - path: Apps/Lillist-iOS/Sources/Detail/TaskDetailView.swift
    blob: 48e20263cf99acb259fb8c5e33812e1c2574fc78
  - path: Apps/Lillist-iOS/Sources/Detail/TaskJournalTab.swift
    blob: 6974aca358fa010a57dcd768d05afbd52593783b
  - path: Apps/Lillist-iOS/Sources/Detail/TaskNotesTab.swift
    blob: 88144eb0768e68e7a61217a7646d869b62207a5d
  - path: Apps/Lillist-iOS/Sources/Detail/TaskSubtasksTab.swift
    blob: 8dedc9faab747afc6b1723c10f48f2917d78b883
references_modules: [Apps-Lillist-iOS-Sources-App, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistUI-Sources-LillistUI-Recurrence, Packages-LillistUI-Sources-LillistUI-Components, Packages-LillistUI-Sources-LillistUI-Accessibility, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1, Packages-LillistUI-Sources-LillistUI-misc]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
---

# Module: Apps/Lillist-iOS/Sources/Detail

## Purpose

The iOS task-detail screen. `TaskDetailView` wraps a `TaskStore.TaskRecord` in a
header plus a segmented `Picker` that swaps between four self-contained tab views
(Notes, Subtasks, Journal, Attachments), each owning its own `@State`, `.task`
load, and store writes. A toolbar button opens `RecurrenceSheet` for editing the
task's series rule. The module is pure app-target glue: every tab reads/writes
through `AppEnvironment`'s stores and renders shared `LillistUI` components, so it
holds presentation/lifecycle state while delegating all data and visuals.

## Public API

These view types are app-target `internal` (Swift default); they are the surface
the App module composes into navigation.

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `RecurrenceSheet` | struct | `Apps/Lillist-iOS/Sources/Detail/RecurrenceSheet.swift:5` | Modal recurrence editor; `init(taskID:initialRule:initialSeriesID:initialAnchorDate:onClose:)`, calls `onClose` on save/cancel |
| `TaskAttachmentsTab` | struct | `Apps/Lillist-iOS/Sources/Detail/TaskAttachmentsTab.swift:8` | Read-only attachment grid for a task id |
| `TaskDetailView` | struct | `Apps/Lillist-iOS/Sources/Detail/TaskDetailView.swift:16` | Detail surface; `init` takes a `taskID: UUID`, fetches the record from env |
| `TaskJournalTab` | struct | `Apps/Lillist-iOS/Sources/Detail/TaskJournalTab.swift:9` | Reverse-chron journal log + bottom composer for a task id |
| `TaskNotesTab` | struct | `Apps/Lillist-iOS/Sources/Detail/TaskNotesTab.swift:9` | Debounced free-text notes editor; `init(taskID:initialText:)` |
| `TaskSubtasksTab` | struct | `Apps/Lillist-iOS/Sources/Detail/TaskSubtasksTab.swift:7` | Lists + inline-adds children of a task id |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `Tab` | enum | `Apps/Lillist-iOS/Sources/Detail/TaskDetailView.swift:26` | `@SceneStorage`-persisted segment selection; drives which tab body renders |
| `TaskDetailHeader` | struct | `Apps/Lillist-iOS/Sources/Detail/TaskDetailView.swift:120` | Combines status + deadline into one VoiceOver header element |
| `commit` | func | `Apps/Lillist-iOS/Sources/Detail/RecurrenceSheet.swift:60` | Maps editor output to series create/update/delete; the sheet's only write path |
| `composer` | func | `Apps/Lillist-iOS/Sources/Detail/TaskJournalTab.swift:38` | Bottom-pinned entry field; scrolls latest into view on focus |
| `setStatus` | func | `Apps/Lillist-iOS/Sources/Detail/TaskSubtasksTab.swift:65` | Applies an explicit subtask status via `taskStore.transition` |

## Relationships

- `Apps-Lillist-iOS-Sources-Detail.TaskDetailView -> Apps-Lillist-iOS-Sources-App.AppEnvironment (reads)`
- `Apps-Lillist-iOS-Sources-Detail.TaskDetailView -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (calls)`
- `Apps-Lillist-iOS-Sources-Detail.TaskNotesTab -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (writes)`
- `Apps-Lillist-iOS-Sources-Detail.TaskSubtasksTab -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (calls)`
- `Apps-Lillist-iOS-Sources-Detail.TaskSubtasksTab -> Packages-LillistUI-Sources-LillistUI-Components.TaskRowView (calls)`
- `Apps-Lillist-iOS-Sources-Detail.TaskSubtasksTab -> Packages-LillistUI-Sources-LillistUI-misc.StatusCycler (calls)`
- `Apps-Lillist-iOS-Sources-Detail.TaskJournalTab -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.JournalStore (calls)`
- `Apps-Lillist-iOS-Sources-Detail.TaskJournalTab -> Packages-LillistUI-Sources-LillistUI-Components.JournalEntryRow (calls)`
- `Apps-Lillist-iOS-Sources-Detail.TaskAttachmentsTab -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.AttachmentStore (calls)`
- `Apps-Lillist-iOS-Sources-Detail.RecurrenceSheet -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SeriesStore (calls)`
- `Apps-Lillist-iOS-Sources-Detail.RecurrenceSheet -> Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceEditorView (calls)`
- `Apps-Lillist-iOS-Sources-Detail.RecurrenceSheet -> Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceEditorViewModel (owns)`
- `Apps-Lillist-iOS-Sources-Detail.RecurrenceSheet -> Packages-LillistUI-Sources-LillistUI-Accessibility.AccessibilityAnnouncements (calls)`
- `Apps-Lillist-iOS-Sources-Detail.TaskDetailView -> Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceSummaryFormatter (calls)`
- `Apps-Lillist-iOS-Sources-Detail.TaskDetailHeader -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.StatusGlyph (calls)`

## Type notes

All six views are SwiftUI value types reading `AppEnvironment` via
`@Environment(AppEnvironment.self)` (`Apps/Lillist-iOS/Sources/Detail/TaskDetailView.swift:18`); none owns a
store. `TaskDetailView` owns the `record`/`seriesRule` state and re-fetches both
in `reload()` (`Apps/Lillist-iOS/Sources/Detail/TaskDetailView.swift:101`); each tab independently re-fetches
its own list in its `.task`/`reload`, so tabs do not share loaded data. Tab selection
survives scene restoration via `@SceneStorage("taskDetailTab")`
(`Apps/Lillist-iOS/Sources/Detail/TaskDetailView.swift:22`). `RecurrenceSheet` seeds its
`RecurrenceEditorViewModel` once in `init` (`Apps/Lillist-iOS/Sources/Detail/RecurrenceSheet.swift:24`)
and treats a nil built rule plus a non-nil `initialSeriesID` as a delete
(`Apps/Lillist-iOS/Sources/Detail/RecurrenceSheet.swift:68`). Store calls are `await`ed inside SwiftUI
`Task {}`/`.task` blocks; writes are fire-and-forget with `try?` then a re-`reload()`
(`Apps/Lillist-iOS/Sources/Detail/TaskSubtasksTab.swift:54`, `Apps/Lillist-iOS/Sources/Detail/TaskJournalTab.swift:66`).

## External deps

- SwiftUI — all views, `@SceneStorage`, `@FocusState`, `ScrollViewReader`, sheets

## Gotchas

- `TaskNotesTab` overlays a `Text` behind `TextEditor` for a placeholder — TextEditor has no built-in placeholder (`Apps/Lillist-iOS/Sources/Detail/TaskNotesTab.swift:22`).
- Notes saves debounce through a cancellable `.task(id: text)` 500ms sleep keyed on `debounceMilliseconds`, so only the last keystroke in a burst reaches Core Data/CloudKit (`Apps/Lillist-iOS/Sources/Detail/TaskNotesTab.swift:54`); a focus-loss save flushes on segment switch (`Apps/Lillist-iOS/Sources/Detail/TaskNotesTab.swift:63`).
