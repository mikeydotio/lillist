---
module: Packages/LillistUI/Sources/LillistUI/iOS/Tasks
summary: "Tree-building, outline row rendering, and filter/sort primitives for the iOS Tasks list."
read_when: "Touching iOS task list or outline structure"
sources:
  - path: Packages/LillistUI/Sources/LillistUI/iOS/Tasks/FilterChip.swift
    blob: 6b97950bb89954e7ae80a11f9af10607d1480cd1
  - path: Packages/LillistUI/Sources/LillistUI/iOS/Tasks/FilterHeader.swift
    blob: a693fc93727287ceaf85fba683bd4095d70f086b
  - path: Packages/LillistUI/Sources/LillistUI/iOS/Tasks/FlatTaskRow.swift
    blob: 39cb162736a7480bf09c2fdc9b8f78aff7a7f90c
  - path: Packages/LillistUI/Sources/LillistUI/iOS/Tasks/TaskOutlineRowView.swift
    blob: c2ed5c0834924e22c4441d965b8e7054037b47c6
  - path: Packages/LillistUI/Sources/LillistUI/iOS/Tasks/TaskTree.swift
    blob: 815f9136b2bf293dd9193a53cf6427110fa4303c
  - path: Packages/LillistUI/Sources/LillistUI/iOS/Tasks/TasksSort.swift
    blob: c217d33cfcf21c914c125485ff29e2e548dc696b
references_modules: [Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistCore-Sources-LillistCore-Ordering, Packages-LillistUI-Sources-LillistUI-Components-chunk-1, Packages-LillistUI-Sources-LillistUI-Components-chunk-2, Packages-LillistUI-Sources-LillistUI-Settings, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistUI/Sources/LillistUI/iOS/Tasks

## Purpose

This module is the complete rendering pipeline for the iOS task list: it transforms a flat [TaskRecord] into a sorted hierarchical tree (TaskTree/TaskNode), projects that tree into an order-stable flat sequence for outline rendering (TreeFlattener/FlatTaskRow), and provides the row view (TaskOutlineRowView) and filter header (FilterHeader/FilterChip) that turn those structures into interactive UI. It vanishes and the Tasks screen loses its tree shape, collapsible outline, and filter/sort affordances entirely.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `FilterChip` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/Tasks/FilterChip.swift:8` | Pill toggle button; callers supply title, isSelected, and action; selected fills lavender/purple-ink, unselected is card-white; contrast borders scale via increaseContrastOverride environment key. |
| `FilterHeader` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/Tasks/FilterHeader.swift:40` | Pure presenter: bindings own searchText, selectedTokens, selectedSavedFilters; onClear fires when any filter is active; host must place via safeAreaInset(edge: .top) to float over the scroll list. |
| `FlatTaskRow` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/Tasks/FlatTaskRow.swift:6` | Depth-annotated flat node produced by TreeFlattener; id delegates to node.id so SwiftUI list identity is stable across re-flattens when node UUIDs are unchanged. |
| `QuickFilterToken` | enum | `Packages/LillistUI/Sources/LillistUI/iOS/Tasks/FilterHeader.swift:8` | Three built-in filter tokens; callers must treat .done specially — it replaces the default status != closed baseline rather than AND-ing with it, per comment at FilterHeader.swift:5-7. |
| `SavedFilterChipSpec` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/Tasks/FilterHeader.swift:27` | Value-type transfer object carrying a pinned saved filter's id and title for FilterHeader to render; decouples the header from SmartFilterRecord. |
| `TaskNode` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/Tasks/TaskTree.swift:15` | Hierarchical TaskRecord projection with resolved tagNames and typed children; orphans (parent absent from input set) are promoted to root by TaskTree.build; hash is identity-based on record.id. |
| `TaskOutlineRowLabel` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/Tasks/TaskOutlineRowView.swift:25` | Inert text-region value passed into TaskOutlineRowView's linkContent closure; the only row subregion that may receive tap or drag gestures, by API contract; wraps TaskRowLabel with full-width contentShape(Rectangle()). |
| `TaskOutlineRowView` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/Tasks/TaskOutlineRowView.swift:38` | Generic outline row with disclosure chevron, StatusIndicatorView, and caller-supplied linkContent; chevron and status indicator are outside the linkContent closure so gesture conflicts are impossible by construction; isDropTargetParent shows drop-target card border. |
| `TaskTree` | enum | `Packages/LillistUI/Sources/LillistUI/iOS/Tasks/TaskTree.swift:43` | Namespace-only enum; sole public entry point is build(records:tagsByTask:sort:); transforms a flat [TaskRecord] into a sorted [TaskNode] tree with sort applied per level. |
| `TasksSort` | enum | `Packages/LillistUI/Sources/LillistUI/iOS/Tasks/TasksSort.swift:11` | Sort options persisted via @AppStorage("lillist.ios.sort") as rawValue; drives TaskTree.applySort per-level; .personalized uses SiblingOrder.precedes, .due/.modified sort by field with nil last. |
| `TreeFlattener` | enum | `Packages/LillistUI/Sources/LillistUI/iOS/Tasks/FlatTaskRow.swift:22` | Namespace-only enum; sole public entry point is flatten(_:collapsed:); callers supply collapsed UUIDs to hide subtrees without removing them from the tree. |
| `build` | func | `Packages/LillistUI/Sources/LillistUI/iOS/Tasks/TaskTree.swift:47` | Single-pass tree builder: groups children by parentID, promotes orphans to root, then applies TasksSort per level recursively; pure function, no stored state. |
| `flatten` | func | `Packages/LillistUI/Sources/LillistUI/iOS/Tasks/FlatTaskRow.swift:26` | Depth-first walk of [TaskNode] emitting one FlatTaskRow per visible node; subtrees whose root UUID is in collapsed are skipped; output order matches render order. |
| `hash` | func | `Packages/LillistUI/Sources/LillistUI/iOS/Tasks/TaskTree.swift:32` | Identity-based hash over record.id; required because TaskStore.TaskRecord is Equatable but not Hashable; content equality is handled by the synthesized == at TaskTree.swift:36-40. |
| `makeNode` | func | `Packages/LillistUI/Sources/LillistUI/iOS/Tasks/TaskTree.swift:67` | Local nested function inside TaskTree.build; resolves children from childrenByParent map and recursively sorts them; not independently callable outside build. |
| `walk` | func | `Packages/LillistUI/Sources/LillistUI/iOS/Tasks/FlatTaskRow.swift:33` | Local recursive closure captured inside flatten; not independently callable — use TreeFlattener.flatten as the entry point. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.FilterChip -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.FilterChip -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.fill (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.FilterHeader -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.FilterHeader -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.accessibilityLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.FilterHeader -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.fill (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.FilterHeader -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.glassSurface (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.QuickFilterToken -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.TaskOutlineRowLabel -> Packages-LillistUI-Sources-LillistUI-Components-chunk-2.TaskRowLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.TaskOutlineRowView -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.TaskOutlineRowView -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1.StatusIndicatorView (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.TaskOutlineRowView -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1.rainbowCard (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.TaskOutlineRowView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.accessibilityLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.TaskOutlineRowView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.color (reads)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.applySort -> Packages-LillistCore-Sources-LillistCore-Ordering.precedes (reads)`

## Type notes

All six public types are value-types (struct or enum) and Sendable — safe to pass across actor boundaries without wrapping. TaskNode.hash(into:) is hand-written to hash only record.id because TaskStore.TaskRecord is Equatable but not Hashable; the comment at TaskTree.swift:29-31 makes this explicit. TaskTree.build and TreeFlattener.flatten are pure functions with no stored state, callable from any isolation context. FilterHeader and TaskOutlineRowView are stateless presenters: all mutable state flows in via @Binding or closure parameters — no @State, no .task lifecycle (per the iOS container/presenter split). FlatTaskRow.id delegates to node.id (FlatTaskRow.swift:12) so list identity is stable across re-flattens when node UUIDs are unchanged. TasksSort is persisted via @AppStorage("lillist.ios.sort") as rawValue (TasksSort.swift:10).

## External deps

- Foundation — imported
- LillistCore — imported
- SwiftUI — imported

## Gotchas

TaskOutlineRowView's linkContent closure is architected to make two antipatterns unrepresentable: a Button inside the closure would starve the long-press drag gesture, and a drag gesture overlapping the status indicator would eat its taps. Both regressions shipped and are documented in comments at TaskOutlineRowView.swift:8-18 (2026-06-12 status-circle regression; 2026-06-17 Button inversion). The closure only ever receives the inert TaskOutlineRowLabel — the chevron and StatusIndicatorView are constructed outside it by design.
