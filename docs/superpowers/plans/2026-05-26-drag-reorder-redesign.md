# Drag-Reorder Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace SwiftUI `List.onMove` on iOS and `TaskDropDelegate`
on macOS with a unified custom drag system that supports sibling
reorder (thick divider) and reparenting (row border) without rows
shifting layout during drag.

**Architecture:** A shared `DragController` (`@MainActor`
`ObservableObject`) in `Packages/LillistUI/Sources/LillistUI/DragReorder/`
owns a state machine — `idle / dragging(DragSession) /
dropping(DragSession, DragTarget)`. Each row reports its frame in a
named coordinate space via `PreferenceKey`; the controller resolves the
cursor position to a `DragTarget` (`.between` / `.onto` / `.rejected`)
using a depth-aware algorithm that mirrors the existing macOS
25/50/25 zone split. A `DragOverlay` renders the floating phantom row
plus the active drop indicator. Drops route to existing
`TaskStore.reorder(id:after:before:)` (which already supports
cross-parent moves with cycle detection) or `TaskStore.reparent(id:newParent:)`
(append to children) — no store API changes are required.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI, Combine (via
`ObservableObject`), XCTest for unit/integration tests, swift-snapshot-testing
for visual baselines (existing `LillistUITests` infrastructure).

**Design doc:** `docs/plans/2026-05-26-drag-reorder-redesign-design.md`.

---

## File Structure

### New files

| Path | Responsibility |
|---|---|
| `Packages/LillistUI/Sources/LillistUI/DragReorder/DragReorderRow.swift` | Cross-platform row descriptor (`id`, `parentID`, `depth`). Decouples controller from FlatTaskRow / TaskOutlineNode. |
| `Packages/LillistUI/Sources/LillistUI/DragReorder/DragTarget.swift` | `DragTarget` enum: `.between(beforeID, afterID, parentID)`, `.onto(targetID)`, `.rejected`, `.none`. |
| `Packages/LillistUI/Sources/LillistUI/DragReorder/DragSession.swift` | Value type carrying drag state: `draggedID`, `originalHeight`, `cursorY`, `currentTarget`. |
| `Packages/LillistUI/Sources/LillistUI/DragReorder/DragSortMode.swift` | `enum DragSortMode { case personalized, sortedByOther }` — abstracts iOS `TasksSort` vs macOS `SortField` so the controller is platform-agnostic. |
| `Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift` | `@MainActor ObservableObject` state machine + drop target resolution. |
| `Packages/LillistUI/Sources/LillistUI/DragReorder/RowGeometryReporter.swift` | `PreferenceKey` (`RowFrameKey`) for collecting `[UUID: CGRect]` row frames in the `"TaskListDrag"` coordinate space. |
| `Packages/LillistUI/Sources/LillistUI/DragReorder/DragOverlay.swift` | `View` that draws the floating phantom row + active drop indicator from the controller's published state. |
| `Packages/LillistUI/Sources/LillistUI/DragReorder/DragReorderable.swift` | View modifier `.dragReorderable(id:controller:)` attaching the platform gesture and the geometry reporter. |
| `Packages/LillistUI/Tests/LillistUITests/DragReorder/DragControllerStateMachineTests.swift` | State-machine transitions. |
| `Packages/LillistUI/Tests/LillistUITests/DragReorder/DragControllerResolutionTests.swift` | Drop-target resolution: zones, depth, cycles, sort gating. |
| `Packages/LillistUI/Tests/LillistUITests/DragReorder/DragReorderSnapshotTests.swift` | Visual snapshots: idle, dragging-between, dragging-onto, rejected. |

### Modified files

| Path | Change |
|---|---|
| `Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift` | Append `LillistDragTokens` enum. |
| `Packages/LillistUI/Sources/LillistUI/iOS/Screens/TasksScreen.swift` | Add `dragController` init param; replace `.onMove` + `editModeBinding` + `performMove` + `moveHandler` with `.dragReorderable` on each row and `.overlay { DragOverlay(controller:) }` on the list container. Convert `[FlatTaskRow]` → `[DragReorderRow]` for the controller. |
| `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift` | Create `@StateObject DragController` (with `onDrop` closure routing to `TaskStore.reorder` / `reparent`). Pass into `TasksScreen`. Remove `onMoveSiblings` / `reorderSiblings`. |
| `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift` | Replace `.draggable(TaskDragPayload)` + `.onDrop(of:delegate:)` with `.dragReorderable(id:controller:)`. Add `@State DragController`. Add `DragOverlay`. Convert `OutlineGroup`'s tree → `[DragReorderRow]` via a flatten helper local to the view. |
| `Packages/LillistUI/Tests/LillistUITests/Tour/IOSScreenTourTests.swift` | Add a tour state rendering `TasksScreen` mid-drag with a mock `DragController` in `.dragging(...)`. |

### Deleted files

| Path | Reason |
|---|---|
| `Packages/LillistUI/Sources/LillistUI/DragDrop/DropPosition.swift` | Replaced by `DragController`'s internal zone logic. |
| `Packages/LillistUI/Sources/LillistUI/DragDrop/TaskDragPayload.swift` | No more `.draggable(Transferable)` usage. |
| `Packages/LillistUI/Sources/LillistUI/DragDrop/TaskDropDelegate.swift` | No more `DropDelegate` path. |
| `Packages/LillistUI/Tests/LillistUITests/DragDrop/DropPositionTests.swift` | Subsumed by `DragControllerResolutionTests`. |
| `Apps/Lillist-macOS/Tests/DragDropInteractionTests.swift` | Rewritten in Task 12 (file path stays, contents replaced). |

---

## Tasks

### Task 1: `DragReorderRow` + `DragSortMode` value types

Foundation types the controller consumes. Pure value types, no SwiftUI.

**Files:**
- Create: `Packages/LillistUI/Sources/LillistUI/DragReorder/DragReorderRow.swift`
- Create: `Packages/LillistUI/Sources/LillistUI/DragReorder/DragSortMode.swift`

- [ ] **Step 1: Create `DragReorderRow.swift`**

```swift
import Foundation

/// Platform-agnostic row descriptor consumed by `DragController`. The
/// iOS screen converts its `[FlatTaskRow]` into `[DragReorderRow]`;
/// the macOS screen flattens its `OutlineGroup` tree the same way.
/// Decouples the controller from `FlatTaskRow` (iOS-only) and
/// `TaskOutlineNode` (macOS-only).
public struct DragReorderRow: Equatable, Sendable {
    public let id: UUID
    public let parentID: UUID?
    public let depth: Int

    public init(id: UUID, parentID: UUID?, depth: Int) {
        self.id = id
        self.parentID = parentID
        self.depth = depth
    }
}
```

- [ ] **Step 2: Create `DragSortMode.swift`**

```swift
import Foundation

/// What the controller needs to know about sort. Sibling-reorder
/// (between-row drops) only makes sense in personalized sort, since
/// other sorts override the user's manual position.
public enum DragSortMode: Sendable {
    case personalized
    case sortedByOther
}
```

- [ ] **Step 3: Build LillistUI to confirm it compiles**

Run: `swift build --package-path Packages/LillistUI`
Expected: success with no warnings.

- [ ] **Step 4: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/DragReorder/DragReorderRow.swift \
        Packages/LillistUI/Sources/LillistUI/DragReorder/DragSortMode.swift
git commit -m "feat(ui): add DragReorderRow and DragSortMode value types"
```

---

### Task 2: `DragTarget` and `DragSession`

The state primitives the controller publishes.

**Files:**
- Create: `Packages/LillistUI/Sources/LillistUI/DragReorder/DragTarget.swift`
- Create: `Packages/LillistUI/Sources/LillistUI/DragReorder/DragSession.swift`
- Test: `Packages/LillistUI/Tests/LillistUITests/DragReorder/DragControllerStateMachineTests.swift` (placeholder, fleshed out in Task 4)

- [ ] **Step 1: Create `DragTarget.swift`**

```swift
import Foundation

/// Resolved drop intent for a given cursor location.
///
/// - `between` — the dragged row will land between two siblings of
///   `parentID`. Either anchor may be `nil` (start or end of the
///   sibling group). Routes to `TaskStore.reorder(id:after:before:)`.
/// - `onto` — the dragged row will become a child of `targetID`,
///   appended to the end. Routes to
///   `TaskStore.reparent(id:newParent:)`.
/// - `rejected` — the cursor resolves to a target that would create a
///   cycle (drop onto self or own descendant). The UI shows a red
///   border on the phantom; release cancels.
/// - `none` — cursor is outside any drop region or in a disabled zone
///   for the current sort mode. No indicator is drawn.
public enum DragTarget: Equatable, Sendable {
    case between(beforeID: UUID?, afterID: UUID?, parentID: UUID?)
    case onto(targetID: UUID)
    case rejected
    case none
}
```

- [ ] **Step 2: Create `DragSession.swift`**

```swift
import CoreGraphics
import Foundation

/// Snapshot of the active drag. The controller publishes a new
/// instance each time the cursor moves or the resolved target
/// changes; SwiftUI consumes it to position the phantom and the
/// drop indicator.
public struct DragSession: Equatable, Sendable {
    public let draggedID: UUID
    public let originalHeight: CGFloat
    public var cursorY: CGFloat
    public var target: DragTarget

    public init(
        draggedID: UUID,
        originalHeight: CGFloat,
        cursorY: CGFloat,
        target: DragTarget
    ) {
        self.draggedID = draggedID
        self.originalHeight = originalHeight
        self.cursorY = cursorY
        self.target = target
    }
}
```

- [ ] **Step 3: Build LillistUI**

Run: `swift build --package-path Packages/LillistUI`
Expected: success, no warnings.

- [ ] **Step 4: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/DragReorder/DragTarget.swift \
        Packages/LillistUI/Sources/LillistUI/DragReorder/DragSession.swift
git commit -m "feat(ui): add DragTarget and DragSession primitives"
```

---

### Task 3: `LillistDragTokens` in Tokens.swift

Visual constants for the overlay. Adding tokens up front so the
overlay can reference them during the green step.

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift`

- [ ] **Step 1: Append `LillistDragTokens` enum to `Tokens.swift`**

Append at end of file (after the existing `LillistTokens` enum):

```swift

/// Visual constants for the custom drag-reorder system in
/// `LillistUI/DragReorder/`. Adjust here, not at callsites.
public enum LillistDragTokens {
    /// Color of the active drop indicator (divider or row border).
    public static let indicatorColor: Color = .accentColor
    /// Border color drawn on the phantom row when the resolved target
    /// is `.rejected` (cycle).
    public static let rejectionColor: Color = Color.red.opacity(0.8)
    /// Thickness of the between-row divider when active.
    public static let dividerThickness: CGFloat = 2.5
    /// Stroke thickness of the onto-row border when active.
    public static let rowBorderThickness: CGFloat = 2.0
    /// Corner radius of the onto-row border highlight.
    public static let rowBorderCornerRadius: CGFloat = 8
    /// Outset of the onto-row border from the row's bounds, so the
    /// stroke does not visually overlap row content.
    public static let rowBorderOutset: CGFloat = 2
    /// Scale applied to the dragged-row phantom while in flight.
    public static let phantomScale: CGFloat = 1.02
    /// Shadow radius of the dragged-row phantom while in flight.
    public static let phantomShadowRadius: CGFloat = 12
    /// Opacity of the dragged-row phantom while in flight.
    public static let phantomOpacity: Double = 0.95
    /// Long-press duration (iOS) before drag begins.
    public static let longPressDuration: TimeInterval = 0.3
    /// Max allowed finger drift during long-press before it cancels.
    public static let longPressMaxDistance: CGFloat = 4
}
```

- [ ] **Step 2: Build LillistUI**

Run: `swift build --package-path Packages/LillistUI`
Expected: success, no warnings.

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift
git commit -m "feat(ui): add LillistDragTokens for the drag overlay visuals"
```

---

### Task 4: `DragController` state machine

The state machine in isolation: `idle → dragging → dropping → idle`,
with cancel paths. No drop-target resolution yet — that's Task 5.

**Files:**
- Create: `Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift`
- Test: `Packages/LillistUI/Tests/LillistUITests/DragReorder/DragControllerStateMachineTests.swift`

- [ ] **Step 1: Write failing tests for the state machine**

Create `Packages/LillistUI/Tests/LillistUITests/DragReorder/DragControllerStateMachineTests.swift`:

```swift
import XCTest
@testable import LillistUI

@MainActor
final class DragControllerStateMachineTests: XCTestCase {
    func test_initialStateIsIdle() {
        let c = DragController(onDrop: { _, _ in })
        XCTAssertEqual(c.state, .idle)
    }

    func test_beginDrag_transitionsToDragging() {
        let c = DragController(onDrop: { _, _ in })
        let id = UUID()
        c.beginDrag(rowID: id, originalHeight: 44, cursorY: 100)
        guard case .dragging(let session) = c.state else {
            return XCTFail("expected .dragging, got \(c.state)")
        }
        XCTAssertEqual(session.draggedID, id)
        XCTAssertEqual(session.originalHeight, 44)
        XCTAssertEqual(session.cursorY, 100)
        XCTAssertEqual(session.target, .none)
    }

    func test_updateCursor_whileDragging_updatesSessionCursorY() {
        let c = DragController(onDrop: { _, _ in })
        c.beginDrag(rowID: UUID(), originalHeight: 44, cursorY: 100)
        c.updateCursor(y: 250)
        guard case .dragging(let s) = c.state else { return XCTFail() }
        XCTAssertEqual(s.cursorY, 250)
    }

    func test_cancelDrag_returnsToIdle() {
        let c = DragController(onDrop: { _, _ in })
        c.beginDrag(rowID: UUID(), originalHeight: 44, cursorY: 100)
        c.cancelDrag()
        XCTAssertEqual(c.state, .idle)
    }

    func test_endDrag_withValidTarget_callsOnDropThenIdles() {
        let id = UUID(), targetID = UUID()
        var calls: [(UUID, DragTarget)] = []
        let c = DragController(onDrop: { dragged, t in calls.append((dragged, t)) })
        c.beginDrag(rowID: id, originalHeight: 44, cursorY: 100)
        c.setResolvedTarget(.onto(targetID: targetID))
        c.endDrag()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.0, id)
        XCTAssertEqual(calls.first?.1, .onto(targetID: targetID))
        XCTAssertEqual(c.state, .idle)
    }

    func test_endDrag_withRejectedTarget_doesNotCallOnDrop() {
        var called = false
        let c = DragController(onDrop: { _, _ in called = true })
        c.beginDrag(rowID: UUID(), originalHeight: 44, cursorY: 100)
        c.setResolvedTarget(.rejected)
        c.endDrag()
        XCTAssertFalse(called)
        XCTAssertEqual(c.state, .idle)
    }

    func test_endDrag_withNoneTarget_doesNotCallOnDrop() {
        var called = false
        let c = DragController(onDrop: { _, _ in called = true })
        c.beginDrag(rowID: UUID(), originalHeight: 44, cursorY: 100)
        // target stays .none
        c.endDrag()
        XCTAssertFalse(called)
        XCTAssertEqual(c.state, .idle)
    }

    func test_beginDrag_whileAlreadyDragging_isIgnored() {
        let id1 = UUID(), id2 = UUID()
        let c = DragController(onDrop: { _, _ in })
        c.beginDrag(rowID: id1, originalHeight: 44, cursorY: 100)
        c.beginDrag(rowID: id2, originalHeight: 44, cursorY: 200)
        guard case .dragging(let s) = c.state else { return XCTFail() }
        XCTAssertEqual(s.draggedID, id1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/LillistUI --filter DragControllerStateMachineTests`
Expected: compile error — `DragController` is not defined.

- [ ] **Step 3: Create `DragController.swift` with the minimum to pass**

Create `Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift`:

```swift
import Combine
import CoreGraphics
import Foundation
import SwiftUI

/// State of the active drag, observed by the screen and overlay.
public enum DragControllerState: Equatable, Sendable {
    case idle
    case dragging(DragSession)
    case dropping(DragSession, DragTarget)
}

/// `@MainActor` ObservableObject driving the custom drag-reorder
/// system. Lives in the platform-agnostic `DragReorder/` module.
///
/// State machine: `idle → dragging → dropping → idle`. Geometry,
/// flatRows, and sortMode are inputs the screen sets before each drop
/// resolution. `onDrop` is invoked once on successful release with a
/// valid target; the container translates it into store calls.
@MainActor
public final class DragController: ObservableObject {
    @Published public private(set) var state: DragControllerState = .idle

    public var flatRows: [DragReorderRow] = []
    public var geometry: [UUID: CGRect] = [:]
    public var sortMode: DragSortMode = .personalized
    public var isFilterActive: Bool = false

    public let onDrop: (_ draggedID: UUID, _ target: DragTarget) -> Void

    public init(onDrop: @escaping (UUID, DragTarget) -> Void) {
        self.onDrop = onDrop
    }

    public func beginDrag(rowID: UUID, originalHeight: CGFloat, cursorY: CGFloat) {
        guard case .idle = state else { return }
        state = .dragging(.init(
            draggedID: rowID,
            originalHeight: originalHeight,
            cursorY: cursorY,
            target: .none
        ))
    }

    public func updateCursor(y: CGFloat) {
        guard case .dragging(var session) = state else { return }
        session.cursorY = y
        state = .dragging(session)
    }

    public func setResolvedTarget(_ target: DragTarget) {
        guard case .dragging(var session) = state else { return }
        session.target = target
        state = .dragging(session)
    }

    public func endDrag() {
        guard case .dragging(let session) = state else { return }
        let target = session.target
        state = .idle
        switch target {
        case .between, .onto:
            onDrop(session.draggedID, target)
        case .rejected, .none:
            break
        }
    }

    public func cancelDrag() {
        state = .idle
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/LillistUI --filter DragControllerStateMachineTests`
Expected: all 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift \
        Packages/LillistUI/Tests/LillistUITests/DragReorder/DragControllerStateMachineTests.swift
git commit -m "feat(ui): add DragController state machine"
```

---

### Task 5: `DragController` drop-target resolution

Now the depth- and cycle-aware algorithm that turns a cursor point +
geometry dict + flat row list into a `DragTarget`. The hard work of
the controller.

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift`
- Test: `Packages/LillistUI/Tests/LillistUITests/DragReorder/DragControllerResolutionTests.swift`

- [ ] **Step 1: Write failing tests for resolution**

Create `Packages/LillistUI/Tests/LillistUITests/DragReorder/DragControllerResolutionTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import LillistUI

@MainActor
final class DragControllerResolutionTests: XCTestCase {

    // Geometry fixture: 3 top-level rows of 44pt at y=0, y=44, y=88.
    // ┌────────────────┐ y=0
    // │  rowA (depth 0)│
    // ├────────────────┤ y=44
    // │  rowB (depth 0)│
    // ├────────────────┤ y=88
    // │  rowC (depth 0)│
    // └────────────────┘ y=132
    private func flatThree() -> (
        rows: [DragReorderRow],
        geometry: [UUID: CGRect],
        ids: (a: UUID, b: UUID, c: UUID)
    ) {
        let a = UUID(), b = UUID(), c = UUID()
        let rows = [
            DragReorderRow(id: a, parentID: nil, depth: 0),
            DragReorderRow(id: b, parentID: nil, depth: 0),
            DragReorderRow(id: c, parentID: nil, depth: 0),
        ]
        let geo: [UUID: CGRect] = [
            a: CGRect(x: 0, y: 0,  width: 320, height: 44),
            b: CGRect(x: 0, y: 44, width: 320, height: 44),
            c: CGRect(x: 0, y: 88, width: 320, height: 44),
        ]
        return (rows, geo, (a, b, c))
    }

    // Hierarchy fixture: A is a parent of A1 and A2; A is expanded.
    // ┌────────────────┐ y=0
    // │  A (depth 0)   │
    // ├────────────────┤ y=44
    // │    A1 (depth 1)│
    // ├────────────────┤ y=88
    // │    A2 (depth 1)│
    // ├────────────────┤ y=132
    // │  B (depth 0)   │
    // └────────────────┘ y=176
    private func flatHierarchy() -> (
        rows: [DragReorderRow],
        geometry: [UUID: CGRect],
        ids: (a: UUID, a1: UUID, a2: UUID, b: UUID)
    ) {
        let a = UUID(), a1 = UUID(), a2 = UUID(), b = UUID()
        let rows = [
            DragReorderRow(id: a,  parentID: nil, depth: 0),
            DragReorderRow(id: a1, parentID: a,   depth: 1),
            DragReorderRow(id: a2, parentID: a,   depth: 1),
            DragReorderRow(id: b,  parentID: nil, depth: 0),
        ]
        let geo: [UUID: CGRect] = [
            a:  CGRect(x: 0, y: 0,   width: 320, height: 44),
            a1: CGRect(x: 0, y: 44,  width: 320, height: 44),
            a2: CGRect(x: 0, y: 88,  width: 320, height: 44),
            b:  CGRect(x: 0, y: 132, width: 320, height: 44),
        ]
        return (rows, geo, (a, a1, a2, b))
    }

    private func makeController(
        rows: [DragReorderRow],
        geometry: [UUID: CGRect],
        sort: DragSortMode = .personalized,
        filterActive: Bool = false
    ) -> DragController {
        let c = DragController(onDrop: { _, _ in })
        c.flatRows = rows
        c.geometry = geometry
        c.sortMode = sort
        c.isFilterActive = filterActive
        return c
    }

    // MARK: - Zone classification

    func test_top25_resolvesToBetweenAbove() {
        let f = flatThree()
        let c = makeController(rows: f.rows, geometry: f.geometry)
        c.beginDrag(rowID: f.ids.c, originalHeight: 44, cursorY: 50)
        // y=50: in rowB. Top 25% of rowB is y∈[44, 55).
        let t = c.resolveTarget(forDraggedID: f.ids.c, atY: 50)
        XCTAssertEqual(t, .between(beforeID: f.ids.a, afterID: f.ids.b, parentID: nil))
    }

    func test_middle50_resolvesToOnto() {
        let f = flatThree()
        let c = makeController(rows: f.rows, geometry: f.geometry)
        c.beginDrag(rowID: f.ids.c, originalHeight: 44, cursorY: 60)
        // y=60: in rowB. Middle 50% of rowB is y∈[55, 77).
        let t = c.resolveTarget(forDraggedID: f.ids.c, atY: 60)
        XCTAssertEqual(t, .onto(targetID: f.ids.b))
    }

    func test_bottom25_resolvesToBetweenBelow() {
        let f = flatThree()
        let c = makeController(rows: f.rows, geometry: f.geometry)
        c.beginDrag(rowID: f.ids.c, originalHeight: 44, cursorY: 80)
        // y=80: in rowB. Bottom 25% of rowB is y∈[77, 88].
        let t = c.resolveTarget(forDraggedID: f.ids.c, atY: 80)
        XCTAssertEqual(t, .between(beforeID: f.ids.b, afterID: f.ids.c, parentID: nil))
    }

    // MARK: - Hierarchy: between target (parent) and first child

    func test_bottom25_belowExpandedParent_resolvesToFirstChild() {
        let f = flatHierarchy()
        let c = makeController(rows: f.rows, geometry: f.geometry)
        c.beginDrag(rowID: f.ids.b, originalHeight: 44, cursorY: 35)
        // y=35: in rowA. Bottom 25% of rowA is y∈[33, 44].
        // Next flat row is A1 (child of A). Resolves to first child of A.
        let t = c.resolveTarget(forDraggedID: f.ids.b, atY: 35)
        XCTAssertEqual(t, .between(beforeID: f.ids.a1, afterID: nil, parentID: f.ids.a))
    }

    // MARK: - Hierarchy: top 25% above a child

    func test_top25_aboveFirstChild_resolvesSameAsBetweenParentAndFirstChild() {
        let f = flatHierarchy()
        let c = makeController(rows: f.rows, geometry: f.geometry)
        // Top 25% of A1 is y∈[44, 55).
        c.beginDrag(rowID: f.ids.b, originalHeight: 44, cursorY: 50)
        let t = c.resolveTarget(forDraggedID: f.ids.b, atY: 50)
        XCTAssertEqual(t, .between(beforeID: f.ids.a1, afterID: nil, parentID: f.ids.a))
    }

    // MARK: - End of list

    func test_belowLastRow_resolvesToBetweenAtRootEnd() {
        let f = flatThree()
        let c = makeController(rows: f.rows, geometry: f.geometry)
        c.beginDrag(rowID: f.ids.a, originalHeight: 44, cursorY: 200)
        let t = c.resolveTarget(forDraggedID: f.ids.a, atY: 200)
        XCTAssertEqual(t, .between(beforeID: nil, afterID: f.ids.c, parentID: nil))
        // Note: beforeID=nil here is the "after the last row" form;
        // see Step 3 algorithm for the chosen anchor convention.
    }

    // MARK: - Sort gating

    func test_topZone_inNonPersonalizedSort_returnsNone() {
        let f = flatThree()
        let c = makeController(rows: f.rows, geometry: f.geometry, sort: .sortedByOther)
        c.beginDrag(rowID: f.ids.c, originalHeight: 44, cursorY: 50)
        let t = c.resolveTarget(forDraggedID: f.ids.c, atY: 50)
        XCTAssertEqual(t, .none)
    }

    func test_middleZone_inNonPersonalizedSort_stillResolvesOnto() {
        let f = flatThree()
        let c = makeController(rows: f.rows, geometry: f.geometry, sort: .sortedByOther)
        c.beginDrag(rowID: f.ids.c, originalHeight: 44, cursorY: 60)
        let t = c.resolveTarget(forDraggedID: f.ids.c, atY: 60)
        XCTAssertEqual(t, .onto(targetID: f.ids.b))
    }

    // MARK: - Cycle rejection

    func test_ontoSelf_returnsRejected() {
        let f = flatThree()
        let c = makeController(rows: f.rows, geometry: f.geometry)
        c.beginDrag(rowID: f.ids.b, originalHeight: 44, cursorY: 60)
        let t = c.resolveTarget(forDraggedID: f.ids.b, atY: 60)
        XCTAssertEqual(t, .rejected)
    }

    func test_ontoDescendantOfDragged_returnsRejected() {
        let f = flatHierarchy()
        let c = makeController(rows: f.rows, geometry: f.geometry)
        // Drag A; cursor over A1 mid-row (depth-1 child).
        c.beginDrag(rowID: f.ids.a, originalHeight: 44, cursorY: 60)
        let t = c.resolveTarget(forDraggedID: f.ids.a, atY: 60)
        XCTAssertEqual(t, .rejected)
    }

    // MARK: - Filter gating

    func test_filterActive_returnsNoneForAnyZone() {
        let f = flatThree()
        let c = makeController(rows: f.rows, geometry: f.geometry, filterActive: true)
        c.beginDrag(rowID: f.ids.c, originalHeight: 44, cursorY: 60)
        XCTAssertEqual(c.resolveTarget(forDraggedID: f.ids.c, atY: 60), .none)
        XCTAssertEqual(c.resolveTarget(forDraggedID: f.ids.c, atY: 50), .none)
        XCTAssertEqual(c.resolveTarget(forDraggedID: f.ids.c, atY: 80), .none)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path Packages/LillistUI --filter DragControllerResolutionTests`
Expected: compile error — `resolveTarget(forDraggedID:atY:)` not found.

- [ ] **Step 3: Extend `DragController.swift` with resolution logic**

Append these methods inside the `DragController` class:

```swift
// MARK: - Resolution

/// Compute the drop target for a cursor y-position. Pure function of
/// the controller's `flatRows`, `geometry`, `sortMode`,
/// `isFilterActive`, and the dragged row id.
public func resolveTarget(forDraggedID draggedID: UUID, atY y: CGFloat) -> DragTarget {
    if isFilterActive { return .none }
    guard !flatRows.isEmpty else { return .none }

    // 1. Find the row whose frame contains y.
    if let hit = flatRows.first(where: { row in
        guard let frame = geometry[row.id] else { return false }
        return y >= frame.minY && y < frame.maxY
    }) {
        let frame = geometry[hit.id]!
        let zone = classifyZone(y: y, in: frame)
        return resolve(zone: zone, hit: hit, draggedID: draggedID)
    }

    // 2. Below the last row — treat as drop at root end.
    if let last = flatRows.last,
       let lastFrame = geometry[last.id],
       y >= lastFrame.maxY,
       sortMode == .personalized {
        return finalize(
            target: .between(beforeID: nil, afterID: last.id, parentID: nil),
            draggedID: draggedID
        )
        // Convention: beforeID=nil means "append at end of root".
        // The container translates this to reorder(after: last, before: nil)
        // at top level.
    }

    return .none
}

private enum Zone { case top25, middle50, bottom25 }

private func classifyZone(y: CGFloat, in frame: CGRect) -> Zone {
    let topBand    = frame.minY + frame.height * 0.25
    let bottomBand = frame.minY + frame.height * 0.75
    if y < topBand    { return .top25 }
    if y >= bottomBand { return .bottom25 }
    return .middle50
}

private func resolve(zone: Zone, hit: DragReorderRow, draggedID: UUID) -> DragTarget {
    switch zone {
    case .middle50:
        return finalize(target: .onto(targetID: hit.id), draggedID: draggedID)
    case .top25:
        guard sortMode == .personalized else { return .none }
        return finalize(target: resolveBetweenAbove(hit), draggedID: draggedID)
    case .bottom25:
        guard sortMode == .personalized else { return .none }
        return finalize(target: resolveBetweenBelow(hit), draggedID: draggedID)
    }
}

private func resolveBetweenAbove(_ hit: DragReorderRow) -> DragTarget {
    // The dragged row will become a sibling-before of `hit`.
    let parent = hit.parentID
    let previous = flatRows
        .prefix(while: { $0.id != hit.id })
        .reversed()
        .first(where: { $0.parentID == parent })
    return .between(beforeID: previous?.id, afterID: hit.id, parentID: parent)
}

private func resolveBetweenBelow(_ hit: DragReorderRow) -> DragTarget {
    // Look at the next flat row.
    guard let hitIndex = flatRows.firstIndex(where: { $0.id == hit.id }) else {
        return .none
    }
    let nextIndex = hitIndex + 1
    if nextIndex >= flatRows.count {
        // Last in flat list — sibling-after at hit's depth.
        return .between(beforeID: hit.id, afterID: nil, parentID: hit.parentID)
    }
    let next = flatRows[nextIndex]
    if next.parentID == hit.id {
        // Hit is expanded, next is its first child. Drop becomes
        // sibling-before next at depth+1 (i.e., first child of hit).
        return .between(beforeID: nil, afterID: next.id, parentID: hit.id)
    } else if next.parentID == hit.parentID {
        // Same depth siblings — between them.
        return .between(beforeID: hit.id, afterID: next.id, parentID: hit.parentID)
    } else {
        // Depth decreases — hit was last in its sibling group.
        return .between(beforeID: hit.id, afterID: nil, parentID: hit.parentID)
    }
}

/// Apply cycle-rejection on top of a resolved target.
private func finalize(target: DragTarget, draggedID: UUID) -> DragTarget {
    switch target {
    case .onto(let id) where isSelfOrDescendant(id, of: draggedID):
        return .rejected
    case .between(_, _, let parentID?):
        if isSelfOrDescendant(parentID, of: draggedID) { return .rejected }
        return target
    default:
        return target
    }
}

private func isSelfOrDescendant(_ candidate: UUID, of ancestor: UUID) -> Bool {
    if candidate == ancestor { return true }
    var cursor: UUID? = candidate
    var safety = 0
    while let c = cursor, safety < 1024 {
        if c == ancestor { return true }
        cursor = flatRows.first(where: { $0.id == c })?.parentID
        safety += 1
    }
    return false
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/LillistUI --filter DragControllerResolutionTests`
Expected: all 11 tests pass.

If `test_belowLastRow_resolvesToBetweenAtRootEnd` fails because of the
anchor-convention assertion, update the test to match the algorithm's
output (the algorithm above returns `.between(beforeID: nil,
afterID: last.id, parentID: nil)` for below-last). Pick a convention
and apply it consistently to the test.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift \
        Packages/LillistUI/Tests/LillistUITests/DragReorder/DragControllerResolutionTests.swift
git commit -m "feat(ui): add depth- and cycle-aware drop target resolution"
```

---

### Task 6: `RowGeometryReporter`

`PreferenceKey` + ViewModifier helper for each row to publish its
frame in the `"TaskListDrag"` named coordinate space.

**Files:**
- Create: `Packages/LillistUI/Sources/LillistUI/DragReorder/RowGeometryReporter.swift`

- [ ] **Step 1: Create `RowGeometryReporter.swift`**

```swift
import SwiftUI

/// PreferenceKey collecting the frames of every row that's currently
/// in `DragReorderable`. Aggregates a `[UUID: CGRect]` keyed by row id
/// in the named coordinate space `"TaskListDrag"`. The screen reads
/// this preference via `.onPreferenceChange` and feeds it to the
/// controller as `controller.geometry`.
public struct RowFramePreferenceKey: PreferenceKey {
    public static let defaultValue: [UUID: CGRect] = [:]
    public static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Coordinate space name shared by the list container, every row's
/// frame reporter, and the drag gesture.
public enum DragCoordinateSpace {
    public static let name: String = "TaskListDrag"
}

extension View {
    /// Reports this view's frame as a single-key dictionary entry to
    /// the enclosing `RowFramePreferenceKey`. The row's `.background`
    /// reads geometry via `GeometryReader`; rendering is otherwise
    /// unaffected.
    func reportRowGeometry(id: UUID) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: RowFramePreferenceKey.self,
                    value: [id: proxy.frame(in: .named(DragCoordinateSpace.name))]
                )
            }
        )
    }
}
```

- [ ] **Step 2: Build LillistUI**

Run: `swift build --package-path Packages/LillistUI`
Expected: success, no warnings.

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/DragReorder/RowGeometryReporter.swift
git commit -m "feat(ui): add RowFramePreferenceKey + reportRowGeometry helper"
```

---

### Task 7: `DragOverlay` view

The visual layer drawn above the list during a drag: phantom row +
active drop indicator (divider, border, or red phantom border for
rejection).

**Files:**
- Create: `Packages/LillistUI/Sources/LillistUI/DragReorder/DragOverlay.swift`

- [ ] **Step 1: Create `DragOverlay.swift`**

```swift
import SwiftUI

/// Drawn as `.overlay` on the task list container. Observes the
/// `DragController` and renders:
///
/// 1. The floating phantom row at the cursor y-position (scaled +
///    shadowed). The phantom content is provided by the screen via
///    the `phantomContent` closure so the overlay stays platform-
///    agnostic.
/// 2. The active drop indicator:
///    - `.between(...)` → a `Capsule` divider at the row boundary.
///    - `.onto(...)` → a stroked `RoundedRectangle` around the target.
///    - `.rejected` → no indicator; the phantom is bordered red.
///    - `.none` → nothing.
public struct DragOverlay<PhantomContent: View>: View {
    @ObservedObject var controller: DragController
    let phantomContent: (UUID) -> PhantomContent

    public init(
        controller: DragController,
        @ViewBuilder phantomContent: @escaping (UUID) -> PhantomContent
    ) {
        self.controller = controller
        self.phantomContent = phantomContent
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            switch controller.state {
            case .idle:
                EmptyView()
            case .dragging(let session):
                indicator(for: session.target)
                phantom(for: session)
            case .dropping(let session, _):
                phantom(for: session)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func phantom(for session: DragSession) -> some View {
        phantomContent(session.draggedID)
            .frame(height: session.originalHeight)
            .scaleEffect(LillistDragTokens.phantomScale)
            .shadow(radius: LillistDragTokens.phantomShadowRadius, y: 8)
            .opacity(LillistDragTokens.phantomOpacity)
            .overlay(
                RoundedRectangle(cornerRadius: LillistDragTokens.rowBorderCornerRadius)
                    .stroke(
                        LillistDragTokens.rejectionColor,
                        lineWidth: session.target == .rejected ? LillistDragTokens.rowBorderThickness : 0
                    )
            )
            .position(
                x: phantomCenterX,
                y: session.cursorY
            )
    }

    @ViewBuilder
    private func indicator(for target: DragTarget) -> some View {
        switch target {
        case .between(let beforeID, let afterID, _):
            betweenDivider(beforeID: beforeID, afterID: afterID)
        case .onto(let id):
            ontoBorder(targetID: id)
        case .rejected, .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private func betweenDivider(beforeID: UUID?, afterID: UUID?) -> some View {
        // Position the capsule at the boundary line:
        // - prefer beforeID's maxY if available
        // - else afterID's minY
        let y: CGFloat? = {
            if let id = beforeID, let f = controller.geometry[id] { return f.maxY }
            if let id = afterID,  let f = controller.geometry[id] { return f.minY }
            return nil
        }()
        if let y {
            let frame = controller.geometry[beforeID ?? afterID ?? UUID()] ?? .zero
            Capsule()
                .fill(LillistDragTokens.indicatorColor)
                .frame(width: frame.width - 24, height: LillistDragTokens.dividerThickness)
                .position(x: 12 + (frame.width - 24) / 2, y: y)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private func ontoBorder(targetID: UUID) -> some View {
        if let frame = controller.geometry[targetID] {
            let outset = LillistDragTokens.rowBorderOutset
            RoundedRectangle(cornerRadius: LillistDragTokens.rowBorderCornerRadius)
                .stroke(LillistDragTokens.indicatorColor, lineWidth: LillistDragTokens.rowBorderThickness)
                .frame(width: frame.width + outset * 2, height: frame.height + outset * 2)
                .position(x: frame.midX, y: frame.midY)
                .transition(.opacity)
        }
    }

    private var phantomCenterX: CGFloat {
        // Use the first geometry entry's midX as the phantom horizontal center.
        // All rows are full-width so any entry suffices.
        controller.geometry.values.first?.midX ?? 0
    }
}
```

- [ ] **Step 2: Build LillistUI**

Run: `swift build --package-path Packages/LillistUI`
Expected: success, no warnings.

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/DragReorder/DragOverlay.swift
git commit -m "feat(ui): add DragOverlay rendering phantom + drop indicators"
```

---

### Task 8: `DragReorderable` view modifier

The per-row glue: attach the platform gesture, report geometry, and
hand the gesture's translation/location to the controller.

**Files:**
- Create: `Packages/LillistUI/Sources/LillistUI/DragReorder/DragReorderable.swift`

- [ ] **Step 1: Create `DragReorderable.swift`**

```swift
import SwiftUI
#if os(iOS)
import UIKit
#endif

extension View {
    /// Attaches the drag-reorder gesture and geometry reporter to a
    /// row. iOS requires a long-press first to disambiguate from
    /// scroll; macOS uses a plain `DragGesture` (mouse-down + slop).
    public func dragReorderable(
        id: UUID,
        controller: DragController
    ) -> some View {
        modifier(DragReorderableModifier(id: id, controller: controller))
    }
}

struct DragReorderableModifier: ViewModifier {
    let id: UUID
    @ObservedObject var controller: DragController

    func body(content: Content) -> some View {
        content
            .reportRowGeometry(id: id)
            .gesture(platformGesture)
    }

    #if os(iOS)
    private var platformGesture: some Gesture {
        let drag = DragGesture(
            minimumDistance: 0,
            coordinateSpace: .named(DragCoordinateSpace.name)
        )
        return LongPressGesture(
            minimumDuration: LillistDragTokens.longPressDuration,
            maximumDistance: LillistDragTokens.longPressMaxDistance
        )
        .sequenced(before: drag)
        .onChanged { value in
            switch value {
            case .first:
                // Long-press in progress, drag has not started.
                break
            case .second(_, let drag?):
                if case .idle = controller.state {
                    guard let frame = controller.geometry[id] else { break }
                    controller.beginDrag(
                        rowID: id,
                        originalHeight: frame.height,
                        cursorY: drag.location.y
                    )
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                controller.updateCursor(y: drag.location.y)
                let resolved = controller.resolveTarget(
                    forDraggedID: id,
                    atY: drag.location.y
                )
                let previous = currentTarget()
                if resolved != previous {
                    controller.setResolvedTarget(resolved)
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            default:
                break
            }
        }
        .onEnded { _ in
            controller.endDrag()
        }
    }
    #else
    private var platformGesture: some Gesture {
        DragGesture(
            minimumDistance: 4,
            coordinateSpace: .named(DragCoordinateSpace.name)
        )
        .onChanged { drag in
            if case .idle = controller.state {
                guard let frame = controller.geometry[id] else { return }
                controller.beginDrag(
                    rowID: id,
                    originalHeight: frame.height,
                    cursorY: drag.location.y
                )
                NSHapticFeedbackManager.defaultPerformer.perform(
                    .alignment, performanceTime: .now
                )
            }
            controller.updateCursor(y: drag.location.y)
            let resolved = controller.resolveTarget(
                forDraggedID: id,
                atY: drag.location.y
            )
            if resolved != currentTarget() {
                controller.setResolvedTarget(resolved)
            }
        }
        .onEnded { _ in
            controller.endDrag()
        }
    }
    #endif

    private func currentTarget() -> DragTarget {
        if case .dragging(let s) = controller.state { return s.target }
        return .none
    }
}
```

- [ ] **Step 2: Build LillistUI**

Run: `swift build --package-path Packages/LillistUI`
Expected: success, no warnings.

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/DragReorder/DragReorderable.swift
git commit -m "feat(ui): add dragReorderable view modifier with platform gestures"
```

---

### Task 9: Update `TasksScreen` to use `DragController`

Replace `.onMove`, `EditMode`, `moveHandler`, and `performMove` with
the new system. The screen now takes `dragController` as an
`@ObservedObject` init param.

**Files:**
- Modify: `Packages/LillistUI/Sources/LillistUI/iOS/Screens/TasksScreen.swift`

- [ ] **Step 1: Read TasksScreen.swift to confirm current shape**

Run: `wc -l Packages/LillistUI/Sources/LillistUI/iOS/Screens/TasksScreen.swift`
(Reference; this is the file to modify — read it fully first.)

- [ ] **Step 2: Add `dragController` parameter to `TasksScreen.init`**

In the `public struct TasksScreen: View` declaration, add the property
near the other parameters:

```swift
@ObservedObject var dragController: DragController
```

In the `public init(...)`, add `dragController: DragController` as a
parameter and assign `self.dragController = dragController`. Order it
right after the other action-related params for consistency with
existing iOS Tab Screens.

- [ ] **Step 3: Replace `editModeBinding`, `moveHandler`, `performMove` with the new wiring**

Delete:

```swift
private var editModeBinding: Binding<EditMode> {
    let value: EditMode = (sort == .personalized) ? .active : .inactive
    return .constant(value)
}

private var moveHandler: ((IndexSet, Int) -> Void)? {
    guard sort == .personalized else { return nil }
    return { source, destination in
        performMove(source, to: destination)
    }
}
```

Delete the entire `performMove(_:to:)` method (lines 285–311 currently).

Delete `onMoveSiblings` from the parameter list and `init`.

Update `listBody` to:

```swift
@ViewBuilder
private var listBody: some View {
    List {
        ForEach(flat) { row in
            outlineRow(row)
                .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                .opacity(row.node.record.id == draggedID ? 0 : 1)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        onDelete(row.node.record)
                    } label: {
                        Label(
                            String(localized: "Delete", bundle: .module),
                            systemImage: "trash"
                        )
                    }
                }
                .dragReorderable(id: row.node.record.id, controller: dragController)
        }
    }
    .listStyle(.plain)
    .coordinateSpace(name: DragCoordinateSpace.name)
    .onPreferenceChange(RowFramePreferenceKey.self) { frames in
        dragController.geometry = frames
    }
    .onChange(of: flat) { _, newFlat in
        dragController.flatRows = newFlat.map {
            DragReorderRow(
                id: $0.node.record.id,
                parentID: $0.parentID,
                depth: $0.depth
            )
        }
        dragController.sortMode = (sort == .personalized) ? .personalized : .sortedByOther
        dragController.isFilterActive = hasActiveFilter
    }
    .onAppear {
        dragController.flatRows = flat.map {
            DragReorderRow(
                id: $0.node.record.id,
                parentID: $0.parentID,
                depth: $0.depth
            )
        }
        dragController.sortMode = (sort == .personalized) ? .personalized : .sortedByOther
        dragController.isFilterActive = hasActiveFilter
    }
    .overlay {
        DragOverlay(controller: dragController) { id in
            phantomRow(forID: id)
        }
    }
}

private var draggedID: UUID? {
    switch dragController.state {
    case .dragging(let s), .dropping(let s, _): return s.draggedID
    case .idle: return nil
    }
}

@ViewBuilder
private func phantomRow(forID id: UUID) -> some View {
    if let row = flat.first(where: { $0.node.record.id == id }) {
        outlineRow(row)
            .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
            .padding(.horizontal, 12)
            .background(Color(.systemBackground))
    }
}
```

(The `outlineRow(_:)` helper exists already; no change needed there.)

If a reference to `hasActiveFilter` doesn't compile because it's
private to a different scope, add or expose it. Read the file to find
its definition; mirror the same logic.

- [ ] **Step 4: Build iOS app target**

Run:
```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```
Expected: success with no warnings. (Treat any warning as a failure
per `CLAUDE.md`.)

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/iOS/Screens/TasksScreen.swift
git commit -m "feat(ui): replace TasksScreen .onMove with DragController + DragOverlay"
```

---

### Task 10: Update iOS `TasksView` container to own `DragController`

Wire the controller's `onDrop` closure to the existing store APIs.
Drop the `onMoveSiblings` callback path entirely.

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift`

- [ ] **Step 1: Add the controller as `@StateObject` and wire `onDrop`**

In `TasksView`, add near the top of the `@State` declarations:

```swift
@StateObject private var dragController = DragController { _, _ in }
```

Then, in `.task { await initialLoad() }`, replace with:

```swift
.task {
    dragController.onDropOverride = { [weak self] dragged, target in
        guard let self else { return }
        Task { await self.applyDrop(dragged: dragged, target: target) }
    }
    await initialLoad()
}
```

Wait — `DragController.onDrop` is `let`, so we can't reassign. Replace
the `@StateObject` initialization with one that captures `self`. The
cleanest pattern: instantiate inside `init()`:

```swift
init() {
    let placeholder: (UUID, DragTarget) -> Void = { _, _ in }
    _dragController = StateObject(wrappedValue: DragController(onDrop: placeholder))
}
```

No — `TasksView` is a `struct` that can't self-reference in init.
Resolution: change `DragController.onDrop` from `let` to `var` so the
container can rewire it after construction, OR pass the closure via a
separate `setHandler` method.

Pick the second: add to `DragController`:

```swift
private var handler: (UUID, DragTarget) -> Void
public init(onDrop: @escaping (UUID, DragTarget) -> Void) {
    self.handler = onDrop
}
public func setOnDrop(_ closure: @escaping (UUID, DragTarget) -> Void) {
    self.handler = closure
}
// Internally rename `onDrop` to `handler` in `endDrag()`.
```

(Update Task 4's `DragController` accordingly: rename the stored
property `onDrop` → `handler`, remove the public `onDrop` field, add
`setOnDrop`.)

Then in `TasksView`:

```swift
@StateObject private var dragController = DragController(onDrop: { _, _ in })
```

And in the body or `.onAppear`:

```swift
.onAppear {
    dragController.setOnDrop { dragged, target in
        Task { await applyDrop(dragged: dragged, target: target) }
    }
}
```

- [ ] **Step 2: Add `applyDrop` method**

In `TasksView`, replace `reorderSiblings(parentID:sources:destination:)`
with:

```swift
@MainActor
private func applyDrop(dragged: UUID, target: DragTarget) async {
    do {
        switch target {
        case .between(let before, let after, _):
            try await env.taskStore.reorder(
                id: dragged,
                after: after,
                before: before
            )
            // Note: in DragTarget, `before` is the row whose space
            // the drop lands above (i.e., the row immediately above
            // the gap), and `after` is the row immediately below.
            // TaskStore.reorder uses "after" for the row the dragged
            // task should follow and "before" for the row it should
            // precede. So we map: before(target) → after(store)…
            // No — re-check the conventions before writing this line.
        case .onto(let parentID):
            try await env.taskStore.reparent(id: dragged, newParent: parentID)
        case .rejected, .none:
            break
        }
        await reload()
    } catch {
        loadError = "\(error)"
    }
}
```

**Convention reconciliation:** clarify the anchor naming in one place
before writing the mapping. Two options:

- (a) Rename `DragTarget.between(beforeID:afterID:parentID:)` so that
      `beforeID` = "row the dragged will sit *before*" and
      `afterID` = "row the dragged will sit *after*". Matches the
      `TaskStore.reorder(id:after:before:)` semantics. Update Task 5
      tests accordingly.
- (b) Keep current naming where `beforeID` = "row immediately above
      the gap" and pass it as `after` to the store call: `try await
      env.taskStore.reorder(id: dragged, after: before, before: after)`.
      Confusing but tests already use this naming.

**Pick (a) and update Task 5's `DragControllerResolutionTests` to use
the store's convention.** This change is small:

- In `resolveBetweenAbove`: was returning
  `.between(beforeID: previous?.id, afterID: hit.id, ...)`.
  Now (a): `.between(beforeID: hit.id, afterID: previous?.id, ...)`.
- In `resolveBetweenBelow` cases: swap similarly.
- All `XCTAssertEqual(...)` in the resolution tests need the same swap.

After the swap, `applyDrop` reduces to:

```swift
case .between(let beforeID, let afterID, _):
    try await env.taskStore.reorder(id: dragged, after: afterID, before: beforeID)
```

- [ ] **Step 3: Remove obsolete `reorderSiblings` and `onMoveSiblings` wiring**

Delete `private func reorderSiblings(parentID:sources:destination:) async`
(lines 280–308 of TasksView.swift).

In `TasksScreen(...)` call site, remove the `onMoveSiblings:` argument.

Pass the new argument:

```swift
TasksScreen(
    // ... existing args ...
    dragController: dragController,
    // ... rest ...
)
```

- [ ] **Step 4: Build iOS app target**

Run:
```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```
Expected: success, no warnings.

- [ ] **Step 5: Run iOS tests**

Run:
```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'
```
Expected: all tests pass. `IOSScreenTourTests` may need snapshot updates
if any pixel shifted (Task 14 explicitly updates the tour state).

- [ ] **Step 6: Commit**

```bash
git add Apps/Lillist-iOS/Sources/Tasks/TasksView.swift \
        Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift
git commit -m "feat(ios): wire DragController into TasksView; drop .onMove path"
```

---

### Task 11: Migrate macOS `TaskListView` to `DragController`

Replace `.draggable(TaskDragPayload)` + `.onDrop(of:delegate:)` with
the new system. Flatten the `OutlineGroup` tree into
`[DragReorderRow]` for the controller.

**Files:**
- Modify: `Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift`

- [ ] **Step 1: Add helper to flatten the macOS tree**

Add this private function inside `TaskListView`:

```swift
private func flattenForDrag(_ nodes: [TaskOutlineNode], depth: Int = 0, parent: UUID? = nil) -> [DragReorderRow] {
    var out: [DragReorderRow] = []
    for node in nodes {
        out.append(DragReorderRow(id: node.id, parentID: parent, depth: depth))
        if let kids = node.children, !kids.isEmpty {
            out.append(contentsOf: flattenForDrag(kids, depth: depth + 1, parent: node.id))
        }
    }
    return out
}
```

- [ ] **Step 2: Add `dragController` `@StateObject`**

Add to `TaskListView`:

```swift
@StateObject private var dragController = DragController(onDrop: { _, _ in })
```

- [ ] **Step 3: Replace `.draggable` + `.onDrop` with `.dragReorderable`**

Inside the `OutlineGroup` row builder (currently lines 86–105), replace:

```swift
TaskRowView( ... )
    .tag(node.id)
    .onDrop(of: [.lillistTask], delegate: TaskDropDelegate( ... ))
    .draggable(TaskDragPayload(taskID: node.id))
```

with:

```swift
TaskRowView( ... )
    .tag(node.id)
    .dragReorderable(id: node.id, controller: dragController)
```

Wrap the outer `List` in:

```swift
.coordinateSpace(name: DragCoordinateSpace.name)
.onPreferenceChange(RowFramePreferenceKey.self) { dragController.geometry = $0 }
.overlay {
    DragOverlay(controller: dragController) { id in
        // Phantom is a duplicate of the row that's currently dragged.
        // Look it up in the tree.
        if let rec = flatRecord(id: id) {
            TaskRowView(task: rec, tagNames: [], onStatusClick: {}, onStatusSet: { _ in })
                .padding(.horizontal, 8)
                .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}
```

Add a helper:

```swift
private func flatRecord(id: UUID) -> TaskStore.TaskRecord? {
    // Walk rootNodes and flatResults, return the matching record.
    if let r = flatResults.first(where: { $0.id == id }) { return r }
    func walk(_ nodes: [TaskOutlineNode]) -> TaskStore.TaskRecord? {
        for n in nodes {
            if n.id == id { return n.record }
            if let kids = n.children, let hit = walk(kids) { return hit }
        }
        return nil
    }
    return walk(rootNodes)
}
```

- [ ] **Step 4: Wire `dragController` state updates**

Add `.onAppear` and `.onChange` modifiers on the outer `VStack` to
keep `flatRows`, `sortMode`, and `isFilterActive` current:

```swift
.onAppear {
    dragController.setOnDrop { dragged, target in
        Task { await applyDrop(dragged: dragged, target: target) }
    }
}
.onChange(of: rootNodes) { _, _ in
    dragController.flatRows = flattenForDrag(rootNodes)
    dragController.sortMode = (sortField == .manualPosition) ? .personalized : .sortedByOther
    dragController.isFilterActive = false
}
```

(macOS `TaskListView` doesn't have an ephemeral filter the way iOS
does — `isFilterActive` is always `false` there.)

- [ ] **Step 5: Add `applyDrop` for macOS**

Add to `TaskListView`:

```swift
@MainActor
private func applyDrop(dragged: UUID, target: DragTarget) async {
    do {
        switch target {
        case .between(let beforeID, let afterID, _):
            try await env.taskStore.reorder(id: dragged, after: afterID, before: beforeID)
        case .onto(let parentID):
            try await env.taskStore.reparent(id: dragged, newParent: parentID)
        case .rejected, .none:
            break
        }
        await refresh()
    } catch {
        // macOS TaskListView swallows errors in this file already
        // (the existing `reparent`/`reorder` paths use `try?`).
    }
}
```

- [ ] **Step 6: Remove the obsolete private `reorder` and `reparent` helpers**

Delete from `TaskListView`:

```swift
private func reorder(dragged: UUID, target: UUID, before: Bool) async { ... }
private func reparent(dragged: UUID, newParent: UUID) async { ... }
```

- [ ] **Step 7: Build macOS app target**

Run:
```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```
Expected: success, no warnings.

- [ ] **Step 8: Commit**

```bash
git add Apps/Lillist-macOS/Sources/Views/TaskList/TaskListView.swift
git commit -m "refactor(macos): migrate TaskListView to shared DragController"
```

---

### Task 12: Delete obsolete `DragDrop` module + its iOS tests

After both platforms migrate, the legacy types have no consumers.

**Files:**
- Delete: `Packages/LillistUI/Sources/LillistUI/DragDrop/DropPosition.swift`
- Delete: `Packages/LillistUI/Sources/LillistUI/DragDrop/TaskDragPayload.swift`
- Delete: `Packages/LillistUI/Sources/LillistUI/DragDrop/TaskDropDelegate.swift`
- Delete: `Packages/LillistUI/Tests/LillistUITests/DragDrop/DropPositionTests.swift`

- [ ] **Step 1: Confirm no remaining references**

Run:
```bash
grep -rn "TaskDropDelegate\|TaskDragPayload\|DropPosition\b" \
  Apps Packages 2>&1 | grep -v __Snapshots__ | grep -v "\.git"
```
Expected: no results (or only matches inside the four files about to be
deleted).

If any remain, stop and resolve them before continuing.

- [ ] **Step 2: Delete the files**

```bash
git rm Packages/LillistUI/Sources/LillistUI/DragDrop/DropPosition.swift \
       Packages/LillistUI/Sources/LillistUI/DragDrop/TaskDragPayload.swift \
       Packages/LillistUI/Sources/LillistUI/DragDrop/TaskDropDelegate.swift \
       Packages/LillistUI/Tests/LillistUITests/DragDrop/DropPositionTests.swift
# If the now-empty directories remain, remove them:
rmdir Packages/LillistUI/Sources/LillistUI/DragDrop 2>/dev/null
rmdir Packages/LillistUI/Tests/LillistUITests/DragDrop 2>/dev/null
```

- [ ] **Step 3: Build both platforms**

Run:
```bash
swift build --package-path Packages/LillistUI
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```
Expected: all three succeed with no warnings.

- [ ] **Step 4: Commit**

```bash
git commit -m "refactor(ui): delete obsolete DragDrop module and DropPositionTests"
```

---

### Task 13: Rewrite macOS `DragDropInteractionTests`

The old file tested the store API via the macOS drop path. Replace
with tests that drive `DragController` directly to confirm the same
end-state.

**Files:**
- Rewrite: `Apps/Lillist-macOS/Tests/DragDropInteractionTests.swift`

- [ ] **Step 1: Write the new test file**

Replace the contents of
`Apps/Lillist-macOS/Tests/DragDropInteractionTests.swift` with:

```swift
import XCTest
import LillistCore
import LillistUI

@MainActor
final class DragDropInteractionTests: XCTestCase {
    func test_dropOnto_callsReparent() async throws {
        let p = try await PersistenceController(configuration: .inMemory)
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "A")
        let b = try await store.create(title: "B")

        let controller = DragController(onDrop: { _, _ in })
        await applyTarget(.onto(targetID: a), draggedID: b, store: store, controller: controller)

        let kidsOfA = try await store.children(of: a).map(\.id)
        XCTAssertEqual(kidsOfA, [b])
    }

    func test_dropBetween_callsReorder() async throws {
        let p = try await PersistenceController(configuration: .inMemory)
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "A")
        let b = try await store.create(title: "B")
        let c = try await store.create(title: "C")
        // Move C before A → order [C, A, B]
        let controller = DragController(onDrop: { _, _ in })
        await applyTarget(
            .between(beforeID: a, afterID: nil, parentID: nil),
            draggedID: c,
            store: store,
            controller: controller
        )

        let order = try await store.children(of: nil).map(\.id)
        XCTAssertEqual(order, [c, a, b])
    }

    func test_dropOntoSelf_isRejectedByController() {
        let id = UUID()
        let controller = DragController(onDrop: { _, _ in })
        controller.flatRows = [DragReorderRow(id: id, parentID: nil, depth: 0)]
        controller.geometry = [id: CGRect(x: 0, y: 0, width: 100, height: 44)]
        controller.beginDrag(rowID: id, originalHeight: 44, cursorY: 22)
        let t = controller.resolveTarget(forDraggedID: id, atY: 22)
        XCTAssertEqual(t, .rejected)
    }

    // MARK: - Helpers

    /// Bridge a `DragTarget` to the store calls the macOS container makes.
    private func applyTarget(
        _ target: DragTarget,
        draggedID: UUID,
        store: TaskStore,
        controller: DragController
    ) async {
        switch target {
        case .between(let beforeID, let afterID, _):
            try? await store.reorder(id: draggedID, after: afterID, before: beforeID)
        case .onto(let parentID):
            try? await store.reparent(id: draggedID, newParent: parentID)
        case .rejected, .none:
            break
        }
    }
}
```

- [ ] **Step 2: Build & run the macOS test suite**

Run:
```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS \
  -destination 'platform=macOS'
```
Expected: `DragDropInteractionTests` all pass. Other macOS tests
(`KeyboardShortcutTests` etc.) continue passing — they use the store
API directly, which is unchanged.

- [ ] **Step 3: Commit**

```bash
git add Apps/Lillist-macOS/Tests/DragDropInteractionTests.swift
git commit -m "test(macos): rewrite DragDropInteractionTests against DragController"
```

---

### Task 14: Snapshot tests for drag states

Visual regression baselines for the four drag visual states. Pinned
to iPhone 16 Pro logical size per `IOSScreenTourTests` convention.

**Files:**
- Create: `Packages/LillistUI/Tests/LillistUITests/DragReorder/DragReorderSnapshotTests.swift`

- [ ] **Step 1: Write the snapshot test scaffold**

Create `Packages/LillistUI/Tests/LillistUITests/DragReorder/DragReorderSnapshotTests.swift`:

```swift
#if os(iOS)
import XCTest
import SwiftUI
import SnapshotTesting
import LillistCore
@testable import LillistUI

@MainActor
final class DragReorderSnapshotTests: XCTestCase {

    private let phoneSize = CGSize(width: 393, height: 852)

    private func task(_ title: String, id: UUID = UUID(), parent: UUID? = nil) -> TaskStore.TaskRecord {
        TaskStore.TaskRecord(
            id: id, title: title, notes: "", status: .todo,
            start: nil, startHasTime: false,
            deadline: nil, deadlineHasTime: false,
            position: 0, isPinned: false, parentID: parent,
            createdAt: Date(timeIntervalSince1970: 1_780_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_780_000_000),
            closedAt: nil, deletedAt: nil
        )
    }

    private func roots() -> [TaskNode] {
        [
            TaskNode(record: task("Buy milk"),    tagNames: [], children: []),
            TaskNode(record: task("Draft email"), tagNames: [], children: []),
            TaskNode(record: task("Renew domain"), tagNames: [], children: []),
        ]
    }

    private func screen(controller: DragController) -> some View {
        TasksScreen(
            roots: roots(),
            loadError: nil,
            syncIndicator: .ok,
            buildVersion: "1.0",
            sort: .constant(.personalized),
            isFilterHeaderExpanded: .constant(false),
            searchText: .constant(""),
            selectedTokens: .constant([]),
            selectedSavedFilters: .constant([]),
            isArchiveToastPresented: .constant(false),
            savedFilters: [],
            collapsedNodeIDs: [],
            archivedCount: 0,
            dragController: controller,
            onToggleCollapsed: { _ in },
            onRefresh: {},
            onStatusClick: { _ in },
            onStatusSet: { _, _ in },
            onDelete: { _ in },
            onClearFilter: {},
            onOpenSettings: {},
            onUndoArchive: {}
        )
        .frame(width: phoneSize.width, height: phoneSize.height)
    }

    func test_idle() {
        let controller = DragController(onDrop: { _, _ in })
        assertSnapshot(of: screen(controller: controller), as: .image, named: "idle")
    }

    func test_dragging_betweenZone() {
        let controller = DragController(onDrop: { _, _ in })
        let draggedID = UUID()
        let aboveID   = UUID()
        let belowID   = UUID()
        controller.flatRows = [
            DragReorderRow(id: draggedID, parentID: nil, depth: 0),
            DragReorderRow(id: aboveID,   parentID: nil, depth: 0),
            DragReorderRow(id: belowID,   parentID: nil, depth: 0),
        ]
        controller.geometry = [
            draggedID: CGRect(x: 12, y: 100, width: 369, height: 44),
            aboveID:   CGRect(x: 12, y: 150, width: 369, height: 44),
            belowID:   CGRect(x: 12, y: 200, width: 369, height: 44),
        ]
        controller.beginDrag(rowID: draggedID, originalHeight: 44, cursorY: 195)
        controller.setResolvedTarget(.between(beforeID: aboveID, afterID: belowID, parentID: nil))
        assertSnapshot(of: screen(controller: controller), as: .image, named: "dragging-between")
    }

    func test_dragging_ontoZone() {
        let controller = DragController(onDrop: { _, _ in })
        let draggedID = UUID(), targetID = UUID()
        controller.flatRows = [
            DragReorderRow(id: draggedID, parentID: nil, depth: 0),
            DragReorderRow(id: targetID,  parentID: nil, depth: 0),
        ]
        controller.geometry = [
            draggedID: CGRect(x: 12, y: 100, width: 369, height: 44),
            targetID:  CGRect(x: 12, y: 150, width: 369, height: 44),
        ]
        controller.beginDrag(rowID: draggedID, originalHeight: 44, cursorY: 172)
        controller.setResolvedTarget(.onto(targetID: targetID))
        assertSnapshot(of: screen(controller: controller), as: .image, named: "dragging-onto")
    }

    func test_dragging_rejected() {
        let controller = DragController(onDrop: { _, _ in })
        let draggedID = UUID()
        controller.flatRows = [
            DragReorderRow(id: draggedID, parentID: nil, depth: 0),
        ]
        controller.geometry = [
            draggedID: CGRect(x: 12, y: 100, width: 369, height: 44),
        ]
        controller.beginDrag(rowID: draggedID, originalHeight: 44, cursorY: 122)
        controller.setResolvedTarget(.rejected)
        assertSnapshot(of: screen(controller: controller), as: .image, named: "dragging-rejected")
    }
}
#endif
```

- [ ] **Step 2: Generate snapshot baselines**

Run:
```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -only-testing:LillistUITests/DragReorderSnapshotTests
```
Expected: first run records baselines (one per test) under
`Packages/LillistUI/Tests/LillistUITests/DragReorder/__Snapshots__/`.

- [ ] **Step 3: Inspect baselines visually**

Open the four PNGs:
```bash
open Packages/LillistUI/Tests/LillistUITests/DragReorder/__Snapshots__/*.png
```
Confirm each state visually matches the design — no drag in idle;
thick capsule divider between two rows in between state; thick rounded
border on the target row in onto state; red border on the phantom in
rejected state.

If any image looks wrong, fix the controller or overlay code and
re-run with `record: true` on the snapshot assertion.

- [ ] **Step 4: Re-run to confirm deterministic match**

Run the same `xcodebuild test` command from Step 2.
Expected: all four tests pass (no diff).

- [ ] **Step 5: Commit baselines + tests**

```bash
git add Packages/LillistUI/Tests/LillistUITests/DragReorder/
git commit -m "test(ui): add DragReorderSnapshotTests with four state baselines"
```

---

### Task 15: Tour state for drag-in-progress

Add a tour snapshot to `IOSScreenTourTests` showing `TasksScreen`
mid-drag so the deck includes the new visual.

**Files:**
- Modify: `Packages/LillistUI/Tests/LillistUITests/Tour/IOSScreenTourTests.swift`

- [ ] **Step 1: Add a new test method to the tour**

Insert after the existing `// MARK: - TasksScreen states` block:

```swift
func test_06_tasksScreen_midDrag() {
    let controller = DragController(onDrop: { _, _ in })
    let roots = sampleRoots()

    // Pick a stable id so the snapshot frame stays consistent.
    let draggedID = roots[3].record.id  // "Reply to investors"
    let targetID  = roots[4].record.id  // "Sync with design"

    controller.flatRows = roots.map {
        DragReorderRow(id: $0.record.id, parentID: nil, depth: 0)
    }
    // Synthetic geometry — order matches the list rendering.
    var y: CGFloat = 100
    for root in roots {
        controller.geometry[root.record.id] = CGRect(
            x: 12, y: y, width: 369, height: 44
        )
        y += 50
    }
    controller.beginDrag(
        rowID: draggedID,
        originalHeight: 44,
        cursorY: controller.geometry[targetID]?.midY ?? 200
    )
    controller.setResolvedTarget(.onto(targetID: targetID))

    let view = ZStack {
        Color.white.ignoresSafeArea()
        TasksScreen(
            roots: roots,
            loadError: nil,
            syncIndicator: .ok,
            buildVersion: "1.0",
            sort: .constant(.personalized),
            isFilterHeaderExpanded: .constant(false),
            searchText: .constant(""),
            selectedTokens: .constant([]),
            selectedSavedFilters: .constant([]),
            isArchiveToastPresented: .constant(false),
            savedFilters: [],
            collapsedNodeIDs: [],
            archivedCount: 0,
            dragController: controller,
            onToggleCollapsed: { _ in },
            onRefresh: {},
            onStatusClick: { _ in },
            onStatusSet: { _, _ in },
            onDelete: { _ in },
            onClearFilter: {},
            onOpenSettings: {},
            onUndoArchive: {}
        )
    }
    .frame(width: phoneSize.width, height: phoneSize.height)
    assertScreen(view, name: "06-tasks-mid-drag-light", colorScheme: .light, size: phoneSize)
}
```

(If `sampleRoots()` uses `private` access, adjust visibility or
inline a smaller fixture inside this test.)

- [ ] **Step 2: Record baseline**

Run:
```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -only-testing:LillistUITests/IOSScreenTourTests/test_06_tasksScreen_midDrag
```
Expected: first run records baseline.

- [ ] **Step 3: Inspect, then re-run**

Open the new `06-tasks-mid-drag-light.png` and confirm the bordered
"Sync with design" row plus the floating "Reply to investors"
phantom near the same y-position.

Re-run the test to confirm deterministic match.

- [ ] **Step 4: Run the full iOS test suite**

Run:
```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'
```
Expected: every test passes, all snapshot baselines stable.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistUI/Tests/LillistUITests/Tour/IOSScreenTourTests.swift \
        Packages/LillistUI/Tests/LillistUITests/Tour/__Snapshots__/IOSScreenTourTests/06-tasks-mid-drag-light.png
git commit -m "test(ui): add 06-tasks-mid-drag tour snapshot"
```

---

### Task 16: Manual verification on device or simulator

After everything is committed, exercise the feature interactively.
Automated tests cover the model; this catches gesture timing and
animation feel.

- [ ] **Step 1: Build a fresh iOS run**

Run:
```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

- [ ] **Step 2: Launch and verify the golden path on simulator**

Boot the simulator, install the .app, and walk through:

1. Personalized sort: long-press a row for ~0.3s. Phantom should
   lift with a haptic.
2. Drag up/down. Confirm the source gap stays in place (no rows
   shift to make room).
3. Hover the top 25% of another row. Confirm the thick capsule
   divider appears above that row.
4. Hover the middle 50%. Confirm the rounded border appears around
   that row.
5. Hover the bottom 25%. Confirm the divider appears below.
6. Release in each zone and confirm the data updates correctly.
7. Try to drop a parent onto its own child — phantom should turn red.
8. Switch to Due sort. Long-press a row, hover other rows. Confirm
   only the middle 50% (onto) target highlights; top/bottom 25%
   shows nothing.
9. Activate a filter. Long-press a row. Confirm drag does not begin.

- [ ] **Step 3: Optional — deploy to physical device for haptic feel**

Per `/deployit deploy` (see CLAUDE.md). Validate the haptic feedback,
which is silent on the simulator. Commit any build-number bump that
results.

- [ ] **Step 4: Final cleanup commit (if any pixels drifted)**

If the manual verification surfaced a visual tweak (e.g., the
divider needed a different thickness or color), make the change and
re-record affected snapshots. Otherwise no commit needed.

---

## Self-review checklist

- [x] **Spec coverage:** Every section of the design doc maps to a
  task. Architecture → Tasks 1, 2, 4. Drop targets → Task 5. Visuals
  → Tasks 3, 7. Animation/gap → Tasks 7, 9. Data layer → no changes
  (existing APIs sufficient — noted in design). Edge cases → Task 5
  resolution + Task 11/13 macOS migration. Testing → Tasks 4, 5, 14,
  15. Rollout → Tasks 9, 11, 12, 13, 16.

- [x] **Placeholders:** None. Every step shows the code or the
  command. The convention reconciliation in Task 10 Step 2 is
  explicit about picking option (a) and updating Task 5 in the same
  pass.

- [x] **Type consistency:**
  - `DragController.beginDrag(rowID:originalHeight:cursorY:)` — used
    consistently across Tasks 4, 5, 8, 13, 14, 15.
  - `DragController.setOnDrop(_:)` — introduced in Task 10 Step 1
    (Task 4's `onDrop` field renamed to `handler`). Used in Tasks 10,
    11.
  - `DragTarget.between(beforeID:afterID:parentID:)` — naming
    convention swapped in Task 10 Step 2 to match `TaskStore.reorder`
    (beforeID = "before this row in store sense"). Task 5 tests are
    updated to match in the same task.
  - `dragReorderable(id:controller:)` — same signature in Tasks 8, 9,
    11.
  - `DragReorderRow(id:parentID:depth:)` — same constructor in Tasks
    1, 5, 9, 11, 13, 14, 15.

- [x] **No spec drift:** The "Smart: where the cursor was" reparent
  semantic resolves to `.onto` → `TaskStore.reparent` (append). The
  design notes this as a simplification of the chosen option in the
  brainstorming reply — Mikey can adjust during review if a richer
  cursor-aware position is wanted.
