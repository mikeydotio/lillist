import XCTest
import CoreGraphics
@testable import LillistUI

@MainActor
final class DragControllerResolutionTests: XCTestCase {

    // Geometry fixture: 3 top-level rows of 44pt at y=0, y=44, y=88.
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

    // Hierarchy: A is parent of A1 and A2; A is expanded. B is sibling of A.
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
        // y=50: in rowB. Top 25% of rowB is y in [44, 55).
        // Drop above B as sibling-before B at root level.
        // Anchor naming convention: beforeID is the row the dragged row will sit BEFORE
        // (matches TaskStore.reorder(id:after:before:) semantics).
        let t = c.resolveTarget(forDraggedID: f.ids.c, atY: 50)
        XCTAssertEqual(t, .between(beforeID: f.ids.b, afterID: f.ids.a, parentID: nil))
    }

    func test_middle50_resolvesToOnto() {
        let f = flatThree()
        let c = makeController(rows: f.rows, geometry: f.geometry)
        c.beginDrag(rowID: f.ids.c, originalHeight: 44, cursorY: 60)
        let t = c.resolveTarget(forDraggedID: f.ids.c, atY: 60)
        XCTAssertEqual(t, .onto(targetID: f.ids.b))
    }

    func test_bottom25_resolvesToBetweenBelow() {
        let f = flatThree()
        let c = makeController(rows: f.rows, geometry: f.geometry)
        c.beginDrag(rowID: f.ids.a, originalHeight: 44, cursorY: 80)
        // y=80: in rowB. Bottom 25% of rowB is y in [77, 88].
        // Drop below B as sibling-after B at root level — between B and C.
        let t = c.resolveTarget(forDraggedID: f.ids.a, atY: 80)
        XCTAssertEqual(t, .between(beforeID: f.ids.c, afterID: f.ids.b, parentID: nil))
    }

    // MARK: - Hierarchy: between expanded parent and first child

    func test_bottom25_belowExpandedParent_resolvesToFirstChild() {
        let f = flatHierarchy()
        let c = makeController(rows: f.rows, geometry: f.geometry)
        c.beginDrag(rowID: f.ids.b, originalHeight: 44, cursorY: 35)
        // y=35: in rowA. Bottom 25% of rowA is y in [33, 44].
        // Next flat row is A1 (child of A). Resolves to first child of A.
        let t = c.resolveTarget(forDraggedID: f.ids.b, atY: 35)
        XCTAssertEqual(t, .between(beforeID: f.ids.a1, afterID: nil, parentID: f.ids.a))
    }

    func test_top25_aboveFirstChild_resolvesSameAsBetweenParentAndFirstChild() {
        let f = flatHierarchy()
        let c = makeController(rows: f.rows, geometry: f.geometry)
        // Top 25% of A1 is y in [44, 55).
        c.beginDrag(rowID: f.ids.b, originalHeight: 44, cursorY: 50)
        let t = c.resolveTarget(forDraggedID: f.ids.b, atY: 50)
        XCTAssertEqual(t, .between(beforeID: f.ids.a1, afterID: nil, parentID: f.ids.a))
    }

    // MARK: - End of list

    func test_belowLastRow_resolvesToBetweenAtRootEnd() {
        let f = flatThree()
        let c = makeController(rows: f.rows, geometry: f.geometry)
        c.beginDrag(rowID: f.ids.a, originalHeight: 44, cursorY: 200)
        // y=200: well below row C (y in [88, 132)). Drop at end of root.
        let t = c.resolveTarget(forDraggedID: f.ids.a, atY: 200)
        XCTAssertEqual(t, .between(beforeID: nil, afterID: f.ids.c, parentID: nil))
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

    // MARK: - Inter-row gap (real List geometry)

    // Geometry fixture mirroring SwiftUI List with
    // `listRowInsets(top: 2, leading: 12, bottom: 2, trailing: 12)`:
    // 44pt content frames separated by 4pt gaps. The insertion-indicator
    // capsule is drawn at `afterID.maxY` — inside the gap — so cursor
    // positions in the gap must resolve to a `.between` target rather
    // than `.none`, or the indicator fades out when the user hovers on it.
    private func flatThreeWithGaps() -> (
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
        // A=[0,44], gap [44,48], B=[48,92], gap [92,96], C=[96,140].
        let geo: [UUID: CGRect] = [
            a: CGRect(x: 0, y: 0,  width: 320, height: 44),
            b: CGRect(x: 0, y: 48, width: 320, height: 44),
            c: CGRect(x: 0, y: 96, width: 320, height: 44),
        ]
        return (rows, geo, (a, b, c))
    }

    func test_gapAboveLine_belowMidpoint_resolvesToBetween_belowAfterRow() {
        // Cursor at y=45: inside the 4pt gap between A.maxY=44 and B.minY=48,
        // on the upper half (below the midpoint y=46). Must claim the row
        // above (A) and resolve as a "below A" drop — same gap as the line.
        let f = flatThreeWithGaps()
        let c = makeController(rows: f.rows, geometry: f.geometry)
        c.beginDrag(rowID: f.ids.c, originalHeight: 44, cursorY: 45)
        let t = c.resolveTarget(forDraggedID: f.ids.c, atY: 45)
        XCTAssertEqual(t, .between(beforeID: f.ids.b, afterID: f.ids.a, parentID: nil))
    }

    func test_gapBelowLine_aboveMidpoint_resolvesToBetween_aboveBeforeRow() {
        // Cursor at y=47: inside the same gap, on the lower half (above the
        // midpoint y=46). Must claim the row below (B) and resolve as an
        // "above B" drop — semantically identical to the line above.
        let f = flatThreeWithGaps()
        let c = makeController(rows: f.rows, geometry: f.geometry)
        c.beginDrag(rowID: f.ids.c, originalHeight: 44, cursorY: 47)
        let t = c.resolveTarget(forDraggedID: f.ids.c, atY: 47)
        XCTAssertEqual(t, .between(beforeID: f.ids.b, afterID: f.ids.a, parentID: nil))
    }

    func test_gapAtBoundary_sweepAcrossGap_neverReturnsNone() {
        // Sweep cursorY in 0.5pt steps across the 4pt gap between A and B.
        // Regression for the disappearing-indicator bug: any cursor position
        // in the gap must resolve to *some* actionable .between target.
        let f = flatThreeWithGaps()
        let c = makeController(rows: f.rows, geometry: f.geometry)
        c.beginDrag(rowID: f.ids.c, originalHeight: 44, cursorY: 44)
        var y: CGFloat = 44.0
        while y <= 48.0 {
            let t = c.resolveTarget(forDraggedID: f.ids.c, atY: y)
            switch t {
            case .between, .onto:
                break
            case .none, .rejected:
                XCTFail("Resolver returned non-actionable target at gap y=\(y): \(t)")
            }
            y += 0.5
        }
    }

    func test_inRowZones_withGappyGeometry_classifyExactlyAsContiguous() {
        // The in-row zone classification must not change just because the
        // surrounding rows have gaps — only gap-region cursors get the
        // new "claim the gap" behavior. B = [48, 92] inside the gappy
        // fixture; top25 = [48, 59), middle = [59, 81), bottom25 = [81, 92).
        let f = flatThreeWithGaps()
        let c = makeController(rows: f.rows, geometry: f.geometry)
        c.beginDrag(rowID: f.ids.c, originalHeight: 44, cursorY: 50)

        // Top 25% of B: y=50 → drop above B as sibling-before B.
        XCTAssertEqual(
            c.resolveTarget(forDraggedID: f.ids.c, atY: 50),
            .between(beforeID: f.ids.b, afterID: f.ids.a, parentID: nil)
        )
        // Middle of B: y=65 → onto B.
        XCTAssertEqual(
            c.resolveTarget(forDraggedID: f.ids.c, atY: 65),
            .onto(targetID: f.ids.b)
        )
        // Bottom 25% of B: y=85 → drop below B as sibling-after B.
        XCTAssertEqual(
            c.resolveTarget(forDraggedID: f.ids.c, atY: 85),
            .between(beforeID: f.ids.c, afterID: f.ids.b, parentID: nil)
        )
    }

    // Hierarchy fixture with 4pt gaps (matches flatHierarchy semantics):
    // A=[0,44], A1=[48,92], A2=[96,140], B=[144,188].
    private func flatHierarchyWithGaps() -> (
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
            a1: CGRect(x: 0, y: 48,  width: 320, height: 44),
            a2: CGRect(x: 0, y: 96,  width: 320, height: 44),
            b:  CGRect(x: 0, y: 144, width: 320, height: 44),
        ]
        return (rows, geo, (a, a1, a2, b))
    }

    func test_hierarchyGap_betweenLastChildAndUncle_neverNone() {
        // Gap between A2 (last child of A) and B (root sibling of A) is
        // [140, 144]. The depth change means the two halves of the gap
        // resolve to *different* valid targets — but neither must be .none.
        let f = flatHierarchyWithGaps()
        let c = makeController(rows: f.rows, geometry: f.geometry)
        c.beginDrag(rowID: f.ids.a1, originalHeight: 44, cursorY: 141)

        // Upper half of gap (claimed by A2): "last child of A".
        let upper = c.resolveTarget(forDraggedID: f.ids.a1, atY: 141)
        XCTAssertEqual(
            upper,
            .between(beforeID: nil, afterID: f.ids.a2, parentID: f.ids.a)
        )
        // Lower half of gap (claimed by B): "between A and B at root".
        let lower = c.resolveTarget(forDraggedID: f.ids.a1, atY: 143)
        XCTAssertEqual(
            lower,
            .between(beforeID: f.ids.b, afterID: f.ids.a, parentID: nil)
        )
    }
}
