---
module: Packages/LillistUI/Sources/LillistUI/DragReorder
summary: "Custom drag-reorder engine for hierarchical task lists — state machine, geometry, hit-testing, and overlay rendering"
read_when: "Touching drag-to-reorder behavior, drop targets, phantom overlay, or row geometry collection"
sources:
  - path: Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift
    blob: aac3debd777545a224f31540a34abfbfbaabfa2f
  - path: Packages/LillistUI/Sources/LillistUI/DragReorder/DragDropResolver.swift
    blob: 8f836bc997a9af166b142f201da8f1d2ba0eb77f
  - path: Packages/LillistUI/Sources/LillistUI/DragReorder/DragOverlay.swift
    blob: 001bb91b34fec88226557689e8b1f32927959769
  - path: Packages/LillistUI/Sources/LillistUI/DragReorder/DragReorderRow.swift
    blob: b598b1592af7855b780250afd2f084f35987c510
  - path: Packages/LillistUI/Sources/LillistUI/DragReorder/DragReorderable.swift
    blob: b5c984f2aa0930702a1a3b8b4a780d94ea70dcf4
  - path: Packages/LillistUI/Sources/LillistUI/DragReorder/DragSession.swift
    blob: baae4992c8080524d5bef21e45d37f7e442fcfbb
  - path: Packages/LillistUI/Sources/LillistUI/DragReorder/DragSortMode.swift
    blob: 5835f4e289cf93d3cbf3fc739e31006a8783a9cd
  - path: Packages/LillistUI/Sources/LillistUI/DragReorder/DragTarget.swift
    blob: 7d25e4ee30e826d15a158e6b92c26628c283df6b
  - path: Packages/LillistUI/Sources/LillistUI/DragReorder/RowGeometryReporter.swift
    blob: 039204fca9709263f21f1c51e39e17a59ee4f35e
references_modules: [Packages-LillistCore-Sources-LillistCore-Diagnostics, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1, Packages-LillistUI-Sources-LillistUI-Theme-chunk-2, Packages-LillistUI-Sources-LillistUI-Accessibility, Packages-LillistUI-Sources-LillistUI-iOS-Tasks, Apps-Lillist-iOS-Sources-misc, Apps-Lillist-macOS-Sources-Views]
generator: cartographer/1
baseline: 34dfea7772679dbabc08fabd6fbba53f6ad5856b
---

# Module: Packages/LillistUI/Sources/LillistUI/DragReorder

## Purpose

A bespoke drag-to-reorder system that replaces SwiftUI's `List.onMove`, built to support
hierarchical (parent/child) reordering, reparenting, and a custom lifted-phantom animation
the standard API cannot express. The design idea: a `@MainActor` `DragController` state
machine (`idle → dragging → idle`) owns all drag state and pure hit-testing, while view code
is split into thin attachable modifiers (gesture + geometry) and a single `DragOverlay`.
Every Core Data concept is kept out — rows are reduced to `DragReorderRow` value structs and
drops resolve to a `DragMutation`, so both apps map a release to `TaskStore` calls themselves.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `DragController` | class | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift:30` | `@MainActor ObservableObject` driving the drag; screens populate inputs and observe `state` |
| `DragControllerState` | enum | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift:9` | Published state: `idle`/`dragging`/`dropping`; `dropping` reserved, not yet emitted |
| `DragCoordinateSpace` | enum | `Packages/LillistUI/Sources/LillistUI/DragReorder/RowGeometryReporter.swift:17` | Holds the shared coordinate-space name `"TaskListDrag"` for list, rows, gesture |
| `DragDropResolver` | enum | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragDropResolver.swift:20` | Pure `DragTarget` + `flatRows` → `DragMutation`; single source of truth for both apps |
| `DragMutation` | enum | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragDropResolver.swift:11` | LillistCore-agnostic store intent: `reorder`/`reparent`/`noop` |
| `DragOverlay` | struct | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragOverlay.swift:18` | `.overlay` on the list; renders phantom + drop indicator from the controller |
| `DragReorderRow` | struct | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragReorderRow.swift:8` | Value row descriptor (`id`/`parentID`/`depth`) decoupling controller from app row types |
| `DragSession` | struct | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragSession.swift:15` | Snapshot of an active drag; `cursorY = initialCursorY + translation` |
| `DragSortMode` | enum | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragSortMode.swift:6` | `personalized`/`sortedByOther`; between-row drops are legal only in `personalized` |
| `DragTarget` | enum | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragTarget.swift:16` | Resolved drop intent: `between`/`onto`/`rejected`/`none` |
| `RowFramePreferenceKey` | struct | `Packages/LillistUI/Sources/LillistUI/DragReorder/RowGeometryReporter.swift:8` | `PreferenceKey` aggregating `[UUID: CGRect]` row frames the screen feeds to the controller |
| `dragReorderable(id:controller:)` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragReorderable.swift:17` | `View` ext: attaches gesture + geometry reporter to a row |
| `dragReorderGesture(id:controller:)` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragReorderable.swift:29` | `View` ext: gesture only, for rows with embedded interactive controls |
| `settlePosition(for:target:geometry:)` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragOverlay.swift:161` | `nonisolated static`: where the phantom lands on release; callable from tests |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `resolveTarget(forDraggedID:atY:)` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift:197` | Pure hit-test entry; turns a cursor Y into a `DragTarget` from current inputs |
| `finalize(target:draggedID:)` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift:316` | Applies cycle-rejection (`isSelfOrDescendant`) over every resolved target |
| `hitRow(atY:)` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift:233` | Row hit-test that expands each frame into half the inter-row gap so indicators stay live |
| `endDrag(settleDuration:)` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift:153` | Fires the drop handler then settles; only `between`/`onto` call the handler |
| `setOnDrop(_:)` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift:78` | Late-binds the drop handler from `.onAppear` (containers can't capture self at init) |
| `DragReorderGestureModifier` | struct | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragReorderable.swift:37` | Per-platform gesture; iOS long-press-then-drag, macOS plain drag; tracks via translation |
| `reportRowGeometry(id:)` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/RowGeometryReporter.swift:26` | Emits a row's frame into `RowFramePreferenceKey` via a clear `GeometryReader` background |

## Relationships

- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.TasksScreen -> Packages-LillistUI-Sources-LillistUI-DragReorder.DragController (owns)` — `Packages/LillistUI/Sources/LillistUI/iOS/Screens/TasksScreen.swift`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.TasksScreen -> Packages-LillistUI-Sources-LillistUI-DragReorder.DragOverlay (calls)` — `Packages/LillistUI/Sources/LillistUI/iOS/Screens/TasksScreen.swift`
- `Apps-Lillist-iOS-Sources-misc.TasksView -> Packages-LillistUI-Sources-LillistUI-DragReorder.DragDropResolver (calls)` — `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift`
- `Apps-Lillist-macOS-Sources-Views.TaskListView -> Packages-LillistUI-Sources-LillistUI-DragReorder.DragController (owns)` — `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift`
- `Apps-Lillist-macOS-Sources-Views.TaskListView -> Packages-LillistUI-Sources-LillistUI-DragReorder.DragDropResolver (calls)` — `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift`
- `Apps-Lillist-macOS-Sources-Views.TaskListView -> Packages-LillistUI-Sources-LillistUI-DragReorder.DragReorderRow (owns)` — `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift`
- `Packages-LillistUI-Sources-LillistUI-DragReorder.DragController -> Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticEvent (emits)` — `Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift:347`
- `Packages-LillistUI-Sources-LillistUI-DragReorder.DragOverlay -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.RainbowGradient (reads)` — `Packages/LillistUI/Sources/LillistUI/DragReorder/DragOverlay.swift:132`
- `Packages-LillistUI-Sources-LillistUI-DragReorder.DragOverlay -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-2.LillistDragTokens (reads)` — `Packages/LillistUI/Sources/LillistUI/DragReorder/DragOverlay.swift:57`
- `Packages-LillistUI-Sources-LillistUI-DragReorder.DragReorderGestureModifier -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-2.LillistDragTokens (reads)` — `Packages/LillistUI/Sources/LillistUI/DragReorder/DragReorderable.swift:56`
- `Packages-LillistUI-Sources-LillistUI-DragReorder.DragReorderGestureModifier -> Packages-LillistUI-Sources-LillistUI-Accessibility.reduceMotionOverride (reads)` — `Packages/LillistUI/Sources/LillistUI/DragReorder/DragReorderable.swift:41`

## Type notes

`DragController` is `@MainActor`; its inputs (`flatRows`, `geometry`, `sortMode`,
`isFilterActive`, `diagnosticLog`) are plain mutable vars the screen re-syncs on every
data/preference change, while `state` is the only `@Published` field. `resolveTarget` is a
pure function of those inputs plus the dragged id, which is why the resolution tests can drive
it with synthetic geometry. All DTOs (`DragReorderRow`, `DragSession`, `DragTarget`,
`DragMutation`, `DragSortMode`) are `Sendable` value types; `DragTarget`/`DragMutation`/
`DragSession`/`DragReorderRow` are also `Equatable`, letting the gesture coalesce unchanged
targets (`DragReorderable.swift:101`). `initialCursorY` is captured once at `beginDrag` and is
the fixed anchor for translation math and the rejected-drop settle position. Cycle safety is
enforced in `finalize` via `isSelfOrDescendant`, which walks the `parentID` chain with a 1024
iteration guard (`DragController.swift:333`). The coordinate-space mismatch between the named
List space and the overlay's local space is corrected by a runtime `-dy` shift
(`DragOverlay.swift:41`).

## External deps

- SwiftUI — gestures, `PreferenceKey`, `GeometryReader`, `ViewModifier`, the overlay views
- Combine — `ObservableObject`/`@Published` backing `DragController`
- UIKit — iOS-only haptics (`UIImpactFeedbackGenerator`, `UISelectionFeedbackGenerator`)
- AppKit — macOS-only `NSHapticFeedbackManager` on drag begin

## Gotchas

- Never attach `dragReorderable` over interactive controls — the long-press eats taps; use `dragReorderGesture` on the inert region instead (`Packages/LillistUI/Sources/LillistUI/DragReorder/DragReorderable.swift:11`).
- iOS drag begin anchors on the row's `frame.midY`, not `drag.location.y`, which can arrive in an unexpected coordinate space at the first sequenced event (`Packages/LillistUI/Sources/LillistUI/DragReorder/DragReorderable.swift:82`).
- `DragControllerState.dropping` is reserved for a future animated phase and is never emitted; `endDrag` goes straight to `idle` when `settleDuration == 0` (`Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift:14`).
