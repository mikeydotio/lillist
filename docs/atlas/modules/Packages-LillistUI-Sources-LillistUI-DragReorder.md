---
module: Packages/LillistUI/Sources/LillistUI/DragReorder
summary: "Drag-reorder engine: gesture capture, @MainActor state machine, phantom overlay, drop-mutation resolver."
read_when: "Touching drag-to-reorder behavior"
sources:
  - path: Packages/LillistUI/Sources/LillistUI/DragReorder/DragAxisArbiter.swift
    blob: e04e4eb4ccdc6e860237f9d700c6f03c9e5902fc
  - path: Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift
    blob: 55668511c74074eebca8da0f5884cc0a3f6d3efd
  - path: Packages/LillistUI/Sources/LillistUI/DragReorder/DragDropResolver.swift
    blob: dd0b276aabd5057029cf97e22c1cb02f42f5069c
  - path: Packages/LillistUI/Sources/LillistUI/DragReorder/DragOverlay.swift
    blob: 972b550cf68fa1005e1f0ada2f088e6273db1c80
  - path: Packages/LillistUI/Sources/LillistUI/DragReorder/DragReorderRow.swift
    blob: b598b1592af7855b780250afd2f084f35987c510
  - path: Packages/LillistUI/Sources/LillistUI/DragReorder/DragReorderable.swift
    blob: 2e3f3101ae198d554a729a05a0685ca17a7e09f9
  - path: Packages/LillistUI/Sources/LillistUI/DragReorder/DragSession.swift
    blob: baae4992c8080524d5bef21e45d37f7e442fcfbb
  - path: Packages/LillistUI/Sources/LillistUI/DragReorder/DragSortMode.swift
    blob: 5835f4e289cf93d3cbf3fc739e31006a8783a9cd
  - path: Packages/LillistUI/Sources/LillistUI/DragReorder/DragTarget.swift
    blob: 6ce0c18a07823a691845961d9e3200402733eef5
  - path: Packages/LillistUI/Sources/LillistUI/DragReorder/RowGeometryReporter.swift
    blob: 039204fca9709263f21f1c51e39e17a59ee4f35e
references_modules: [Packages-LillistCore-Sources-LillistCore-Diagnostics, Packages-LillistCore-Sources-LillistCore-Ordering, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistUI-Sources-LillistUI-Accessibility, Packages-LillistUI-Sources-LillistUI-Components-chunk-1, Packages-LillistUI-Sources-LillistUI-Recurrence, Packages-LillistUI-Sources-LillistUI-Settings, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistUI/Sources/LillistUI/DragReorder

## Purpose

DragReorder implements the complete custom drag-to-reorder engine for task lists: gesture capture (`DragReorderable`), an `@MainActor` state machine (`DragController`), visual feedback (`DragOverlay`), row-frame collection (`RowGeometryReporter`), and drop-to-store-mutation mapping (`DragDropResolver`). The unifying idea is that all drag state flows through one observable controller so overlays, rows, and app logic each react to a single source of truth rather than coordinating across independent gesture handlers. Without this module, task lists are static and users cannot manually reorder or reparent tasks.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AnyTransition` | extension | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragOverlay.swift:262` | Extension on `AnyTransition` providing `.lift`: asymmetric transition with inverse-scale insertion and identity removal, used for phantom mount/unmount animation. |
| `Axis` | enum | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragAxisArbiter.swift:12` | Two-case enum (`vertical`, `horizontal`) returned by `DragAxisArbiter.axis`; callers switch on this to decide whether a drag drives reorder or yields to the swipe gesture. |
| `DragAxisArbiter` | enum | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragAxisArbiter.swift:11` | Pure enum namespace; no instances. Sole entry point is `axis(forTranslation:commitDistance:)`. |
| `DragController` | class | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift:30` | `@MainActor` `ObservableObject` state machine for one drag session. Callers set `flatRows`, `geometry`, `sortMode`, `isFilterActive` before resolution; the registered `onDrop` handler fires exactly once per actionable (`.between`) drop. |
| `DragControllerState` | enum | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift:9` | Enum of drag phases: `.idle`, `.dragging(DragSession)`, `.dropping(DragSession, DragTarget)`. `.dropping` is reserved — `endDrag()` currently transitions directly to `.idle`. |
| `DragCoordinateSpace` | enum | `Packages/LillistUI/Sources/LillistUI/DragReorder/RowGeometryReporter.swift:17` | Enum namespace holding `name: String = "TaskListDrag"` — the shared coordinate-space name that ties the container's `.coordinateSpace(name:)`, each row's geometry reporter, and the drag gesture into one space. |
| `DragDropResolver` | enum | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragDropResolver.swift:23` | Pure enum namespace; no instances. Sole entry point is `resolve(target:)`. Single source of truth for iOS and macOS `applyDrop` implementations. |
| `DragMutation` | enum | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragDropResolver.swift:14` | LillistCore-agnostic drop outcome: `.reorder(parent:after:before:)`, `.reparent(newParent:)`, or `.noop`. App targets dispatch the result to `TaskStore`; the dragged ID is supplied by the app, not carried here. |
| `DragOverlay` | struct | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragOverlay.swift:18` | Overlay view rendering the floating phantom and insertion indicator; observes `DragController`. `PhantomContent` is caller-supplied so the overlay is platform-agnostic. `indentLeadingX` is injectable for platform-specific indent math. |
| `DragReorderGestureModifier` | struct | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragReorderable.swift:39` | Internal `ViewModifier` wiring the platform gesture to `DragController`. iOS: long-press sequenced with drag; macOS: bare drag with axis arbitration. Callers should use the `View` extension entry points (`dragReorderable` / `dragReorderGesture`) rather than applying this modifier directly. |
| `DragReorderRow` | struct | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragReorderRow.swift:8` | Minimal platform-neutral row descriptor (`id`, `parentID`, `depth`) consumed by `DragController` for gap-finding and subtree exclusion. Decouples the controller from iOS's `FlatTaskRow` and macOS's `TaskOutlineNode`. |
| `DragSession` | struct | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragSession.swift:15` | Value-type snapshot of an active drag. `initialCursorY` is fixed at `beginDrag` and acts as the anchor for translation-based updates and the settle target on rejection; `cursorY` and `target` are mutable per-event. |
| `DragSortMode` | enum | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragSortMode.swift:6` | Two-case enum (`personalized`, `sortedByOther`). `DragController.resolveTarget` returns `.none` unless mode is `.personalized`, blocking reorder in auto-sorted contexts. |
| `DragTarget` | enum | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragTarget.swift:18` | Three-case resolved drop intent. `.between(beforeID:afterID:parentID:)` encodes the full insertion point; both anchors `nil` means first/only child (routes to `reparent`). `.rejected` is a cycle violation; `.none` is no-op. Callers pass this to `DragDropResolver.resolve` to get a `DragMutation`. |
| `RowFramePreferenceKey` | struct | `Packages/LillistUI/Sources/LillistUI/DragReorder/RowGeometryReporter.swift:8` | SwiftUI `PreferenceKey` aggregating `[UUID: CGRect]` row frames. The screen reads it via `.onPreferenceChange` and assigns the result to `controller.geometry`. |
| `View` | extension | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragReorderable.swift:6` | Extension on `View` providing `dragReorderable(id:controller:)` (geometry + gesture) and `dragReorderGesture(id:controller:)` (gesture only). Primary attachment API for rows. |
| `View` | extension | `Packages/LillistUI/Sources/LillistUI/DragReorder/RowGeometryReporter.swift:21` | Extension on `View` providing `reportRowGeometry(id:)`, which injects a background `GeometryReader` reporting the row's frame into `RowFramePreferenceKey` in the `DragCoordinateSpace`. |
| `axis` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragAxisArbiter.swift:19` | Returns the committed axis once `max(|dx|, |dy|) >= commitDistance`, or `nil` while undecided. Ties resolve to `.vertical`. Pure function; no side effects. |
| `beginDrag` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift:91` | Transitions `idle → dragging`; idempotent when already dragging. Locks `initialCursorY = cursorY` at the moment of the call, anchoring subsequent `updateCursor(translation:)` offsets. |
| `body` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragOverlay.swift:292` | Applies `scaleMultiplier` via `scaleEffect(_:)` to content; cancels the phantom's permanently-applied lifted scale during the `.lift` transition's active frame. |
| `body` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragReorderable.swift:54` | Attaches `platformGesture` to wrapped content. On iOS: `LongPressGesture.sequenced(before: DragGesture)`; on macOS: bare `DragGesture` with `DragAxisArbiter` arbitration. Reads `reduceMotionOverride` to collapse the settle animation when reduce-motion is active. |
| `cancelDrag` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift:188` | Unconditionally transitions to `.idle` without firing the drop handler. Safe to call in any state. |
| `dragReorderGesture` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragReorderable.swift:31` | Gesture-only variant: attaches `DragReorderGestureModifier` without geometry reporting. For rows whose full frame is reported separately via `.reportRowGeometry(id:)`. |
| `dragReorderable` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragReorderable.swift:19` | Combines `.reportRowGeometry(id:)` + `DragReorderGestureModifier`. Primary entry point for simple rows without embedded controls that need separate gesture regions. |
| `endDrag` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift:153` | Fires the drop handler for `.between` targets, then transitions to `.idle` (or `.dropping` when `settleDuration > 0`). `.rejected` / `.none` skip the handler; a dropped-but-rejected event is still emitted to the diagnostic log. |
| `insertionIndicatorY` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift:274` | Returns the Y coordinate for the insertion indicator in the named coordinate space. Excludes the dragged subtree from the reference set to produce exactly one fencepost per gap, avoiding a bogus double-fencepost at the source slot. |
| `reduce` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/RowGeometryReporter.swift:10` | Merges two `[UUID: CGRect]` preference dictionaries; later (new) values win for duplicate keys, keeping geometry current when rows re-report their frames. |
| `reportRowGeometry` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/RowGeometryReporter.swift:26` | Injects a background `GeometryReader` that reports this view's frame in `DragCoordinateSpace` to `RowFramePreferenceKey`. Does not affect the view's visual rendering. |
| `resolve` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragDropResolver.swift:33` | Maps `DragTarget` → `DragMutation`. `.between` with at least one sibling anchor → `.reorder`; `.between` with no anchors (first/only child) → `.reparent`; `.rejected` / `.none` → `.noop`. |
| `resolveTarget` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift:217` | Pure resolution: selects gap by Y over reference rows (dragged subtree excluded), chooses depth by horizontal translation (Reminders-style indent/outdent). Returns `.none` when a smart filter is active or sort mode is not `.personalized`. |
| `setOnDrop` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift:78` | Replaces the drop handler. Intended for SwiftUI containers that cannot capture a valid closure at `@StateObject` init time; call from `.onAppear`. |
| `setResolvedTarget` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift:130` | Stores `target` onto the current `DragSession`; ignored when not in `.dragging` state. Emits a `drag.over` diagnostic event on every call. |
| `targetPayload` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift:385` | Converts a `DragTarget` to a `[String: DiagValue]` payload for diagnostic logging, including `.rejected` and `.none` so cancelled drops are visible in the log. |
| `updateCursor` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift:110` | Sets cursor Y to an absolute value. Intended for synthetic-geometry tests and snapshot fixtures; live gestures should use `updateCursor(translation:)` instead. |
| `updateCursor` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift:122` | Sets `cursorY = initialCursorY + translation`. Preferred live-gesture update path because gesture translation is coordinate-space-invariant, avoiding the coordinate-space ambiguity in `drag.location` at the first event. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `depth` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragOverlay.swift:246` | Translates a `parentID` to a numeric depth by walking `controller.flatRows` (fan-in 26, called from `betweenDivider`). Drives the horizontal indent of the insertion indicator, making the drop-depth preview visible to the user. DragOverlay.swift:246-251. |
| `emit` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift:377` | Single choke point for all diagnostic emission from the drag lifecycle (fan-in 11). Guards the nil `diagnosticLog` and wraps `log.log(event)` in a non-blocking `Task`, so every call site is one line and the gesture handler is never stalled. Removing it would scatter the guard+Task pattern across `beginDrag`, `setResolvedTarget`, and `endDrag`. |
| `finalize` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift:350` | Defense-in-depth cycle guard applied to every resolved target before it leaves `resolveTarget` (called on every `.between` path). Without it, a drop whose `parentID` is inside the dragged subtree could be accepted, violating the tree invariant. DragController.swift:350-357. |
| `indicator` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragOverlay.swift:198` | Factory for all drop indicator views during `.dragging` (fan-in 23, called from `DragOverlay.body`). Switches on `DragTarget` to produce a `betweenDivider` or `EmptyView`; gating function for all visual drop feedback. DragOverlay.swift:198-205. |
| `phantom` | func | `Packages/LillistUI/Sources/LillistUI/DragReorder/DragOverlay.swift:129` | Renders the floating lifted row with scale, opacity, shadow, and cursor-tracked position (fan-in 11, called from `DragOverlay.body`). The primary user-visible drag artifact; its settled position drives the perceived continuity of the drop. DragOverlay.swift:129-150. |

## Relationships

- `Packages-LillistUI-Sources-LillistUI-DragReorder.DragOverlay -> Packages-LillistCore-Sources-LillistCore-Ordering.position (calls)`
- `Packages-LillistUI-Sources-LillistUI-DragReorder.DragOverlay -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.transition (calls)`
- `Packages-LillistUI-Sources-LillistUI-DragReorder.DragOverlay -> Packages-LillistUI-Sources-LillistUI-Accessibility.accessibleAnimation (calls)`
- `Packages-LillistUI-Sources-LillistUI-DragReorder.DragOverlay -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.row (calls)`
- `Packages-LillistUI-Sources-LillistUI-DragReorder.DragReorderGestureModifier -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (calls)`
- `Packages-LillistUI-Sources-LillistUI-DragReorder.beginDrag -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Packages-LillistUI-Sources-LillistUI-DragReorder.betweenDivider -> Packages-LillistCore-Sources-LillistCore-Ordering.position (calls)`
- `Packages-LillistUI-Sources-LillistUI-DragReorder.betweenDivider -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.transition (calls)`
- `Packages-LillistUI-Sources-LillistUI-DragReorder.betweenDivider -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.fill (calls)`
- `Packages-LillistUI-Sources-LillistUI-DragReorder.emit -> Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticEvent (emits)`
- `Packages-LillistUI-Sources-LillistUI-DragReorder.endDrag -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Packages-LillistUI-Sources-LillistUI-DragReorder.phantom -> Packages-LillistCore-Sources-LillistCore-Ordering.position (calls)`
- `Packages-LillistUI-Sources-LillistUI-DragReorder.phantom -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1.rainbowCard (calls)`
- `Packages-LillistUI-Sources-LillistUI-DragReorder.referenceRows -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.row (calls)`
- `Packages-LillistUI-Sources-LillistUI-DragReorder.targetPayload -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`

## Type notes

`DragController` is `@MainActor final class ObservableObject`: all state transitions are guaranteed on the main actor; `@Published state` drives SwiftUI invalidation for overlays and rows (DragController.swift:29-34). `DragSession` is a value-type struct (`Equatable, Sendable`): each cursor move or target change replaces the whole session value inside `DragControllerState.dragging`, so SwiftUI detects changes via equality (DragSession.swift:15). `DragController.flatRows` and `.geometry` are plain `var` properties, not `@Published`: the screen sets them imperatively before calling `resolveTarget`; they do not trigger SwiftUI invalidation (DragController.swift:40-43). `DragAxisArbiter` and `DragDropResolver` are caseless `enum` namespaces with only `static func`; they hold no state and cannot be instantiated (DragAxisArbiter.swift:11, DragDropResolver.swift:23). `DragCoordinateSpace.name = "TaskListDrag"` is the string constant tying the container's `.coordinateSpace(name:)`, every row's geometry reporter, and the drag gesture into one shared space (RowGeometryReporter.swift:18). The `indentLeadingX` closure on `DragOverlay.init` is injectable so macOS and iOS can each supply their own indent-math without platform `#if` inside the overlay (DragOverlay.swift:27-43).

## External deps

- Combine — imported
- CoreGraphics — imported
- Foundation — imported
- LillistCore — imported
- SwiftUI — imported
- UIKit — imported

## Gotchas

Coordinate-space offset: `DragOverlay` lays out inside the safe area while `controller.geometry` frames are in the named coordinate space (behind safe areas); a `-dy` offset converts named→local at runtime or the phantom drifts under different insets (DragOverlay.swift:49-58). iOS first-event coordinate space: the first `.second` event of `LongPressGesture.sequenced(before:DragGesture)` may report `drag.location` in an unexpected space; `beginDrag` anchors on `frame.midY` instead (DragReorderable.swift:87-99). macOS axis arbitration: no long-press gate means `DragAxisArbiter` must commit a direction before any reorder begins; a horizontal commit yields to `SwipeableRow`; `committedAxis` resets to `nil` at `onEnded` (DragReorderable.swift:136-178). `DragControllerState.dropping` is reserved: `endDrag()` transitions directly to `.idle`; the `.dropping` case exists for a future animated-drop phase but is not currently emitted (DragController.swift:14-16). `setOnDrop` exists because SwiftUI containers cannot capture `self` in a `@StateObject` default-value closure; the real handler must be wired from `.onAppear` (DragController.swift:77-80).
