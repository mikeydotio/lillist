import XCTest
import CoreGraphics
@testable import LillistUI

/// Coverage for horizontal-translation depth disambiguation — the core of the
/// drag-reorder de-parenting work. Within a single vertical gap, the horizontal
/// translation chooses the drop depth (Reminders-style indent/outdent), clamped
/// to the gap's valid range. The indent step is `LillistDragTokens.indentPerLevel`
/// with a half-indent dead-zone (from `rounded()`).
@MainActor
final class DragControllerGapDepthTests: XCTestCase {

    private var indent: CGFloat { LillistDragTokens.indentPerLevel }

    private func makeController(
        rows: [DragReorderRow],
        geometry: [UUID: CGRect]
    ) -> DragController {
        let c = DragController(onDrop: { _, _ in })
        c.flatRows = rows
        c.geometry = geometry
        c.sortMode = .personalized
        return c
    }

    // MARK: - Issue 1: drag a child above its top-level parent → de-parent

    func test_childDraggedAboveParent_deparentsToTopLevelBeforeParent() {
        // A (top) with only child B. Drag B above A.
        let a = UUID(), b = UUID()
        let rows = [
            DragReorderRow(id: a, parentID: nil, depth: 0),
            DragReorderRow(id: b, parentID: a,   depth: 1),
        ]
        let geo: [UUID: CGRect] = [
            a: CGRect(x: 0, y: 0,  width: 320, height: 44),  // midY 22
            b: CGRect(x: 0, y: 44, width: 320, height: 44),
        ]
        let c = makeController(rows: rows, geometry: geo)
        c.beginDrag(rowID: b, originalHeight: 44, cursorY: 10)
        // y=10 < A.midY(22): gap before A. The only valid depth there is 0
        // (no row above), so even with no horizontal nudge B de-parents.
        let t = c.resolveTarget(forDraggedID: b, atY: 10, horizontalTranslation: 0)
        XCTAssertEqual(t, .between(beforeID: a, afterID: nil, parentID: nil))
    }

    // MARK: - Issue 2 + 3: single child, drag down, disambiguate with horizontal

    func test_singleChildDraggedBelow_keepsNestingByDefault() {
        let (a, b, c) = singleChildController()
        c.beginDrag(rowID: b, originalHeight: 44, cursorY: 60)
        // Gap below A (B excluded). Default baseline = B's depth (1) → stays a
        // child of A (reparent-append: no sibling anchors).
        let t = c.resolveTarget(forDraggedID: b, atY: 60, horizontalTranslation: 0)
        XCTAssertEqual(t, .between(beforeID: nil, afterID: nil, parentID: a))
    }

    func test_singleChildDraggedBelow_pullLeft_deparentsAfterParent() {
        let (a, b, c) = singleChildController()
        c.beginDrag(rowID: b, originalHeight: 44, cursorY: 60)
        // Pull one indent to the left → outdent to top level, after A.
        let t = c.resolveTarget(forDraggedID: b, atY: 60, horizontalTranslation: -indent)
        XCTAssertEqual(t, .between(beforeID: nil, afterID: a, parentID: nil))
    }

    /// A (top) with only child B. Dragging B excludes it, leaving reference [A].
    private func singleChildController() -> (a: UUID, b: UUID, controller: DragController) {
        let a = UUID(), b = UUID()
        let rows = [
            DragReorderRow(id: a, parentID: nil, depth: 0),
            DragReorderRow(id: b, parentID: a,   depth: 1),
        ]
        let geo: [UUID: CGRect] = [
            a: CGRect(x: 0, y: 0,  width: 320, height: 44),  // midY 22
            b: CGRect(x: 0, y: 44, width: 320, height: 44),
        ]
        return (a, b, makeController(rows: rows, geometry: geo))
    }

    // MARK: - Multi-level depth selection in one gap

    func test_gapBelowNestedRow_horizontalShiftsThroughEveryValidDepth() {
        // A(0) > A1(1) > [A1a(2)]; then B(0). Drag mover M (top level).
        // Gap between A1a (depth 2) and B (depth 0): valid depths 0...3.
        let a = UUID(), a1 = UUID(), a1a = UUID(), b = UUID(), m = UUID()
        let rows = [
            DragReorderRow(id: a,   parentID: nil, depth: 0),
            DragReorderRow(id: a1,  parentID: a,   depth: 1),
            DragReorderRow(id: a1a, parentID: a1,  depth: 2),
            DragReorderRow(id: b,   parentID: nil, depth: 0),
            DragReorderRow(id: m,   parentID: nil, depth: 0),
        ]
        let geo: [UUID: CGRect] = [
            a:   CGRect(x: 0, y: 0,   width: 320, height: 44),  // midY 22
            a1:  CGRect(x: 0, y: 44,  width: 320, height: 44),  // midY 66
            a1a: CGRect(x: 0, y: 88,  width: 320, height: 44),  // midY 110
            b:   CGRect(x: 0, y: 132, width: 320, height: 44),  // midY 154
            m:   CGRect(x: 0, y: 176, width: 320, height: 44),
        ]
        let c = makeController(rows: rows, geometry: geo)
        c.beginDrag(rowID: m, originalHeight: 44, cursorY: 140)
        // y=140: above A1a.midY(110), below B.midY(154) → gap (above=A1a, below=B).
        // baseline = M.depth = 0.

        // depth 0: top level, between A and B.
        XCTAssertEqual(
            c.resolveTarget(forDraggedID: m, atY: 140, horizontalTranslation: 0),
            .between(beforeID: b, afterID: a, parentID: nil)
        )
        // depth 1: child of A, after A1 (A1's last child position).
        XCTAssertEqual(
            c.resolveTarget(forDraggedID: m, atY: 140, horizontalTranslation: indent),
            .between(beforeID: nil, afterID: a1, parentID: a)
        )
        // depth 2: child of A1, after A1a.
        XCTAssertEqual(
            c.resolveTarget(forDraggedID: m, atY: 140, horizontalTranslation: indent * 2),
            .between(beforeID: nil, afterID: a1a, parentID: a1)
        )
        // depth 3: child of A1a (reparent-append; no sibling anchors).
        XCTAssertEqual(
            c.resolveTarget(forDraggedID: m, atY: 140, horizontalTranslation: indent * 3),
            .between(beforeID: nil, afterID: nil, parentID: a1a)
        )
    }

    func test_horizontal_clampsToValidRange() {
        // Same fixture: pulling far left past depth 0 clamps to 0, far right
        // past depth 3 clamps to 3.
        let a = UUID(), a1 = UUID(), a1a = UUID(), b = UUID(), m = UUID()
        let rows = [
            DragReorderRow(id: a,   parentID: nil, depth: 0),
            DragReorderRow(id: a1,  parentID: a,   depth: 1),
            DragReorderRow(id: a1a, parentID: a1,  depth: 2),
            DragReorderRow(id: b,   parentID: nil, depth: 0),
            DragReorderRow(id: m,   parentID: nil, depth: 0),
        ]
        let geo: [UUID: CGRect] = [
            a:   CGRect(x: 0, y: 0,   width: 320, height: 44),
            a1:  CGRect(x: 0, y: 44,  width: 320, height: 44),
            a1a: CGRect(x: 0, y: 88,  width: 320, height: 44),
            b:   CGRect(x: 0, y: 132, width: 320, height: 44),
            m:   CGRect(x: 0, y: 176, width: 320, height: 44),
        ]
        let c = makeController(rows: rows, geometry: geo)
        c.beginDrag(rowID: m, originalHeight: 44, cursorY: 140)
        XCTAssertEqual(
            c.resolveTarget(forDraggedID: m, atY: 140, horizontalTranslation: -indent * 10),
            .between(beforeID: b, afterID: a, parentID: nil)   // clamped to depth 0
        )
        XCTAssertEqual(
            c.resolveTarget(forDraggedID: m, atY: 140, horizontalTranslation: indent * 10),
            .between(beforeID: nil, afterID: nil, parentID: a1a)  // clamped to depth 3
        )
    }

    func test_smallHorizontalWobble_withinDeadzone_doesNotChangeDepth() {
        let (a, b, c) = singleChildController()
        c.beginDrag(rowID: b, originalHeight: 44, cursorY: 60)
        // Less than half an indent of horizontal travel must not outdent.
        let t = c.resolveTarget(forDraggedID: b, atY: 60, horizontalTranslation: -(indent / 2 - 1))
        XCTAssertEqual(t, .between(beforeID: nil, afterID: nil, parentID: a))
    }
}
