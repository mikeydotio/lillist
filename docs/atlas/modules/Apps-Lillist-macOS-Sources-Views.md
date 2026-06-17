---
module: Apps/Lillist-macOS/Sources/Views
summary: "macOS three-column shell — sidebar source list, task outline/flat list, root NavigationSplitView wiring"
read_when: "Touching macOS sidebar or task list"
sources:
  - path: Apps/Lillist-macOS/Sources/Views/RootSplitView.swift
    blob: 652354694da3643b5962a4711ad6bf7fffb7dce8
  - path: Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarSection.swift
    blob: 26e2fea7d1dd00c25de2b07150377bd17e4ff010
  - path: Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarSelection.swift
    blob: 5db8773c57a6a070482eabffcf8c7e8a275432b0
  - path: Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarView.swift
    blob: 0e7d65010a0bc5d8a55b0c447df628ab7867e4d9
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
    blob: 2a2fe450e3a8b6934c1840eb8966bb6d9746c7d6
  - path: Apps/Lillist-macOS/Sources/Views/TaskList/TaskOutlineNode.swift
    blob: e6b6844fe1d32663306460de539630d0252b07e4
references_modules: [Apps-Lillist-macOS-Sources-misc, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistCore-Sources-LillistCore-Model, Packages-LillistCore-Sources-LillistCore-Ordering, Packages-LillistUI-Sources-LillistUI-Components, Packages-LillistUI-Sources-LillistUI-DragReorder, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1, Packages-LillistUI-Sources-LillistUI-Theme-chunk-2, Packages-LillistUI-Sources-LillistUI-misc, Packages-LillistUI-Sources-LillistUI-Sync]
generator: cartographer/1
baseline: 1a1562b636e43ebbdc35c7939ab6989b387f50e9
verified: true
---

# Module: Apps/Lillist-macOS/Sources/Views

## Purpose

This module is the entire visible macOS window: a `NavigationSplitView` rooted at `RootSplitView` drives a sidebar column (source selection) and a content column (task list). The unifying design idea is that `SidebarSelection` is the single value flowing between columns — the sidebar writes it, the task list reads it, and every notification/command handler in `RootSplitView` ultimately routes through it. Removing this module collapses the macOS window to nothing.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `InlineCreateField` | struct (View) | `Apps/Lillist-macOS/Sources/Views/TaskList/InlineCreateField.swift:6` | Callback-driven text field for inline task creation; Return/Tab/Shift-Tab/Escape all route to caller-supplied closures |
| `RootSplitView` | struct (View) | `Apps/Lillist-macOS/Sources/Views/RootSplitView.swift:5` | Top-level macOS window body; owns sidebar/list column split, toolbar, and all notification-driven command routing |
| `SelectionAdvance` | enum | `Apps/Lillist-macOS/Sources/Views/TaskList/SelectionAdvance.swift:13` | Pure index-math for ±1 cursor advance in an ordered ID list; `advance(current:ordered:direction:)` clamps at bounds |
| `SidebarSection` | enum | `Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarSection.swift:3` | Four sidebar groupings (pinned, tags, filters, trash); `title` provides display strings |
| `SidebarSelection` | enum | `Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarSelection.swift:4` | Discriminated union of source kinds (`pinnedTask`, `pinnedFilter`, `tag`, `filter`, `trash`); `Hashable`, `Codable`, `Sendable` |
| `SidebarView` | struct (View) | `Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarView.swift:5` | macOS sidebar list with pinned, tags, filters, and trash sections; exposes `selection: Binding<SidebarSelection?>` |
| `SourceTitleResolver` | enum | `Apps/Lillist-macOS/Sources/Views/TaskList/SourceTitleResolver.swift:14` | Async resolver that maps a `SidebarSelection` to its user-facing name via store fetches; falls back gracefully on deleted records |
| `TaskListHeaderView` | struct (View) | `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListHeaderView.swift:4` | Displays source title + task count in `title2.bold` style |
| `TaskListSortControl` | struct (View) | `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListSortControl.swift:4` | Borderless menu over `SortField.allCases`; toggles ascending on repeat-click of the same field |
| `TaskListView` | struct (View) | `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift:5` | Middle column; switches between hierarchical `OutlineGroup` (tag/pinnedTask) and flat `List` (filter/trash) based on selection kind |
| `TaskOutlineNode` | struct | `Apps/Lillist-macOS/Sources/Views/TaskList/TaskOutlineNode.swift:4` | Tree node wrapping `TaskStore.TaskRecord`; `children: [TaskOutlineNode]?` drives `OutlineGroup`; identity and equality by `id` |

## Load-bearing internals

| Symbol | Location | Why it matters |
| --- | --- | --- |
| `SidebarView.refresh()` | `Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarView.swift:121` | Single async method that reloads all sidebar sections from three stores; all mutation callbacks call it to keep the sidebar live |
| `TaskListView.refresh()` | `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift:308` | Dispatches to the correct store API (filter evaluate, tag tree, trash, pinnedTask) based on `SidebarSelection`; populates `rootNodes` vs `flatResults` |
| `TaskListView.buildTree(from:)` | `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift:343` | Fetches children per task record and assembles `TaskOutlineNode` tree sorted by `SiblingOrder.precedes`; bridges flat store records to `OutlineGroup` |
| `TaskListView.applyDrop(dragged:target:)` | `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift:276` | `@MainActor` drop handler; resolves `DragTarget` to reorder/reparent/noop via `DragDropResolver` then calls `TaskStore.reorder` or `TaskStore.reparent` |
| `TaskListView.setStatus(_:to:)` | `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift:368` | Calls `taskStore.transition` then refreshes; used by every `TaskRowView` status callback in both outline and flat list branches |
| `RootSplitView.pruneStaleSidebarSelectionIfNeeded()` | `Apps/Lillist-macOS/Sources/Views/RootSplitView.swift:145` | On appear, verifies the persisted selection's UUID still exists in its store; clears stale selection from inter-launch CloudKit deletions |
| `TagDisclosureView` (private) | `Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarView.swift:135` | Recursive `DisclosureGroup` for nested tags; each instance fetches its own children via `tagStore.children(of:)` on `.task` |

## Relationships

- `Apps-Lillist-macOS-Sources-Views.RootSplitView -> Apps-Lillist-macOS-Sources-misc.AppEnvironment (reads)` — `@Environment(AppEnvironment.self)` at `Apps/Lillist-macOS/Sources/Views/RootSplitView.swift:6`
- `Apps-Lillist-macOS-Sources-Views.RootSplitView -> Apps-Lillist-macOS-Sources-misc.UIStatePersistence (reads)` — `@State private var uiState = UIStatePersistence()` at `Apps/Lillist-macOS/Sources/Views/RootSplitView.swift:9`
- `Apps-Lillist-macOS-Sources-Views.RootSplitView -> Apps-Lillist-macOS-Sources-misc.StatusCycler (calls)` — `StatusCycler.nextOnSpace(from:)` at `Apps/Lillist-macOS/Sources/Views/RootSplitView.swift:92`
- `Apps-Lillist-macOS-Sources-Views.TaskListView -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (calls)` — `env.taskStore.tasks(forTag:...)`, `.reorder`, `.reparent`, `.create` throughout `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift`
- `Apps-Lillist-macOS-Sources-Views.TaskListView -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SmartFilterStore (calls)` — `env.smartFilterStore.evaluate(id:)` at `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift:312`
- `Apps-Lillist-macOS-Sources-Views.TaskListView -> Packages-LillistCore-Sources-LillistCore-Model.SortField (reads)` — `SortField` binding drives sort at `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift:11`
- `Apps-Lillist-macOS-Sources-Views.TaskListView -> Packages-LillistCore-Sources-LillistCore-Ordering.SiblingOrder (calls)` — `SiblingOrder.precedes` in `buildTree` at `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift:347`
- `Apps-Lillist-macOS-Sources-Views.TaskListView -> Packages-LillistUI-Sources-LillistUI-DragReorder.DragController (owns)` — `@StateObject private var dragController = DragController()` at `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift:22`
- `Apps-Lillist-macOS-Sources-Views.TaskListView -> Packages-LillistUI-Sources-LillistUI-DragReorder.DragDropResolver (calls)` — `DragDropResolver.resolve(target:flatRows:)` at `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift:278`
- `Apps-Lillist-macOS-Sources-Views.TaskListView -> Packages-LillistUI-Sources-LillistUI-Components.TaskRowView (owns)` — used in both flat and outline list branches throughout `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift`
- `Apps-Lillist-macOS-Sources-Views.TaskListView -> Packages-LillistUI-Sources-LillistUI-misc.StatusPalette (calls)` — `StatusPalette.color(for:)` at `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift:88`
- `Apps-Lillist-macOS-Sources-Views.TaskListView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.LillistColor (reads)` — `.background(LillistColor.workspace)` at `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift:102`
- `Apps-Lillist-macOS-Sources-Views.InlineCreateField -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.LillistColor (reads)` — `LillistColor.borderHair` at `Apps/Lillist-macOS/Sources/Views/TaskList/InlineCreateField.swift:31`
- `Apps-Lillist-macOS-Sources-Views.InlineCreateField -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-2.LillistRadius (reads)` — `LillistRadius.m` at `Apps/Lillist-macOS/Sources/Views/TaskList/InlineCreateField.swift:25`
- `Apps-Lillist-macOS-Sources-Views.SidebarView -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SmartFilterStore (calls)` — `env.smartFilterStore.list()`, `.delete`, `.update` throughout `Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarView.swift`
- `Apps-Lillist-macOS-Sources-Views.SidebarView -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TagStore (calls)` — `env.tagStore.children(of:)`, `.rename`, `.setTintColor`, `.delete` at `Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarView.swift:127`
- `Apps-Lillist-macOS-Sources-Views.RootSplitView -> Packages-LillistUI-Sources-LillistUI-Sync.SyncStatusDotView (owns)` — toolbar `.status` item at `Apps/Lillist-macOS/Sources/Views/RootSplitView.swift:224`
- `Apps-Lillist-macOS-Sources-Views.SourceTitleResolver -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (calls)` — `taskStore.fetch(id:)` at `Apps/Lillist-macOS/Sources/Views/TaskList/SourceTitleResolver.swift:23`
- `Apps-Lillist-macOS-Sources-Views.SourceTitleResolver -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SmartFilterStore (calls)` — `smartFilterStore.list()` at `Apps/Lillist-macOS/Sources/Views/TaskList/SourceTitleResolver.swift:25`
- `Apps-Lillist-macOS-Sources-Views.SourceTitleResolver -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TagStore (calls)` — `tagStore.fetch(id:)` at `Apps/Lillist-macOS/Sources/Views/TaskList/SourceTitleResolver.swift:29`

## Type notes

`SidebarSelection` is `Codable` so `UIStatePersistence` can round-trip it across launches. The `RootSplitView.init()` immediately reads the persisted value to initialize `@State` before the view appears, avoiding a flash-to-nil on launch (`Apps/Lillist-macOS/Sources/Views/RootSplitView.swift:41`).

`TaskListView` uses `isFlat: Bool` (computed from the selection kind) as the architectural branch point: filter and trash selections produce a flat `[TaskStore.TaskRecord]` list; tag and pinnedTask selections produce a `[TaskOutlineNode]` tree for `OutlineGroup`. The two branches share `TaskRowView` but differ in drag-reorder (outline only) and breadcrumb display (flat only).

`TaskOutlineNode` equality is by `id` only (`Apps/Lillist-macOS/Sources/Views/TaskList/TaskOutlineNode.swift:9`) — SwiftUI change detection will not re-render children whose parent node's record mutated but whose ID is the same. Call `refresh()` after any mutation.

The `@retroactive Identifiable` extensions on `TaskStore.TaskRecord`, `SmartFilterStore.SmartFilterRecord`, and `TagStore.TagRecord` at `Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarView.swift:273–275` are the minimum required by `.sheet(item:)` and are confined to this file to avoid polluting other call sites.

`RootSplitView` uses `@SceneStorage` (not `@AppStorage`) for column visibility so each window scene gets its own persisted value (`Apps/Lillist-macOS/Sources/Views/RootSplitView.swift:12`).

## External deps

- SwiftUI — `NavigationSplitView`, `OutlineGroup`, `List(selection:)`, `@FocusState`, `@SceneStorage`, `DisclosureGroup`
- Foundation — `NotificationCenter`, `UUID`, `Codable`

## Gotchas

- The detail column is intentionally retired: `RootSplitView` is a two-column split (`sidebar + detail`), with the "detail" slot housing `TaskListView`. A comment at `Apps/Lillist-macOS/Sources/Views/RootSplitView.swift:61` explains that clicking a row opens the floating `openTaskEditorAction` instead of a docked pane; `taskSelection` only drives list highlight.
- `SelectionAdvance` exists for documentation and regression-test coverage of arrow-key behavior that SwiftUI now handles natively — see `Apps/Lillist-macOS/Sources/Views/TaskList/SelectionAdvance.swift:6`. If SwiftUI regresses, wire `advance(...)` via `.onKeyPress` on the list.
- Tab in `InlineCreateField` is swallowed only when the field is non-empty; an empty field lets Tab escape focus — intentional escape hatch noted at `Apps/Lillist-macOS/Sources/Views/TaskList/InlineCreateField.swift:43`.
- `SidebarView.refresh()` silently swallows store errors at `Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarView.swift:129`; a future banner is noted in the comment but not yet implemented.
