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
}
