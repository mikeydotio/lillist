---
module: Apps/Lillist-macOS/Sources/Views/Detail
summary: "macOS task-detail Form pane and its inline editors (title, dates, recurrence, follow-up, notes, subtasks, journal)"
read_when: macOS task detail pane
sources:
  - path: Apps/Lillist-macOS/Sources/Views/Detail/DetailHeaderView.swift
    blob: 5de5be34439b88cbb1ad0ba850e70199a0959ff6
  - path: Apps/Lillist-macOS/Sources/Views/Detail/FollowUpFormView.swift
    blob: d648bfcd629adb838df1d78d0819d4ec47b4cfca
  - path: Apps/Lillist-macOS/Sources/Views/Detail/JournalComposerView.swift
    blob: 010d724129556fa2e8d1f5f449a291e11b7ab34a
  - path: Apps/Lillist-macOS/Sources/Views/Detail/JournalStreamView.swift
    blob: 8c64ba29db2604a294772244d0cc3c4e4cf1376d
  - path: Apps/Lillist-macOS/Sources/Views/Detail/NotesEditorView.swift
    blob: a20d2375ac4dd7aec0ae590f89fa3ba2bffece17
  - path: Apps/Lillist-macOS/Sources/Views/Detail/SubtaskOutlineView.swift
    blob: 955653f882179b64cfe641ffe0a97f7a99b6be2c
  - path: Apps/Lillist-macOS/Sources/Views/Detail/TaskDetailView.swift
    blob: 516c5a0597af15b1e7491d4c41ee7fcf644a3f97
references_modules: [Apps-Lillist-macOS-Sources-misc, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistUI-Sources-LillistUI-Components, Packages-LillistUI-Sources-LillistUI-Recurrence, Packages-LillistUI-Sources-LillistUI-Accessibility]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
---

# Module: Apps/Lillist-macOS/Sources/Views/Detail

## Purpose

The macOS detail pane for a single task: a grouped `Form` whose sections each
edit one facet (title/status, dates, recurrence, follow-up, notes, subtasks,
journal). `TaskDetailView` is the composition root — it owns the loaded record
and `@State` field mirrors, debounces edits straight into `AppEnvironment`
stores via `.onChange`, and hosts the smaller editor structs as section bodies.
The design is "each editor is a self-contained view that reads/writes its own
slice of the same task through the shared environment," so the pane has no
view-model layer between SwiftUI and the LillistCore stores.

## Public API

All types are `internal` (no module declares `public`); this is an app-target
leaf consumed only by the macOS shell. The table lists the file-level view
structs other macOS views could mount.

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `DetailHeaderView` | struct | `Apps/Lillist-macOS/Sources/Views/Detail/DetailHeaderView.swift:5` | Title/status/tags/date header; bindings + `onStatusMenu` closure injected by caller |
| `FollowUpFormView` | struct | `Apps/Lillist-macOS/Sources/Views/Detail/FollowUpFormView.swift:8` | Inline blocked-task follow-up form; reads `env`, calls back via `onCommit`/`onDismiss` |
| `JournalComposerView` | struct | `Apps/Lillist-macOS/Sources/Views/Detail/JournalComposerView.swift:3` | Note-entry text field; appends via `env.journalStore`, fires `onAdded` |
| `JournalStreamView` | struct | `Apps/Lillist-macOS/Sources/Views/Detail/JournalStreamView.swift:5` | Renders + filters a task's journal entries; self-refreshing on `taskID` change |
| `NotesEditorView` | struct | `Apps/Lillist-macOS/Sources/Views/Detail/NotesEditorView.swift:3` | Markdown notes editor with preview toggle; pure `@Binding<String>`, no env |
| `SubtaskOutlineView` | struct | `Apps/Lillist-macOS/Sources/Views/Detail/SubtaskOutlineView.swift:5` | Child-task list + add field; self-refreshing on `parentID` change |
| `TaskDetailView` | struct | `Apps/Lillist-macOS/Sources/Views/Detail/TaskDetailView.swift:5` | Detail-pane root; takes a `taskID`, composes all editor sections |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `load` | func | `Apps/Lillist-macOS/Sources/Views/Detail/TaskDetailView.swift:119` | Hydrates record + all field mirrors + recurrence VM; re-run after every mutation |
| `transition` | func | `Apps/Lillist-macOS/Sources/Views/Detail/TaskDetailView.swift:135` | Status change; toggles the inline follow-up form when status is `.blocked` |
| `commitRecurrence` | func | `Apps/Lillist-macOS/Sources/Views/Detail/TaskDetailView.swift:141` | Create/update/delete the task's series from the recurrence-editor result |
| `submit` | func | `Apps/Lillist-macOS/Sources/Views/Detail/FollowUpFormView.swift:42` | Calls `scheduleFollowUp`; falls back to a derived title when blank |
| `Filter` | enum | `Apps/Lillist-macOS/Sources/Views/Detail/JournalStreamView.swift:6` | `all`/`attachments` segmented filter backing `filtered` |
| `cycle` | func | `Apps/Lillist-macOS/Sources/Views/Detail/SubtaskOutlineView.swift:46` | Click-advances a subtask's status via `StatusCycler.nextOnClick` |

## Relationships

- `Apps-Lillist-macOS-Sources-Views-Detail.TaskDetailView -> Apps-Lillist-macOS-Sources-misc.AppEnvironment (reads)`
- `Apps-Lillist-macOS-Sources-Views-Detail.TaskDetailView -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TaskStore (calls)`
- `Apps-Lillist-macOS-Sources-Views-Detail.TaskDetailView -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SeriesStore (calls)`
- `Apps-Lillist-macOS-Sources-Views-Detail.TaskDetailView -> Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceEditorView (calls)`
- `Apps-Lillist-macOS-Sources-Views-Detail.TaskDetailView -> Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceEditorViewModel (owns)`
- `Apps-Lillist-macOS-Sources-Views-Detail.TaskDetailView -> Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceSummaryFormatter (calls)`
- `Apps-Lillist-macOS-Sources-Views-Detail.TaskDetailView -> Packages-LillistUI-Sources-LillistUI-Accessibility.AccessibilityAnnouncements (calls)`
- `Apps-Lillist-macOS-Sources-Views-Detail.FollowUpFormView -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TaskStore (calls)`
- `Apps-Lillist-macOS-Sources-Views-Detail.JournalStreamView -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.JournalStore (calls)`
- `Apps-Lillist-macOS-Sources-Views-Detail.JournalStreamView -> Packages-LillistUI-Sources-LillistUI-Components.JournalEntryRow (calls)`
- `Apps-Lillist-macOS-Sources-Views-Detail.JournalComposerView -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.JournalStore (calls)`
- `Apps-Lillist-macOS-Sources-Views-Detail.SubtaskOutlineView -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TaskStore (calls)`
- `Apps-Lillist-macOS-Sources-Views-Detail.SubtaskOutlineView -> Packages-LillistUI-Sources-LillistUI-Components.TaskRowView (calls)`
- `Apps-Lillist-macOS-Sources-Views-Detail.DetailHeaderView -> Packages-LillistUI-Sources-LillistUI-Components.TagChipView (calls)`

## Type notes

`AppEnvironment` is injected through `@Environment(AppEnvironment.self)`
(`Apps/Lillist-macOS/Sources/Views/Detail/TaskDetailView.swift:6`); each editor
view reaches its store through that single `@Observable` root rather than
holding store references itself. `TaskDetailView` is the only stateful owner of
the record — `record`, `title`, `notes`, `start`, `deadline` are mirrors loaded
in `load` and pushed back via the `.onChange` debounce
(`Apps/Lillist-macOS/Sources/Views/Detail/TaskDetailView.swift:68`). The child
editors that mutate (`SubtaskOutlineView`, `JournalStreamView`/`JournalComposerView`,
`FollowUpFormView`) keep their own list state and re-fetch on `.task` / `onChange`,
so they are decoupled from the parent's reload. `TitleRow`
(`Apps/Lillist-macOS/Sources/Views/Detail/TaskDetailView.swift:168`) is a private
nested view, distinct from the standalone `DetailHeaderView`. Views are
`@MainActor` by SwiftUI conformance; all store work hops onto detached `Task`s.
`FollowUpFormView` is shown only while status is `.blocked`, gated in `load`
(`Apps/Lillist-macOS/Sources/Views/Detail/TaskDetailView.swift:126`).

## External deps

- SwiftUI — every view; `Form`, `TextEditor`, `DatePicker`, `Menu`, `.userActivity`
- LillistCore — `TaskStore`/`SeriesStore`/`JournalStore` records, `Status`, `RecurrenceRule`
- LillistUI — recurrence editor, status glyph/palette, journal/tag/task row components

## Gotchas

- Notes preview renders user Markdown via `LocalizedStringKey(markdown)`, flagged
  `i18n-exempt` at `Apps/Lillist-macOS/Sources/Views/Detail/NotesEditorView.swift:21`.
- `TaskDetailView` broadcasts an `NSUserActivity` for Handoff; the iOS reciprocal
  `onContinueUserActivity` is deferred (`Apps/Lillist-macOS/Sources/Views/Detail/TaskDetailView.swift:83`).
- `NotesEditorView` still uses raw padding/radius literals pending design-token
  migration (`Apps/Lillist-macOS/Sources/Views/Detail/NotesEditorView.swift:30`).
