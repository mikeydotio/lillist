---
module: Apps/Lillist-macOS/Sources/Views/TaskList
summary: "macOS task-list pane — outline/flat rendering, drag-reorder, inline create, status cycling"
read_when: "macOS task-list pane"
sources:
  - path: Apps/Lillist-macOS/Sources/Views/TaskList/InlineCreateField.swift
    blob: d737387de165974c77a26ca89529a57b51cbed99
  - path: Apps/Lillist-macOS/Sources/Views/TaskList/SelectionAdvance.swift
    blob: 7c6f317dc02fa7336bcd3d01b0bcd21d5caa6f81
  - path: Apps/Lillist-macOS/Sources/Views/TaskList/SourceTitleResolver.swift
    blob: 5cbcc6b0c3e27b91cf341718ef0e77e271657590
  - path: Apps/Lillist-macOS/Sources/Views/TaskList/TaskListHeaderView.swift
    blob: 5a3ae2804869198bed5d951672e40a791fe53a48
  - path: Apps/Lillist-macOS/Sources/Views/TaskList/TaskListSortControl.swift
    blob: ed61e10f26e474710792a98401490c63b52c5ca2
  - path: Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift
    blob: 75e4a8bba6d4c7b421672574112a384c19c30460
  - path: Apps/Lillist-macOS/Sources/Views/TaskList/TaskOutlineNode.swift
    blob: e6b6844fe1d32663306460de539630d0252b07e4
references_modules: [Apps-Lillist-macOS-Sources-Views-Sidebar, Apps-Lillist-macOS-Sources-misc, Apps-Lillist-macOS-Sources-Commands, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Model, Packages-LillistCore-Sources-LillistCore-Ordering, Packages-LillistUI-Sources-LillistUI-DragReorder, Packages-LillistUI-Sources-LillistUI-Components, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
---

# Module: Apps/Lillist-macOS/Sources/Views/TaskList

## Purpose

The center pane of the macOS three-column shell: it renders the tasks for whatever
`SidebarSelection` is active, either as a hierarchical `OutlineGroup` (tags, pinned
tasks) or a flat breadcrumbed list (filters, trash). `TaskListView` is the only
stateful piece; everything else here is a pure helper or presentation-only view
deliberately lifted out so it can be unit/snapshot-tested without `AppEnvironment`
or SwiftUI. It is the macOS home for the read-write task surface — drag-reorder,
status cycling, and inline create all funnel through `env.taskStore`.

## Public API

All symbols are file-internal (no `public`); the module's "surface" is `TaskListView`,
which the macOS shell instantiates. Other types are intra-target collaborators.

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `InlineCreateField` | struct | `Apps/Lillist-macOS/Sources/Views/TaskList/InlineCreateField.swift:6` | Presentation-only text field; owner supplies Return/Tab/Shift-Tab/Cancel closures |
| `SelectionAdvance` | enum | `Apps/Lillist-macOS/Sources/Views/TaskList/SelectionAdvance.swift:13` | `advance(current:ordered:direction:)` pure ±1 cursor math, clamped |
| `SourceTitleResolver` | enum | `Apps/Lillist-macOS/Sources/Views/TaskList/SourceTitleResolver.swift:14` | `resolve(...)` maps a selection to its user-facing title, with kind fallback |
| `TaskListHeaderView` | struct | `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListHeaderView.swift:4` | Renders `title` + task `count` header row |
| `TaskListSortControl` | struct | `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListSortControl.swift:4` | Sort menu bound to `SortField` + `ascending`; tapping active field toggles direction |
| `TaskListView` | struct | `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift:5` | Center-pane view; renders selection's tasks, owns refresh/drag/create/status flows |
| `TaskOutlineNode` | struct | `Apps/Lillist-macOS/Sources/Views/TaskList/TaskOutlineNode.swift:4` | Identifiable/Hashable tree node wrapping a `TaskRecord`; identity is `id` only |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `refresh` | func | `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift:295` | Single re-query path; every mutation calls it to repopulate `rootNodes`/`flatResults` |
| `buildTree` | func | `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift:330` | Builds the two-level outline from records + children, ordered via `SiblingOrder` |
| `applyDrop` | func | `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift:263` | Resolves a drop to reorder/reparent/noop and commits it to the task store |
| `cycle` | func | `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift:347` | Status-click/space handler; routes through `StatusCycler` then transitions |
| `setStatus` | func | `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift:355` | Direct status set from the row menu; transitions then refreshes |
| `syncDragControllerInputs` | func | `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift:230` | Feeds flattened rows + sort mode into the `DragController` on appear/change |

## Relationships

- `Apps-Lillist-macOS-Sources-Views-TaskList.TaskListView -> Apps-Lillist-macOS-Sources-Views-Sidebar.SidebarSelection (reads)`
- `Apps-Lillist-macOS-Sources-Views-TaskList.SourceTitleResolver -> Apps-Lillist-macOS-Sources-Views-Sidebar.SidebarSelection (reads)`
- `Apps-Lillist-macOS-Sources-Views-TaskList.TaskListView -> Apps-Lillist-macOS-Sources-misc.AppEnvironment (reads)`
- `Apps-Lillist-macOS-Sources-Views-TaskList.TaskListView -> Apps-Lillist-macOS-Sources-misc.UIStatePersistence (reads)`
- `Apps-Lillist-macOS-Sources-Views-TaskList.TaskListView -> Apps-Lillist-macOS-Sources-Commands.lillistNewTask (reads)`
- `Apps-Lillist-macOS-Sources-Views-TaskList.TaskListView -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TaskStore (calls)`
- `Apps-Lillist-macOS-Sources-Views-TaskList.SourceTitleResolver -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SmartFilterStore (calls)`
- `Apps-Lillist-macOS-Sources-Views-TaskList.TaskOutlineNode -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TaskStore (owns)`
- `Apps-Lillist-macOS-Sources-Views-TaskList.TaskListSortControl -> Packages-LillistCore-Sources-LillistCore-Model.SortField (reads)`
- `Apps-Lillist-macOS-Sources-Views-TaskList.buildTree -> Packages-LillistCore-Sources-LillistCore-Ordering.SiblingOrder (calls)`
- `Apps-Lillist-macOS-Sources-Views-TaskList.applyDrop -> Packages-LillistUI-Sources-LillistUI-DragReorder.DragDropResolver (calls)`
- `Apps-Lillist-macOS-Sources-Views-TaskList.TaskListView -> Packages-LillistUI-Sources-LillistUI-DragReorder.DragController (owns)`
- `Apps-Lillist-macOS-Sources-Views-TaskList.cycle -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.StatusPalette (reads)`
- `Apps-Lillist-macOS-Sources-Views-TaskList.TaskListView -> Packages-LillistUI-Sources-LillistUI-Components.TaskRowView (calls)`

## Type notes

`TaskListView` is a `@MainActor` SwiftUI view that owns all module state: `rootNodes`
(outline mode), `flatResults` (flat mode), and a `@StateObject DragController`.
Exactly one of `rootNodes`/`flatResults` is populated per `refresh()` — `isFlat`
(`TaskListView.swift:35`) selects the branch by selection kind. `applyDrop`
(`TaskListView.swift:262`) is explicitly `@MainActor`; drop, create, and status
mutations all `await env.taskStore` then re-`refresh()`. `SourceTitleResolver` and
`SelectionAdvance` are deliberately SwiftUI-free `enum`s of static methods so the
standalone macOS test bundle can exercise them without `AppEnvironment`. Inline
create remembers its parent via `inlineCreateParent`, set by the `.lillistNewSibling`
notification handler (`TaskListView.swift:220`). `TaskOutlineNode` equality/hash key
off `id` alone (`TaskOutlineNode.swift:9`), so two nodes with the same id but
differing children compare equal.

## External deps

- SwiftUI — `View`s, `OutlineGroup`, `List(selection:)`, `@FocusState`, `.onKeyPress`
- LillistCore — `TaskStore`/`SmartFilterStore`/`TagStore`, `TaskRecord`, `Status`, `SortField`, `SiblingOrder`
- LillistUI — `TaskRowView`, `BreadcrumbView`, `EmptyStateView`, drag-reorder stack, glass/rainbow theme

## Gotchas

- Tab is passed through (`.ignored`) when the inline field is empty so focus can leave it (`Apps/Lillist-macOS/Sources/Views/TaskList/InlineCreateField.swift:43`).
- Arrow-key list navigation relies on SwiftUI's built-in `List(selection:)` focus; `SelectionAdvance` exists as a documented fallback if that default changes (`Apps/Lillist-macOS/Sources/Views/TaskList/SelectionAdvance.swift:8`).
- A failed reorder surfaces a transient toast via `reorderFailed`, auto-dismissed after a sleep (`Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift:185`).
