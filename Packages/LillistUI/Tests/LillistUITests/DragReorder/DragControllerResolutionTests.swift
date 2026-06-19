import XCTest
import CoreGraphics
@testable import LillistUI

/// Resolution coverage for the gap-based resolver. Vertical position selects the
/// gap between two visible **reference** rows (the dragged row and its subtree
/// are excluded); horizontal translation selects the depth within the gap's
/// valid range. These tests fix the horizontal translation at 0 (depth-shift
/// behavior lives in `DragControllerGapDepthTests`) and exercise gap selection,
/// subtree exclusion, end-of-list, and the sort/filter gates.
@MainActor
final class DragControllerResolutionTests: XCTestCase {

    /// Three top-level rows A, B, C plus a top-level "mover" M that the tests
    /// drag. Dragging M keeps A, B, C in the reference list so gap selection is
    /// isolated from subtree exclusion. Contiguous 44pt frames; midYs at
    /// 22 / 66 / 110 / 154.
    private func flatThreePlusMover() -> (
        rows: [DragReorderRow],
        geometry: [UUID: CGRect],
        ids: (a: UUID, b: UUID, c: UUID, m: UUID)
    ) {
        let a = UUID(), b = UUID(), c = UUID(), m = UUID()
        let rows = [
            DragReorderRow(id: a, parentID: nil, depth: 0),
            DragReorderRow(id: b, parentID: nil, depth: 0),
            DragReorderRow(id: c, parentID: nil, depth: 0),
            DragReorderRow(id: m, parentID: nil, depth: 0),
        ]
        let geo: [UUID: CGRect] = [
            a: CGRect(x: 0, y: 0,   width: 320, height: 44),
            b: CGRect(x: 0, y: 44,  width: 320, height: 44),
            c: CGRect(x: 0, y: 88,  width: 320, height: 44),
            m: CGRect(x: 0, y: 132, width: 320, height: 44),
        ]
        return (rows, geo, (a, b, c, m))
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

    // MARK: - Gap selection (top level, no horizontal)

    func test_aboveFirstRow_resolvesToHeadOfRoot() {
        let f = flatThreePlusMover()
        let c = makeController(rows: f.rows, geometry: f.geometry)
        c.beginDrag(rowID: f.ids.m, originalHeight: 44, cursorY: 10)
        // y=10 is above A's midline (22): gap before A → M becomes first root.
        let t = c.resolveTarget(forDraggedID: f.ids.m, atY: 10)
        XCTAssertEqual(t, .between(beforeID: f.ids.a, afterID: nil, parentID: nil))
    }

    func test_betweenA_andB() {
        let f = flatThreePlusMover()
        let c = makeController(rows: f.rows, geometry: f.geometry)
        c.beginDrag(rowID: f.ids.m, originalHeight: 44, cursorY: 30)
        // y=30: below A.midY(22), above B.midY(66) → gap between A and B.
        let t = c.resolveTarget(forDraggedID: f.ids.m, atY: 30)
        XCTAssertEqual(t, .between(beforeID: f.ids.b, afterID: f.ids.a, parentID: nil))
    }

    func test_betweenB_andC() {
        let f = flatThreePlusMover()
        let c = makeController(rows: f.rows, geometry: f.geometry)
        c.beginDrag(rowID: f.ids.m, originalHeight: 44, cursorY: 70)
        let t = c.resolveTarget(forDraggedID: f.ids.m, atY: 70)
        XCTAssertEqual(t, .between(beforeID: f.ids.c, afterID: f.ids.b, parentID: nil))
    }

    func test_belowLastReferenceRow_resolvesToTailOfRoot() {
        let f = flatThreePlusMover()
        let c = makeController(rows: f.rows, geometry: f.geometry)
        // y=200 is below every reference row (C is the last, M is excluded).
        c.beginDrag(rowID: f.ids.m, originalHeight: 44, cursorY: 200)
        let t = c.resolveTarget(forDraggedID: f.ids.m, atY: 200)
        XCTAssertEqual(t, .between(beforeID: nil, afterID: f.ids.c, parentID: nil))
    }

    // MARK: - Gap sweep never returns a non-actionable target

    func test_sweep_acrossAllGaps_neverNone() {
        let f = flatThreePlusMover()
        let c = makeController(rows: f.rows, geometry: f.geometry)
        c.beginDrag(rowID: f.ids.m, originalHeight: 44, cursorY: 0)
        var y: CGFloat = 0
        while y <= 132 {
            let t = c.resolveTarget(forDraggedID: f.ids.m, atY: y)
            if case .between = t { /* ok */ } else {
                XCTFail("Expected a .between target at y=\(y), got \(t)")
            }
            y += 0.5
        }
    }

    // MARK: - Subtree exclusion (a parent can never nest into its own subtree)

    func test_draggingParent_excludesDescendants_fromReference() {
        // A is an expanded parent of A1, A2; B is a root sibling. Drag A.
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
        let c = makeController(rows: rows, geometry: geo)
        c.beginDrag(rowID: a, originalHeight: 44, cursorY: 60)
        // Cursor over A1 (a descendant). Because A's subtree is excluded, the
        // only reference row is B → the resolved parent is never inside A's
        // subtree, so the result is a valid top-level target, not a cycle.
        let t = c.resolveTarget(forDraggedID: a, atY: 60)
        XCTAssertEqual(t, .between(beforeID: b, afterID: nil, parentID: nil))
    }

    // MARK: - Sort / filter gating

    func test_nonPersonalizedSort_returnsNone() {
        let f = flatThreePlusMover()
        let c = makeController(rows: f.rows, geometry: f.geometry, sort: .sortedByOther)
        c.beginDrag(rowID: f.ids.m, originalHeight: 44, cursorY: 30)
        XCTAssertEqual(c.resolveTarget(forDraggedID: f.ids.m, atY: 30), .none)
    }

    func test_filterActive_returnsNone() {
        let f = flatThreePlusMover()
        let c = makeController(rows: f.rows, geometry: f.geometry, filterActive: true)
        c.beginDrag(rowID: f.ids.m, originalHeight: 44, cursorY: 30)
        XCTAssertEqual(c.resolveTarget(forDraggedID: f.ids.m, atY: 30), .none)
    }

    func test_emptyReferenceList_returnsNone() {
        // Only the dragged row exists → no reference rows → nowhere to drop.
        let m = UUID()
        let rows = [DragReorderRow(id: m, parentID: nil, depth: 0)]
        let geo: [UUID: CGRect] = [m: CGRect(x: 0, y: 0, width: 320, height: 44)]
        let c = makeController(rows: rows, geometry: geo)
        c.beginDrag(rowID: m, originalHeight: 44, cursorY: 20)
        XCTAssertEqual(c.resolveTarget(forDraggedID: m, atY: 20), .none)
    }
}
