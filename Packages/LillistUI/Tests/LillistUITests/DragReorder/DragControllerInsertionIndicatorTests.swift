import XCTest
import CoreGraphics
@testable import LillistUI

/// Coverage for `insertionIndicatorY` — the drop indicator's vertical position,
/// which snaps to the insertion fencepost nearest the touch in the **current**
/// visual list (all rows at their present positions, including the dragged
/// row's slot), independent of where the row will land after the list re-sorts.
@MainActor
final class DragControllerInsertionIndicatorTests: XCTestCase {

    /// A (top), B (child of A), C (top) — contiguous 44pt rows at y 0 / 44 / 88.
    /// Visual midlines: A=22, B=66, C=110.
    private func abcController() -> (a: UUID, b: UUID, c: UUID, controller: DragController) {
        let a = UUID(), b = UUID(), c = UUID()
        let rows = [
            DragReorderRow(id: a, parentID: nil, depth: 0),
            DragReorderRow(id: b, parentID: a,   depth: 1),
            DragReorderRow(id: c, parentID: nil, depth: 0),
        ]
        let geo: [UUID: CGRect] = [
            a: CGRect(x: 0, y: 0,  width: 320, height: 44),
            b: CGRect(x: 0, y: 44, width: 320, height: 44),
            c: CGRect(x: 0, y: 88, width: 320, height: 44),
        ]
        let con = DragController(onDrop: { _, _ in })
        con.flatRows = rows
        con.geometry = geo
        con.sortMode = .personalized
        return (a, b, c, con)
    }

    /// The user's example: dragging B downward past its own midline must place
    /// the indicator at the *current* fencepost between B and C (3rd position),
    /// not the future "between A and B" slot the anchors describe.
    func test_cursorBelowBMidline_snapsToCurrentGapBetweenBandC() {
        let (_, _, _, c) = abcController()
        // Cursor at y=70: below B.midY(66), above C.midY(110) → fencepost
        // between B and C = midpoint of B.maxY(88) and C.minY(88) = 88.
        XCTAssertEqual(c.insertionIndicatorY(forCursorY: 70), 88)
    }

    func test_cursorInUpperHalfOfB_snapsToGapBetweenAandB() {
        let (_, _, _, c) = abcController()
        // y=50: below A.midY(22), above B.midY(66) → fencepost between A and B
        // = midpoint of A.maxY(44) and B.minY(44) = 44.
        XCTAssertEqual(c.insertionIndicatorY(forCursorY: 50), 44)
    }

    func test_cursorAboveFirstRow_snapsToTopEdge() {
        let (_, _, _, c) = abcController()
        // y=5: above A.midY(22) → fencepost above A = A.minY = 0.
        XCTAssertEqual(c.insertionIndicatorY(forCursorY: 5), 0)
    }

    func test_cursorBelowLastRow_snapsToBottomEdge() {
        let (_, _, _, c) = abcController()
        // y=200: below every midline → fencepost below C = C.maxY = 132.
        XCTAssertEqual(c.insertionIndicatorY(forCursorY: 200), 132)
    }

    func test_noGeometry_returnsNil() {
        let con = DragController(onDrop: { _, _ in })
        con.flatRows = [DragReorderRow(id: UUID(), parentID: nil, depth: 0)]
        // geometry left empty
        XCTAssertNil(con.insertionIndicatorY(forCursorY: 50))
    }
}
