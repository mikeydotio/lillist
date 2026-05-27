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
