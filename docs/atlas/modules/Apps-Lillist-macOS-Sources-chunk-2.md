---
module: "Apps/Lillist-macOS/Sources (chunk 2)"
summary: "macOS status-bar Today popover and main task-list container with filter/sort/drag/editor lifecycle"
read_when: "Touching macOS status-bar or task list"
sources:
  - path: Apps/Lillist-macOS/Sources/StatusBar/TodayPopoverView.swift
    blob: 90274bef31060bca2bee37d3cd550a68dc1fca93
  - path: Apps/Lillist-macOS/Sources/Tasks/MacTasksView.swift
    blob: da90437a0d59dc3baebfdaac01a195b9aeaec001
references_modules: [Apps-Lillist-macOS-Sources-chunk-1, Packages-LillistCore-Sources-LillistCore-Rules, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistUI-Sources-LillistUI-Components-chunk-1, Packages-LillistUI-Sources-LillistUI-Components-chunk-2, Packages-LillistUI-Sources-LillistUI-DragReorder, Packages-LillistUI-Sources-LillistUI-Editor, Packages-LillistUI-Sources-LillistUI-Recurrence, Packages-LillistUI-Sources-LillistUI-Settings, Packages-LillistUI-Sources-LillistUI-Status, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1, Packages-LillistUI-Sources-LillistUI-iOS-Tasks, Packages-LillistUI-Sources-LillistUI-iOS-misc]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Apps/Lillist-macOS/Sources (chunk 2)

## Purpose

This chunk provides the two primary macOS task surfaces: `TodayPopoverView` (a compact status-bar popover showing today's tasks) and `MacTasksView` (the full main-window task list). `MacTasksView` is the macOS analogue of the iOS TasksView — it owns the complete filter, sort, drag-drop, archive, and editor lifecycle while delegating rendering to the shared `LillistUI.TasksScreen`. Without this chunk the macOS app has no task-list UI and no status-bar Today widget.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `MacTasksView` | struct | `Apps/Lillist-macOS/Sources/Tasks/MacTasksView.swift:21` | macOS main task-list screen; owns filter/sort/drag/archive/editor lifecycle and delegates all rendering to TasksScreen. |
| `TodayPopoverView` | struct | `Apps/Lillist-macOS/Sources/StatusBar/TodayPopoverView.swift:6` | Renders today's tasks in a fixed 320×360 popover; auto-reloads on NSManagedObjectContextDidSave notifications. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `applyDrop` | func | `Apps/Lillist-macOS/Sources/Tasks/MacTasksView.swift:335` | Single gateway for all drag-drop mutations in the macOS list; dispatches to TaskStore.reorder or TaskStore.reparent based on DragDropResolver output and surfaces toast on error. |
| `buildActivePredicateGroup` | func | `Apps/Lillist-macOS/Sources/Tasks/MacTasksView.swift:239` | Composes the active PredicateGroup from quick tokens, saved filters, and search text; every reload feeds through this, so filter parity with the iOS container depends on it being kept in sync. |
| `cycle` | func | `Apps/Lillist-macOS/Sources/Tasks/MacTasksView.swift:356` | Computes the next status via StatusCycler.nextOnClick then delegates to setStatus; the entire tap-to-cycle UX path flows through it. |
| `initialLoad` | func | `Apps/Lillist-macOS/Sources/Tasks/MacTasksView.swift:189` | Startup sequence gate: normalizes sibling ordering, loads saved filters, then triggers the first reload; called once from .task so skipping it leaves the list empty on launch. |
| `load` | func | `Apps/Lillist-macOS/Sources/StatusBar/TodayPopoverView.swift:43` | Fetches today's tasks by evaluating the built-in 'Today' smart filter; the entire popover content depends on it — a failure silently empties the list rather than crashing. |
| `loadSavedFilters` | func | `Apps/Lillist-macOS/Sources/Tasks/MacTasksView.swift:195` | Fetches and normalizes saved smart filters; populates the pinned filter chip bar — a failure here is silently swallowed so the main list still loads. |
| `performRefreshArchive` | func | `Apps/Lillist-macOS/Sources/Tasks/MacTasksView.swift:301` | Archives all closed tasks on pull-to-refresh and records the batch IDs for undo; coordinates the three-state archive+toast+undo flow that `undoArchive` reverses. |
| `reload` | func | `Apps/Lillist-macOS/Sources/Tasks/MacTasksView.swift:211` | Re-evaluates the active predicate group and updates `records` inside a withAnimation transaction; every list change — sort, filter, search, mutation — funnels through it. |
| `setStatus` | func | `Apps/Lillist-macOS/Sources/StatusBar/TodayPopoverView.swift:52` | The sole mutation path in TodayPopoverView: routes status changes to TaskStore.transition then triggers a reload; without it status taps in the popover have no effect. |
| `setStatus` | func | `Apps/Lillist-macOS/Sources/Tasks/MacTasksView.swift:363` | Writes status transitions to TaskStore and surfaces errors as a transient toast (never silently swallowed, per RCA comment at line 362); the authoritative status-mutation path in MacTasksView. |
| `undoArchive` | func | `Apps/Lillist-macOS/Sources/Tasks/MacTasksView.swift:319` | Restores the last archived batch via TaskStore.unarchive and clears the toast state; the only undo path for pull-to-refresh archive in the macOS list. |

## Relationships

- `Apps-Lillist-macOS-Sources-chunk-2.MacTasksView -> Apps-Lillist-macOS-Sources-chunk-1.MacTaskEditorHost (calls)`
- `Apps-Lillist-macOS-Sources-chunk-2.MacTasksView -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.softDelete (writes)`
- `Apps-Lillist-macOS-Sources-chunk-2.MacTasksView -> Packages-LillistUI-Sources-LillistUI-DragReorder.DragController (owns)`
- `Apps-Lillist-macOS-Sources-chunk-2.MacTasksView -> Packages-LillistUI-Sources-LillistUI-Editor.Stores (calls)`
- `Apps-Lillist-macOS-Sources-chunk-2.MacTasksView -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (calls)`
- `Apps-Lillist-macOS-Sources-chunk-2.MacTasksView -> Packages-LillistUI-Sources-LillistUI-iOS-Tasks.SavedFilterChipSpec (calls)`
- `Apps-Lillist-macOS-Sources-chunk-2.MacTasksView -> Packages-LillistUI-Sources-LillistUI-iOS-misc.FloatingAddButton (calls)`
- `Apps-Lillist-macOS-Sources-chunk-2.MacTasksView -> Packages-LillistUI-Sources-LillistUI-iOS-misc.TasksScreen (calls)`
- `Apps-Lillist-macOS-Sources-chunk-2.TodayPopoverView -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1.rainbowCard (calls)`
- `Apps-Lillist-macOS-Sources-chunk-2.TodayPopoverView -> Packages-LillistUI-Sources-LillistUI-Components-chunk-2.TaskRowView (calls)`
- `Apps-Lillist-macOS-Sources-chunk-2.TodayPopoverView -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (calls)`
- `Apps-Lillist-macOS-Sources-chunk-2.TodayPopoverView -> Packages-LillistUI-Sources-LillistUI-Status.nextOnClick (calls)`
- `Apps-Lillist-macOS-Sources-chunk-2.TodayPopoverView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.color (reads)`
- `Apps-Lillist-macOS-Sources-chunk-2.buildActivePredicateGroup -> Packages-LillistCore-Sources-LillistCore-Rules.Leaf (calls)`
- `Apps-Lillist-macOS-Sources-chunk-2.buildActivePredicateGroup -> Packages-LillistCore-Sources-LillistCore-Rules.PredicateGroup (calls)`
- `Apps-Lillist-macOS-Sources-chunk-2.buildActivePredicateGroup -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Apps-Lillist-macOS-Sources-chunk-2.cycle -> Packages-LillistUI-Sources-LillistUI-Status.nextOnClick (calls)`
- `Apps-Lillist-macOS-Sources-chunk-2.initialLoad -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.normalizeSiblingsIfDegenerate (writes)`
- `Apps-Lillist-macOS-Sources-chunk-2.loadSavedFilters -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.normalizeIfDegenerate (writes)`
- `Apps-Lillist-macOS-Sources-chunk-2.performRefreshArchive -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.archive (writes)`
- `Apps-Lillist-macOS-Sources-chunk-2.reload -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.easeOut (calls)`
- `Apps-Lillist-macOS-Sources-chunk-2.setStatus -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.transition (writes)`
- `Apps-Lillist-macOS-Sources-chunk-2.undoArchive -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.unarchive (writes)`

## Type notes

Both views read `AppEnvironment` via `@Environment(AppEnvironment.self)` (Apps/Lillist-macOS/Sources/StatusBar/TodayPopoverView.swift:7, Apps/Lillist-macOS/Sources/Tasks/MacTasksView.swift:22). `MacTasksView` holds `DragController` as `@StateObject` (line 45), giving it exclusive ownership of that controller's lifetime. `applyDrop` is marked `@MainActor` (line 334) even though the surrounding `View` already runs on the main actor — an explicit annotation guarding against isolation drift. The `searchDebounceTask` at line 38 is a nullable `Task<Void, Never>` that is cancelled and replaced on each keystroke, providing 250 ms debounce without a Combine pipeline.

## External deps

- CoreData — imported
- LillistCore — imported
- LillistUI — imported
- SwiftUI — imported

## Gotchas

MacTasksView suppresses the row-insertion animation on the very first populate via `hasLoadedOnce` (Apps/Lillist-macOS/Sources/Tasks/MacTasksView.swift:43); every subsequent reload animates the diff. `setStatus` in MacTasksView never swallows transition errors — they surface as a transient status toast, documented by a 2026-06-12 RCA comment at Apps/Lillist-macOS/Sources/Tasks/MacTasksView.swift:362.
