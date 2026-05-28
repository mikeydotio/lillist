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

    // MARK: - Anchor + translation tracking

    func test_beginDrag_capturesInitialCursorYAsAnchor() {
        let c = DragController(onDrop: { _, _ in })
        c.beginDrag(rowID: UUID(), originalHeight: 44, cursorY: 200)
        guard case .dragging(let s) = c.state else { return XCTFail() }
        XCTAssertEqual(s.initialCursorY, 200)
        XCTAssertEqual(s.cursorY, 200)
    }

    func test_updateCursor_byTranslation_addsToAnchor() {
        let c = DragController(onDrop: { _, _ in })
        c.beginDrag(rowID: UUID(), originalHeight: 44, cursorY: 200)
        c.updateCursor(translation: 50)
        guard case .dragging(let s) = c.state else { return XCTFail() }
        XCTAssertEqual(s.initialCursorY, 200) // anchor unchanged
        XCTAssertEqual(s.cursorY, 250)
    }

    func test_updateCursor_byTranslation_negativeTranslationMovesUp() {
        let c = DragController(onDrop: { _, _ in })
        c.beginDrag(rowID: UUID(), originalHeight: 44, cursorY: 400)
        c.updateCursor(translation: -120)
        guard case .dragging(let s) = c.state else { return XCTFail() }
        XCTAssertEqual(s.cursorY, 280)
    }

    func test_updateCursor_byTranslation_ignoredWhenIdle() {
        let c = DragController(onDrop: { _, _ in })
        c.updateCursor(translation: 50)
        XCTAssertEqual(c.state, .idle)
    }

    // MARK: - Settle (`.dropping`) state machine

    func test_endDrag_defaultSettleDurationZero_skipsDroppingPhase() {
        let c = DragController(onDrop: { _, _ in })
        c.beginDrag(rowID: UUID(), originalHeight: 44, cursorY: 100)
        c.setResolvedTarget(.onto(targetID: UUID()))
        c.endDrag() // default settleDuration: 0
        XCTAssertEqual(c.state, .idle)
    }

    func test_endDrag_withSettleDuration_entersDroppingThenIdles() async {
        let id = UUID(), targetID = UUID()
        var calls: [(UUID, DragTarget)] = []
        let c = DragController(onDrop: { dragged, t in calls.append((dragged, t)) })
        c.beginDrag(rowID: id, originalHeight: 44, cursorY: 100)
        c.setResolvedTarget(.onto(targetID: targetID))
        c.endDrag(settleDuration: 0.05)

        // Immediately after endDrag the handler must have fired exactly once
        // and the state must be .dropping carrying both the session and target.
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.0, id)
        XCTAssertEqual(calls.first?.1, .onto(targetID: targetID))
        guard case .dropping(let s, let t) = c.state else {
            return XCTFail("expected .dropping, got \(c.state)")
        }
        XCTAssertEqual(s.draggedID, id)
        XCTAssertEqual(t, .onto(targetID: targetID))

        // After the settle window, the controller returns to idle.
        try? await Task.sleep(nanoseconds: 120_000_000) // 120ms > 50ms window
        XCTAssertEqual(c.state, .idle)
    }

    func test_endDrag_withSettleDuration_rejected_entersDroppingButSkipsOnDrop() async {
        var called = false
        let c = DragController(onDrop: { _, _ in called = true })
        c.beginDrag(rowID: UUID(), originalHeight: 44, cursorY: 100)
        c.setResolvedTarget(.rejected)
        c.endDrag(settleDuration: 0.05)
        XCTAssertFalse(called)
        guard case .dropping(_, let t) = c.state else { return XCTFail() }
        XCTAssertEqual(t, .rejected)
        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(c.state, .idle)
    }

    func test_endDrag_withSettleDuration_none_entersDroppingButSkipsOnDrop() async {
        var called = false
        let c = DragController(onDrop: { _, _ in called = true })
        c.beginDrag(rowID: UUID(), originalHeight: 44, cursorY: 100)
        c.endDrag(settleDuration: 0.05) // target stays .none
        XCTAssertFalse(called)
        guard case .dropping(_, let t) = c.state else { return XCTFail() }
        XCTAssertEqual(t, DragTarget.none)
        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(c.state, .idle)
    }

    func test_endDrag_callIsIgnoredWhenIdle() {
        let c = DragController(onDrop: { _, _ in })
        c.endDrag(settleDuration: 0.05)
        XCTAssertEqual(c.state, .idle)
    }

    func test_endDrag_droppingPhaseExposesOriginalCursorAndHeight() async {
        let c = DragController(onDrop: { _, _ in })
        c.beginDrag(rowID: UUID(), originalHeight: 44, cursorY: 300)
        c.updateCursor(translation: 75) // cursorY -> 375
        c.endDrag(settleDuration: 0.05)
        guard case .dropping(let s, _) = c.state else { return XCTFail() }
        // The dropping session preserves the *last* cursor position and the
        // anchor so the overlay can interpolate from cursorY back to the
        // settle target.
        XCTAssertEqual(s.initialCursorY, 300)
        XCTAssertEqual(s.cursorY, 375)
        XCTAssertEqual(s.originalHeight, 44)
        try? await Task.sleep(nanoseconds: 120_000_000)
    }
}
