import XCTest
import CoreGraphics
@testable import LillistUI

/// Coverage for `insertionIndicatorY` — the drop indicator's vertical position.
/// It snaps to the insertion fencepost nearest the touch, computed over the
/// **reference** rows (the current list minus the dragged row and its subtree),
/// so the dragged row's own slot collapses into the surrounding gap and there is
/// exactly one fencepost per gap (no duplicate destinations).
@MainActor
final class DragControllerInsertionIndicatorTests: XCTestCase {

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

    /// A, B, C(child of B), D — contiguous 44pt rows. Visual midlines:
    /// A=22, B=66, C=110, D=154. C's slot is [88, 132].
    private func abcdController() -> (
        a: UUID, b: UUID, c: UUID, d: UUID, controller: DragController
    ) {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let rows = [
            DragReorderRow(id: a, parentID: nil, depth: 0),
            DragReorderRow(id: b, parentID: nil, depth: 0),
            DragReorderRow(id: c, parentID: b,   depth: 1),
            DragReorderRow(id: d, parentID: nil, depth: 0),
        ]
        let geo: [UUID: CGRect] = [
            a: CGRect(x: 0, y: 0,   width: 320, height: 44),
            b: CGRect(x: 0, y: 44,  width: 320, height: 44),
            c: CGRect(x: 0, y: 88,  width: 320, height: 44),
            d: CGRect(x: 0, y: 132, width: 320, height: 44),
        ]
        return (a, b, c, d, makeController(rows: rows, geometry: geo))
    }

    /// #3: dragging C, cursors anywhere within C's own slot collapse to a single
    /// fencepost (the B–D gap midpoint = middle of C's slot). No separate
    /// "just below B" vs "just above D" destinations.
    func test_draggingOwnSlot_collapsesToOneFencepost() {
        let (_, _, c, _, con) = abcdController()
        // Reference excludes C → [A, B, D]; C's slot [88,132] is the B–D gap.
        // Midpoint of B.maxY(88) and D.minY(132) = 110.
        let upper = con.insertionIndicatorY(forCursorY: 100, draggedID: c) // upper half of C's slot
        let lower = con.insertionIndicatorY(forCursorY: 120, draggedID: c) // lower half of C's slot
        XCTAssertEqual(upper, 110)
        XCTAssertEqual(lower, 110)
        XCTAssertEqual(upper, lower, "C's slot must yield one fencepost, not two")
    }

    /// Dragging C still distinguishes the genuinely-distinct gaps around it.
    func test_draggingC_distinctGapsStillSelectable() {
        let (_, _, c, _, con) = abcdController()
        // Between A and B (cursor in A|B gap region, y=30): A.maxY=44 ≈ B.minY=44 → 44.
        XCTAssertEqual(con.insertionIndicatorY(forCursorY: 30, draggedID: c), 44)
        // Above A (y=5 < A.midY): top edge A.minY = 0.
        XCTAssertEqual(con.insertionIndicatorY(forCursorY: 5, draggedID: c), 0)
        // Below D (y=200): bottom edge D.maxY = 176.
        XCTAssertEqual(con.insertionIndicatorY(forCursorY: 200, draggedID: c), 176)
    }

    /// De-parenting drag (last round's scenario), now over the reference list:
    /// dragging B (child of A) collapses B's slot, so the line sits at the
    /// midpoint of the A–C gap (≈ B's current centre) rather than its edge.
    func test_draggingChild_collapsesItsSlotToMidpoint() {
        let a = UUID(), b = UUID(), c = UUID()
        let rows = [
            DragReorderRow(id: a, parentID: nil, depth: 0),
            DragReorderRow(id: b, parentID: a,   depth: 1),
            DragReorderRow(id: c, parentID: nil, depth: 0),
        ]
        let geo: [UUID: CGRect] = [
            a: CGRect(x: 0, y: 0,  width: 320, height: 44),  // [0,44], midY 22
            b: CGRect(x: 0, y: 44, width: 320, height: 44),  // [44,88], excluded
            c: CGRect(x: 0, y: 88, width: 320, height: 44),  // [88,132], midY 110
        ]
        let con = makeController(rows: rows, geometry: geo)
        // Reference [A, C]; B's slot [44,88] is the A–C gap. Midpoint of
        // A.maxY(44) and C.minY(88) = 66 (= B's current centre).
        XCTAssertEqual(con.insertionIndicatorY(forCursorY: 70, draggedID: b), 66)
    }

    func test_noReferenceGeometry_returnsNil() {
        let only = UUID()
        let con = makeController(
            rows: [DragReorderRow(id: only, parentID: nil, depth: 0)],
            geometry: [only: CGRect(x: 0, y: 0, width: 320, height: 44)]
        )
        // Dragging the only row → reference list empty → nil.
        XCTAssertNil(con.insertionIndicatorY(forCursorY: 20, draggedID: only))
    }
}
