---
module: Apps/Lillist-macOS/Sources/Views/Sidebar
summary: "macOS sidebar source list — pinned items, tag tree, filters, trash, with inline rename/recolor editors"
read_when: macOS sidebar source list
sources:
  - path: Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarSection.swift
    blob: 26e2fea7d1dd00c25de2b07150377bd17e4ff010
  - path: Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarSelection.swift
    blob: 5db8773c57a6a070482eabffcf8c7e8a275432b0
  - path: Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarView.swift
    blob: 0e7d65010a0bc5d8a55b0c447df628ab7867e4d9
references_modules: [Apps-Lillist-macOS-Sources-misc, Apps-Lillist-macOS-Sources-Views-misc, Apps-Lillist-macOS-Sources-Views-TaskList, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistUI-Sources-LillistUI-Components, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
---

# Module: Apps/Lillist-macOS/Sources/Views/Sidebar

## Purpose

The leading column of the macOS three-pane shell: a `List` of pinned tasks/filters,
a recursive tag tree, smart filters, and trash. Its selection (`SidebarSelection`)
is the single source of truth that drives the middle (task-list) column. The view
owns no persistence — it reads value-type records from `AppEnvironment`'s stores on
`.task` and after every mutation, and surfaces inline rename/recolor editors as sheets.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `SidebarSection` | enum | `Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarSection.swift:3` | Identifiable section descriptor (pinned/tags/filters/trash) with display `title` |
| `SidebarSelection` | enum | `Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarSelection.swift:4` | `Codable`/`Sendable` selection token bound across panes; persisted and pruned downstream |
| `SidebarView` | struct | `Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarView.swift:5` | Sidebar pane; takes `@Binding var selection: SidebarSelection?` |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `refresh` | func | `Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarView.swift:121` | Sole data-load path; re-pulls pinned/filters/tags/trash from stores on appear and after each edit |
| `TagDisclosureView` | struct | `Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarView.swift:135` | Recursive disclosure row rendering the nested tag tree; lazily loads children per node |
| `RenameSheet` | struct | `Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarView.swift:193` | Shared text-edit sheet for renaming tasks, filters, and tags; trims and no-ops unchanged input |
| `TagColorSheet` | struct | `Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarView.swift:235` | `ColorPicker` sheet that round-trips a tag tint through hex |

## Relationships

- `Apps-Lillist-macOS-Sources-Views-Sidebar.SidebarView -> Apps-Lillist-macOS-Sources-misc.AppEnvironment (reads)`
- `Apps-Lillist-macOS-Sources-Views-Sidebar.SidebarView -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (calls)`
- `Apps-Lillist-macOS-Sources-Views-Sidebar.SidebarView -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SmartFilterStore (calls)`
- `Apps-Lillist-macOS-Sources-Views-Sidebar.SidebarView -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TagStore (calls)`
- `Apps-Lillist-macOS-Sources-Views-Sidebar.SidebarView -> Packages-LillistUI-Sources-LillistUI-Components.SidebarRowView (calls)`
- `Apps-Lillist-macOS-Sources-Views-Sidebar.TagDisclosureView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.TagTint (calls)`
- `Apps-Lillist-macOS-Sources-Views-Sidebar.TaskRecord -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskRecord (extends)`
- `Apps-Lillist-macOS-Sources-Views-Sidebar.SmartFilterRecord -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SmartFilterRecord (extends)`
- `Apps-Lillist-macOS-Sources-Views-Sidebar.TagRecord -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TagRecord (extends)`
- `Apps-Lillist-macOS-Sources-Views-misc.RootSplitView -> Apps-Lillist-macOS-Sources-Views-Sidebar.SidebarView (calls)`
- `Apps-Lillist-macOS-Sources-Views-TaskList.TaskListView -> Apps-Lillist-macOS-Sources-Views-Sidebar.SidebarSelection (reads)`
- `Apps-Lillist-macOS-Sources-misc.UIStatePersistence -> Apps-Lillist-macOS-Sources-Views-Sidebar.SidebarSelection (reads)`

## Type notes

`SidebarView` holds no model of its own — all displayed collections are `@State`
caches refilled by `refresh` (`Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarView.swift:121`)
from `AppEnvironment` stores; a thrown store error silently leaves the cache empty.
`SidebarSelection` is `Codable` precisely so it can be persisted and later
pruned by the app target (`Apps/Lillist-macOS/Sources/Persistence/UIStatePersistence.swift:21`).
`@retroactive Identifiable` conformances on the three LillistCore record types
(`Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarView.swift:273`) exist only to
satisfy `.sheet(item:)`; they lean on the records' stable UUIDs.
Tag children load lazily per `TagDisclosureView` node's own `.task`
(`Apps/Lillist-macOS/Sources/Views/Sidebar/SidebarView.swift:185`), so deep trees
fetch on expansion rather than up front.

## External deps

- SwiftUI — `List(selection:)`, `DisclosureGroup`, `.sheet(item:)`, `ColorPicker`
