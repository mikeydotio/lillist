# Drag-reorder redesign — design

- **Date:** 2026-05-26
- **Status:** Approved (brainstorm complete; implementation plan to follow)
- **Scope:** Lillist iOS + macOS (unified)

## Context

iOS uses SwiftUI `List.onMove` gated to `sort == .personalized` (drag
handles surface via EditMode). It is sibling-only: cross-parent drops
silently revert in `TasksScreen.performMove`. macOS has a separate
hierarchical drop system (`TaskDropDelegate` + `DropPosition` with a
25/50/25 zone split) that already supports reparenting. The data model
fully supports parenting via `LillistTask.parent` and a fractional
`position`; `TaskStore.reorder(id:after:before:)` enforces same-parent
moves today.

The current iOS interaction has two complaints driving this redesign:

1. **Rows shift to make room** as the user drags — native `.onMove`
   behavior — which makes it impossible to express "drop *onto* this
   row to make it a child".
2. **No drop-onto-row semantics on iOS** at all, despite the data
   model and macOS pipeline already supporting reparenting.

## Goals

- Replace `.onMove` on iOS with a custom drag/drop system that supports
  both **between-row sibling reorder** and **onto-row reparent**.
- Show a clear visual cue for each drop mode without changing layout
  during the drag:
  - **Between two rows** → the divider between them becomes a thick,
    tinted capsule.
  - **Onto a row** → that row gets a thick, tinted rounded border.
- Keep the **gap** left by the dragged row in place for the duration of
  the drag, closing it smoothly at drop time as the dragged row animates
  to its new home.
- Unify iOS and macOS on one implementation. Remove the legacy
  `TaskDropDelegate` / `DropPosition` path on macOS.
- Preserve list chrome: swipe-to-delete, list row insets, sync badge,
  filter header all keep working.

## Non-goals

- Indent/outdent via horizontal cursor movement (Reminders-style). The
  depth of a between-drop is inferred from the row below the gap; we
  can revisit if it feels limiting in use.
- Auto-expand collapsed targets on hover. Per the answered "Smart:
  where the cursor was" reparent semantic, dropping onto a collapsed
  target appends the new child silently.
- Multi-select drag.
- Drag-and-drop across distinct lists/screens (Today → All Tags etc.).

## Decision summary

| Decision | Answer |
| --- | --- |
| Platform scope | Both platforms, unified implementation |
| iOS drag trigger | Long-press anywhere on row (0.3s, 4pt slop) |
| Sort gating | Smart split — reparent always, sibling-reorder only in `.personalized` |
| Reparent position | Where the cursor was (collapsed → end of children) |
| Implementation approach | Custom `DragGesture` overlay with shared controller |

## Architecture

### New module

`Packages/LillistUI/Sources/LillistUI/DragReorder/` (cross-platform,
not under `iOS/`). Files:

- `DragController.swift` — `@MainActor ObservableObject` holding the
  state machine: `.idle`, `.dragging(DragSession)`,
  `.dropping(DragSession, DragTarget)`. Exposes a single
  `onDrop: (UUID, DragTarget) -> Void` closure injected by the
  container.
- `DragSession.swift` — value type with the dragged row's id, original
  height, cursor position in the named coordinate space, and current
  resolved `DragTarget`.
- `DragTarget.swift` — `enum DragTarget { case between(beforeID: UUID?,
  afterID: UUID?, parentID: UUID?), onto(targetID: UUID), rejected }`.
- `RowGeometryReporter.swift` — `PreferenceKey` collecting each row's
  frame in the `"TaskList"` coordinate space; the screen aggregates a
  `[UUID: CGRect]` and feeds it to the controller.
- `DragOverlay.swift` — overlay drawn above the list rendering the
  floating phantom row and the drop indicator (divider or border).
- `DragReorderable.swift` — `View` modifier
  `.dragReorderable(id:controller:)` that attaches the
  platform-appropriate gesture and reports geometry.

### Container / presenter wiring

The existing iOS Tab-screen pattern keeps screens free of `@State`.

- `TasksView` (Lillist-iOS, container) creates
  `@StateObject var dragController = DragController(onDrop: …)` and
  passes it into `TasksScreen` as `@ObservedObject`. The `onDrop`
  closure dispatches to `TaskStore.reparent(...)` or `reorder(...)`.
- `TasksScreen` (LillistUI, presenter) observes the controller, lays
  out the rows with `.dragReorderable(id:controller:)`, and attaches
  the `DragOverlay(controller:)` as `.overlay` on the list container.
- On macOS, the equivalent container in `Apps/Lillist-macOS/` owns the
  controller the same way.

### Gesture activation

The `.dragReorderable` modifier resolves to:

- **iOS:**
  ```swift
  LongPressGesture(minimumDuration: 0.3, maximumDistance: 4)
      .sequenced(before:
          DragGesture(minimumDistance: 0,
                      coordinateSpace: .named("TaskList")))
  ```
- **macOS:**
  ```swift
  DragGesture(minimumDistance: 4,
              coordinateSpace: .named("TaskList"))
  ```

Both funnel into `controller.update(rowID:translation:location:)`.
`onEnded` calls `controller.endDrag(at:)`.

### List type

The list stays a SwiftUI `List` so swipe actions and list chrome
continue working. We do not adopt `LazyVStack` — the trade-off in lost
list chrome is not worth the marginal layout control.

While a session is active, the source row renders `Color.clear` of its
captured original height; no other row moves.

## Drop targets and hit testing

### Zones per row

Each row's frame splits into top 25% / middle 50% / bottom 25%. The
controller resolves the cursor's y-position to one of these for the
row whose frame currently contains the cursor, then maps to a
`DragTarget`:

- Top 25% → `.between(...)` above the row.
- Middle 50% → `.onto(targetID: row)`.
- Bottom 25% → `.between(...)` below the row.

This matches the existing macOS `DropPosition` (so its tests carry
over).

### Sort-mode gating

- `.personalized`: all three zones resolve as above.
- `.due` / `.modified`: middle 50% resolves to `.onto(...)`; the top
  and bottom 25% zones fall through to a `.none` resolution and no
  divider is drawn. Between-row drops would lie about visible position.

### Filter gating

Drag is disabled whenever an ephemeral filter is active. Long-press
fires no action. Position math against a filtered subset is unsafe.

### Depth resolution for between-row drops

The dragged row inherits the parent of the row immediately *below* the
gap:

- Between row N (depth D) and row N+1 (depth D+1, child of N): drop
  resolves as depth D+1, parent = row N — i.e., first child of N.
- Between two siblings at depth D: depth D, parent = their parent.
- Below the last row: top-level (parent = nil) at the end.

### Cycle rejection

If `.onto(targetID)` would make the dragged task its own descendant
(or itself), the controller emits `DragTarget.rejected`. The phantom
gets a red border, no indicator is drawn, and release cancels. The
same applies to between-row drops whose resolved parent is in the
dragged task's subtree.

## Visuals

### Dragged phantom

A duplicate `TaskOutlineRowView` rendered in the overlay at the
cursor's y-center. `scaleEffect(1.02)`, `shadow(radius: 12, y: 8)`,
`opacity(0.95)`. Picks up the row's natural appearance so the user
recognizes what they are moving.

### Source gap

The original row in the list renders `Color.clear` at its captured
original height. No other rows shift.

### Between-divider highlight

A `Capsule()` 2.5pt thick, `Color.accentColor`, inset 12pt leading and
trailing to match `listRowInsets`. Positioned at the divider line
between the two rows. Drawn in the overlay so it never alters layout.

### Onto-row border highlight

A `RoundedRectangle(cornerRadius: 8)` stroked at 2pt,
`Color.accentColor`, drawn at the target row's frame outset by 2pt on
all sides so the stroke sits outside the row's content. Drawn in the
overlay.

### Rejection state

When `DragTarget == .rejected`, the phantom row gets a 2pt
`Color.red.opacity(0.8)` border; no other indicator is drawn.

### New tokens

Added to `Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift`:

```swift
public enum LillistDragTokens {
    public static let indicatorColor: Color = .accentColor
    public static let rejectionColor: Color = Color.red.opacity(0.8)
    public static let dividerThickness: CGFloat = 2.5
    public static let rowBorderThickness: CGFloat = 2.0
    public static let rowBorderCornerRadius: CGFloat = 8
    public static let rowBorderOutset: CGFloat = 2
    public static let phantomScale: CGFloat = 1.02
    public static let phantomShadowRadius: CGFloat = 12
    public static let phantomOpacity: Double = 0.95
}
```

## Animation and gap behavior

### Drag begin (long-press resolves on iOS, mouse-down + slop on macOS)

`.spring(response: 0.25, dampingFraction: 0.7)`:

- Source row's content fades out; its height becomes the gap.
- Phantom fades in at the gesture location; scale 1.0 → 1.02, shadow
  radius 0 → 12, opacity 0 → 0.95.

Haptic — iOS: `UIImpactFeedbackGenerator(style: .medium)`; macOS:
`NSHapticFeedbackManager.defaultPerformer.perform(.alignment,
performanceTime: .now)`.

### In-flight

Phantom y-position binds 1:1 to `dragGesture.location.y` with no
animation. When the resolved `DragTarget` changes, the indicator
(divider, border, or red rejection border on the phantom) cross-fades
with `.easeInOut(duration: 0.12)`. iOS emits a `.selection` haptic on
each target change.

### Drop (success)

Controller transitions to `.dropping(session, target)`. Indicator
hides instantly. `TaskStore.reparent` / `reorder` is called
synchronously so the `recordsPublisher` emits the updated records
mid-animation. Tied to one
`.spring(response: 0.35, dampingFraction: 0.78)`:

- The gap at the source position closes from full height to 0.
- The new row at the destination renders with opacity 0 → 1.
- The phantom animates from its cursor position to the new row's
  resolved frame, opacity 0.95 → 0, scale 1.02 → 1.0.

When the spring completes, the controller transitions to `.idle`.
Haptic — iOS: `UIImpactFeedbackGenerator(style: .medium)`; macOS:
`.levelChange`.

### Drop (cancel or rejection)

`.spring(response: 0.4, dampingFraction: 0.8)`:

- Phantom returns to its source position; opacity 0.95 → 0, scale → 1.0.
- The gap closes to 0.
- Source row's content fades back in.

Haptic — iOS: `UINotificationFeedbackGenerator().notificationOccurred(.warning)`
for rejection only; no haptic for plain cancel. macOS: `.generic` for
rejection.

### Auto-scroll near edges

When the cursor is within 60pt of the list's top or bottom edge during
an active drag, the list auto-scrolls at a rate proportional to depth
into the zone (0 at the boundary, ~600pt/s at the edge). Implemented
with a `ScrollViewProxy.scrollTo(...)` call on a timer driven by the
controller; rows expose their id as a `.id(...)` anchor.

## Data layer changes

### New API

```swift
public func reparent(
    id: UUID,
    newParentID: UUID?,
    after afterID: UUID?,
    before beforeID: UUID?
) async throws
```

Atomically updates the task's `parent` relationship and computes a new
fractional `position` via `FractionalPosition.position(after:before:)`,
reading anchor positions from the new parent's children. If
`newParentID == oldParentID`, the call routes to existing `reorder`
behavior. Both UI paths go through this entry point for
single-responsibility.

### Cycle detection

The store walks up from `newParentID` through `parent` relationships
and throws `TaskStoreError.cycleWouldBeCreated` if the dragged task
appears in the chain. The UI never sends invalid drops, but tests of
the store API exercise this directly.

### Validation

`afterID` and `beforeID` must be direct children of `newParentID` (or
both nil for empty parent). The dragged task itself must exist. Other
mismatches throw `TaskStoreError.invalidAnchors`.

### Atomicity

One Core Data `save()`. Same pattern as existing `reorder`. CloudKit
sync picks up the change on the next mirror cycle.

## Edge cases

- **Drop onto self or descendant** — rejection.
- **Drop on empty space below last row** — top-level (parent = nil),
  appended to end of root.
- **Drop on empty list** — top-level, position 0.
- **Dragging a parent with children** — the subtree moves; children
  retain their relative order under the new parent.
- **Drag during search / active filter** — disabled.
- **Indent/outdent via horizontal cursor** — out of scope for v1.
- **Auto-expand collapsed targets** — out of scope.
- **EditMode removal** — the iOS list no longer activates EditMode in
  `.personalized` sort. Side benefit: swipe-to-delete works in all
  sort modes.

## Testing strategy

1. **`LillistCoreTests`** — new
   `Stores/TaskStoreReparentTests.swift`: basic reparent (changes
   parent + position), cycle rejection (direct ancestor, transitive
   ancestor, self), anchor validation (anchors must be children of
   new parent), cross-parent position math, error cases.
2. **`LillistCoreTests`** — new `DragReorder/DragControllerTests.swift`
   (pure model, no SwiftUI): state-machine transitions
   `idle → dragging → dropping → idle`, cancel path, rejection path,
   drop-target resolution given a `[UUID: CGRect]` geometry dictionary
   and a cursor point, sort-mode gating, filter gating.
3. **`LillistUITests`** — new
   `DragReorder/DragReorderSnapshotTests.swift`: four states — idle
   (regression baseline equal to current), dragging with between
   target, dragging with onto target, dragging rejected. Pinned to
   iPhone 16 Pro logical size per `IOSScreenTourTests` conventions.
4. **`IOSScreenTourTests`** — add a tour state showing `TasksScreen`
   mid-drag (frozen mock data + mock `DragController` in `.dragging`
   state).
5. **Existing tests:** `TaskStoreOrderingTests` keeps passing
   unchanged. `DragDropInteractionTests` on macOS gets rewritten to
   drive the new controller's drop closure rather than the deleted
   `TaskDropDelegate`.

## Rollout plan

Solo project, commits go directly to `main` with conventional commit
prefixes. Suggested commit boundaries:

1. **`feat(ui): add DragReorder module with controller, session, and overlay`**
   — Build the `DragReorder` module + unit-test the controller in
   isolation. No UI integration yet.
2. **`feat(core): add TaskStore.reparent with cycle detection`** —
   Store API, error cases, unit tests.
3. **`feat(ios): replace .onMove with custom drag-reorder on TasksScreen`**
   — Wire the controller into `TasksView` / `TasksScreen`; remove
   `editModeBinding`, `moveHandler`, `performMove`; route drops to
   `TaskStore.reparent` / `reorder`. Update snapshot baselines and
   tour states.
4. **`refactor(macos): migrate TaskListView to shared DragController`**
   — Remove `TaskDropDelegate.swift` and `DropPosition.swift`. Rewrite
   `DragDropInteractionTests`.
5. **`chore(deploy): bump iOS build number to N`** — bump if running an
   OTA test build.

## Open questions

None at design time. Edge cases noted above are decided defaults; can
revisit during implementation if any feel wrong in practice.
