---
module: Packages/LillistUI/Sources/LillistUI/iOS/Tasks
summary: "Pure-presentation pieces of the iOS Tasks screen — outline tree, flat projection, filter header, sort"
read_when: "iOS Tasks outline screen"
sources:
  - path: Packages/LillistUI/Sources/LillistUI/iOS/Tasks/FilterChip.swift
    blob: d9c391dbdee40c9de6196eae330ba7a2398be0c7
  - path: Packages/LillistUI/Sources/LillistUI/iOS/Tasks/FilterHeader.swift
    blob: b3091afc0ea60c53aedb7d03df94d83469dea1cd
  - path: Packages/LillistUI/Sources/LillistUI/iOS/Tasks/FlatTaskRow.swift
    blob: 33960b025a31e092cf601d9a68fb22423cfc7933
  - path: Packages/LillistUI/Sources/LillistUI/iOS/Tasks/TaskOutlineRowView.swift
    blob: 8cb73c03a7c176c7544269aeee5c9847f4cedd6b
  - path: Packages/LillistUI/Sources/LillistUI/iOS/Tasks/TaskTree.swift
    blob: a3e62822968acad7c6d73eccda8e7d4e8b0f70ca
  - path: Packages/LillistUI/Sources/LillistUI/iOS/Tasks/TasksSort.swift
    blob: ec113d2e4e3de800b679902e317ff0b6b6bb8d20
references_modules: [Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Model, Packages-LillistCore-Sources-LillistCore-Ordering, Packages-LillistUI-Sources-LillistUI-Components, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1, Packages-LillistUI-Sources-LillistUI-iOS-misc, Apps-Lillist-iOS-Sources-misc]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
---

# Module: Packages/LillistUI/Sources/LillistUI/iOS/Tasks

## Purpose

The reusable, stateless building blocks of the iOS Tasks screen. It turns a flat
`[TaskStore.TaskRecord]` list into a collapsible outline (`TaskTree` ->
`TreeFlattener` -> rows) and supplies the expanding filter header above it. Every
type here is pure presentation or pure data transform — all `@State`, lifecycle,
and persistence live in the host `TasksView` (in the iOS app target), so these
types render under frozen mock data in `IOSScreenTourTests`. The whole file set
is wrapped in `#if os(iOS)`.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `FilterChip` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/Tasks/FilterChip.swift:8` | Pill toggle button; lavender-filled when `isSelected`, raised card otherwise |
| `FilterHeader` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/Tasks/FilterHeader.swift:40` | Search field + chip row; all state via `@Binding`; host owns it |
| `FlatTaskRow` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/Tasks/FlatTaskRow.swift:6` | A `TaskNode` plus render `depth`, `parentID`, `hasChildren`; id is `node.id` |
| `QuickFilterToken` | enum | `Packages/LillistUI/Sources/LillistUI/iOS/Tasks/FilterHeader.swift:8` | The three built-in filters (`today`/`thisWeek`/`done`); `done` is special-cased by the host |
| `SavedFilterChipSpec` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/Tasks/FilterHeader.swift:27` | Pinned saved-filter chip identity (`id` UUID + `title`) |
| `TaskNode` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/Tasks/TaskTree.swift:15` | One outline node: `record`, `tagNames`, `children`; id is `record.id` |
| `TaskOutlineRowLabel` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/Tasks/TaskOutlineRowView.swift:24` | The inert tappable text region passed to a row's `linkContent` closure |
| `TaskOutlineRowView` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/Tasks/TaskOutlineRowView.swift:37` | One outline row: chevron + status + caller-wrapped label; generic over `LinkContent` |
| `TaskTree` | enum | `Packages/LillistUI/Sources/LillistUI/iOS/Tasks/TaskTree.swift:43` | `build(records:tagsByTask:sort:)` projects flat records into a sorted node tree |
| `TasksSort` | enum | `Packages/LillistUI/Sources/LillistUI/iOS/Tasks/TasksSort.swift:11` | Sort options (`personalized`/`due`/`modified`); persisted as `rawValue` by the host |
| `TreeFlattener` | enum | `Packages/LillistUI/Sources/LillistUI/iOS/Tasks/FlatTaskRow.swift:22` | `flatten(_:collapsed:)` depth-first walk emitting one `FlatTaskRow` per visible node |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `TaskTree.build` | static func | `Packages/LillistUI/Sources/LillistUI/iOS/Tasks/TaskTree.swift:47` | Sole tree constructor; orphan-promotion + per-level sort rules live here |
| `applySort` | static func | `Packages/LillistUI/Sources/LillistUI/iOS/Tasks/TaskTree.swift:80` | Encodes the three `TasksSort` orderings incl. nil-last and UUID tie-break |
| `TreeFlattener.flatten` | static func | `Packages/LillistUI/Sources/LillistUI/iOS/Tasks/FlatTaskRow.swift:26` | Maps the tree to the `List` row sequence, honoring the `collapsed` set |

## Relationships

- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.TaskNode -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TaskRecord (owns)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.TaskTree -> Packages-LillistCore-Sources-LillistCore-Ordering.SiblingOrder (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.TaskOutlineRowView -> Packages-LillistUI-Sources-LillistUI-Components.StatusIndicatorView (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.TaskOutlineRowLabel -> Packages-LillistUI-Sources-LillistUI-Components.TaskRowLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.TaskOutlineRowView -> Packages-LillistCore-Sources-LillistCore-Model.Status (reads)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.TaskOutlineRowView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.StatusPalette (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.FilterChip -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.LillistColor (reads)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.FilterHeader -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.RainbowPalette (reads)`
- `Apps-Lillist-iOS-Sources-misc.TasksView -> Packages-LillistUI-Sources-LillistUI-iOS-Tasks.TaskTree (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.TasksScreen -> Packages-LillistUI-Sources-LillistUI-iOS-Tasks.FilterHeader (calls)`

## Type notes

All public types are value types; `TaskNode`, `FlatTaskRow`, and
`SavedFilterChipSpec` are `Sendable + Hashable`, safe to pass across actor
boundaries and use as SwiftUI diff identity. `TaskNode.hash` is hand-written
(`Packages/LillistUI/Sources/LillistUI/iOS/Tasks/TaskTree.swift:32`) because
`TaskRecord` is only `Equatable`; it hashes `record.id` while `==` compares full
content. `TaskTree.build` promotes any record whose `parentID` is absent from the
input set to a root, so a filtered view never drops orphan-matched subtasks
(`TaskTree.swift:57`). `TaskOutlineRowView` deliberately constructs the chevron
and `StatusIndicatorView` *outside* the `linkContent` closure so a row-level
drag/navigation wrapper can never cover those controls — the closure only ever
receives the inert `TaskOutlineRowLabel` (`TaskOutlineRowView.swift:9`).
`TaskOutlineRowLabel` is standalone (not nested in the generic view) to keep
`LinkContent` inference non-circular (`TaskOutlineRowView.swift:22`).

## External deps

- SwiftUI — view layer for `FilterChip`, `FilterHeader`, `TaskOutlineRowView`
- Foundation — `UUID`/`Date` math in `TaskTree`/`TreeFlattener`/`FlatTaskRow`

## Gotchas

- `QuickFilterToken.done` replaces the default `status != closed` baseline rather
  than AND-ing with it, else the result is always empty — special-cased by the
  host `TasksView` (`Packages/LillistUI/Sources/LillistUI/iOS/Tasks/FilterHeader.swift:5`).
