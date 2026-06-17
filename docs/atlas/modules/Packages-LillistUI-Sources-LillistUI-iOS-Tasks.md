---
module: Packages/LillistUI/Sources/LillistUI/iOS/Tasks
summary: Tree-building, flat-projection, sort, and filter-UI primitives for the iOS Tasks outline screen
read_when: Touching iOS task list rendering, outline expand/collapse, filter chips, or sort logic
sources:
  - path: Packages/LillistUI/Sources/LillistUI/iOS/Tasks/FilterChip.swift
  - path: Packages/LillistUI/Sources/LillistUI/iOS/Tasks/FilterHeader.swift
  - path: Packages/LillistUI/Sources/LillistUI/iOS/Tasks/FlatTaskRow.swift
  - path: Packages/LillistUI/Sources/LillistUI/iOS/Tasks/TaskOutlineRowView.swift
  - path: Packages/LillistUI/Sources/LillistUI/iOS/Tasks/TaskTree.swift
  - path: Packages/LillistUI/Sources/LillistUI/iOS/Tasks/TasksSort.swift
references_modules:
  - Packages-LillistCore-Sources-LillistCore-Stores-chunk-2
  - Packages-LillistCore-Sources-LillistCore-Ordering
  - Packages-LillistCore-Sources-LillistCore-Model
  - Packages-LillistUI-Sources-LillistUI-Components
  - Packages-LillistUI-Sources-LillistUI-Theme-chunk-1
generator: cartographer/1 model=claude-sonnet-4-6
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

- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.TaskNode -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (owns)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.TaskTree -> Packages-LillistCore-Sources-LillistCore-Ordering.SiblingOrder (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.TaskOutlineRowView -> Packages-LillistUI-Sources-LillistUI-Components.StatusIndicatorView (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.TaskOutlineRowLabel -> Packages-LillistUI-Sources-LillistUI-Components.TaskRowLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.TaskOutlineRowView -> Packages-LillistCore-Sources-LillistCore-Model.Status (reads)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.TaskOutlineRowView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.StatusPalette (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.FilterChip -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.LillistColor (reads)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.FilterHeader -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.RainbowPalette (reads)`

## Type notes

All public types are value types; `TaskNode`, `FlatTaskRow`, and
`SavedFilterChipSpec` are `Sendable + Hashable`, safe to pass across actor
boundaries and use as SwiftUI diff identity. `TaskNode.hash` is hand-written
(`Packages/LillistUI/Sources/LillistUI/iOS/Tasks/TaskTree.swift:32`) because
`TaskRecord` is only `Equatable`; it hashes `record.id` while `==` compares full
content. `TaskTree.build` promotes any record whose `parentID` is absent from the
input set to a root, so a filtered view never drops orphan-matched subtasks
(`Packages/LillistUI/Sources/LillistUI/iOS/Tasks/TaskTree.swift:57`). `TaskOutlineRowView` deliberately constructs the chevron
and `StatusIndicatorView` *outside* the `linkContent` closure so a row-level
drag/navigation wrapper can never cover those controls — the closure only ever
receives the inert `TaskOutlineRowLabel` (`Packages/LillistUI/Sources/LillistUI/iOS/Tasks/TaskOutlineRowView.swift:9`).
`TaskOutlineRowLabel` is standalone (not nested in the generic view) to keep
`LinkContent` inference non-circular (`Packages/LillistUI/Sources/LillistUI/iOS/Tasks/TaskOutlineRowView.swift:22`).

## External deps

- SwiftUI — view layer for `FilterChip`, `FilterHeader`, `TaskOutlineRowView`
- Foundation — `UUID`/`Date` math in `TaskTree`/`TreeFlattener`/`FlatTaskRow`

## Gotchas

- `QuickFilterToken.done` replaces the default `status != closed` baseline rather
  than AND-ing with it, else the result is always empty — special-cased by the
  host `TasksView` (`Packages/LillistUI/Sources/LillistUI/iOS/Tasks/FilterHeader.swift:5`).
