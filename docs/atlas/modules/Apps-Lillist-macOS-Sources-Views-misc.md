---
module: "Apps/Lillist-macOS/Sources/Views (misc)"
summary: "macOS three-column NavigationSplitView root that wires sidebar/list/detail and the window toolbar"
read_when: "macOS root window layout"
sources:
  - path: Apps/Lillist-macOS/Sources/Views/RootSplitView.swift
    blob: 127b3aa7429518c3a0e1f48c90ff38b29aade3bb
  - path: Apps/Lillist-macOS/Sources/Views/EmptyView/NoSelectionDetailView.swift
    blob: 7a17e59fd6aa447a08fc1b732b1d52154bb4b598
references_modules: [Apps-Lillist-macOS-Sources-misc, Apps-Lillist-macOS-Sources-Views-Sidebar, Apps-Lillist-macOS-Sources-Views-TaskList, Apps-Lillist-macOS-Sources-Views-Detail, Apps-Lillist-macOS-Sources-Commands, Packages-LillistUI-Sources-LillistUI-Components]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
---

# Module: Apps/Lillist-macOS/Sources/Views (misc)

## Purpose

The top-level macOS window body. `RootSplitView` is the single `NavigationSplitView`
that composes the three primary columns (sidebar / task list / detail) and owns the
window toolbar — source-title principal, sidebar toggle, New-Task button, sort control,
and sync dot. It is the macOS app's central selection-state hub: it holds and persists
`sidebarSelection` and `taskSelection`, and translates command-menu / hotkey notifications
into selection and status mutations. `NoSelectionDetailView` is the detail-column
placeholder shown when no task is selected.

## Public API

Both types are internal SwiftUI `View` structs (no `public` modifier); they are the
app target's window composition surface, not a cross-package API.

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `NoSelectionDetailView` | struct | `Apps/Lillist-macOS/Sources/Views/EmptyView/NoSelectionDetailView.swift:4` | Detail-column empty state shown when `taskSelection` is nil |
| `RootSplitView` | struct | `Apps/Lillist-macOS/Sources/Views/RootSplitView.swift:5` | Root window body; the macOS app's selection-state hub and toolbar host |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `toggleSidebar` | func | `Apps/Lillist-macOS/Sources/Views/RootSplitView.swift:224` | Single sidebar collapse path; shared by toolbar button and the `lillistToggleSidebar` command |
| `pruneStaleSidebarSelectionIfNeeded` | func | `Apps/Lillist-macOS/Sources/Views/RootSplitView.swift:139` | On launch, clears `sidebarSelection` whose record was deleted (CloudKit/CLI) — one store fetch, no scan |
| `refreshPrincipalTitle` | func | `Apps/Lillist-macOS/Sources/Views/RootSplitView.swift:158` | Resolves the toolbar principal title from the selection via `SourceTitleResolver` |
| `parseVisibility` | func | `Apps/Lillist-macOS/Sources/Views/RootSplitView.swift:24` | Decodes the `@SceneStorage` column-visibility string into `NavigationSplitViewVisibility` |
| `encodeVisibility` | func | `Apps/Lillist-macOS/Sources/Views/RootSplitView.swift:32` | Encodes column visibility back to the persisted scene-storage string |

## Relationships

- `Apps-Lillist-macOS-Sources-misc.LillistApp -> Apps-Lillist-macOS-Sources-Views-misc.RootSplitView (calls)`
- `Apps-Lillist-macOS-Sources-Views-misc.RootSplitView -> Apps-Lillist-macOS-Sources-misc.AppEnvironment (reads)`
- `Apps-Lillist-macOS-Sources-Views-misc.RootSplitView -> Apps-Lillist-macOS-Sources-misc.UIStatePersistence (writes)`
- `Apps-Lillist-macOS-Sources-Views-misc.RootSplitView -> Apps-Lillist-macOS-Sources-Views-Sidebar.SidebarView (calls)`
- `Apps-Lillist-macOS-Sources-Views-misc.RootSplitView -> Apps-Lillist-macOS-Sources-Views-Sidebar.SidebarSelection (owns)`
- `Apps-Lillist-macOS-Sources-Views-misc.RootSplitView -> Apps-Lillist-macOS-Sources-Views-TaskList.TaskListView (calls)`
- `Apps-Lillist-macOS-Sources-Views-misc.RootSplitView -> Apps-Lillist-macOS-Sources-Views-TaskList.TaskListSortControl (calls)`
- `Apps-Lillist-macOS-Sources-Views-misc.RootSplitView -> Apps-Lillist-macOS-Sources-Views-TaskList.SourceTitleResolver (calls)`
- `Apps-Lillist-macOS-Sources-Views-misc.RootSplitView -> Apps-Lillist-macOS-Sources-Views-Detail.TaskDetailView (calls)`
- `Apps-Lillist-macOS-Sources-Views-misc.RootSplitView -> Apps-Lillist-macOS-Sources-Commands.ListColumn (reads)`
- `Apps-Lillist-macOS-Sources-Views-misc.RootSplitView -> Packages-LillistUI-Sources-LillistUI-Components.SyncStatusDotView (calls)`
- `Apps-Lillist-macOS-Sources-Views-misc.RootSplitView -> Packages-LillistUI-Sources-LillistUI-Components.StatusCycler (calls)`
- `Apps-Lillist-macOS-Sources-Views-misc.NoSelectionDetailView -> Packages-LillistUI-Sources-LillistUI-Components.EmptyStateView (calls)`

## Type notes

`RootSplitView` is `@MainActor` (SwiftUI `View`). Selection lives in `@State`
(`sidebarSelection`, `taskSelection`) and is mirrored into `UIStatePersistence` on every
`onChange`; column visibility is persisted via `@SceneStorage("lillist.ui.columnVisibility")`
as a string round-tripped through `parseVisibility`/`encodeVisibility`. The `init`
seeds `sidebarSelection` from the last-persisted value so the window restores its source
across launches. Command-menu and hotkey actions arrive as `NotificationCenter`
`.lillist*` posts handled in `onReceive`; store mutations (status transitions) are
dispatched in detached `Task`s against `env.taskStore`. The toolbar principal title and
`TaskListView`'s `.navigationTitle` both flow from `SourceTitleResolver`, kept in lockstep.

## External deps

- SwiftUI — `NavigationSplitView`, `ToolbarContent`, `@SceneStorage`, `@FocusState`
- LillistCore — store and DTO types reached through `AppEnvironment` (e.g. `TaskStore`)

## Gotchas

- Binding a toolbar button to `columnVisibility` (rather than relying on the OS-26
  built-in affordance) is deliberate: it persists the user's choice and gives the
  ⌃⌘S menu command a stable target — see `Apps/Lillist-macOS/Sources/Views/RootSplitView.swift:173`.
- The sync dot moved here from a `SidebarView` `safeAreaInset`; the inset block in
  `SidebarView` was deleted in the same change — see `Apps/Lillist-macOS/Sources/Views/RootSplitView.swift:215`.
