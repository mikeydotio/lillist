import XCTest
import LillistCore
@testable import LillistUI

/// Collects diagnostic events emitted by the drag layer without touching disk.
actor SpyDiagnosticSink: DiagnosticSink {
    private(set) var events: [DiagnosticEvent] = []
    func log(_ event: DiagnosticEvent) { events.append(event) }
}

@MainActor
final class DragControllerDiagnosticTests: XCTestCase {
    /// Drag emits are fire-and-forget `Task`s; poll the spy until they land.
    private func waitForEvents(_ spy: SpyDiagnosticSink, count: Int, timeout: TimeInterval = 2) async -> [DiagnosticEvent] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let events = await spy.events
            if events.count >= count { return events }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return await spy.events
    }

    func test_emits_start_over_per_setResolvedTarget_and_drop() async throws {
        let spy = SpyDiagnosticSink()
        let c = DragController(onDrop: { _, _ in })
        c.diagnosticLog = spy
        let a = UUID(), dragged = UUID(), b = UUID()
        c.flatRows = [
            DragReorderRow(id: a, parentID: nil, depth: 0),
            DragReorderRow(id: dragged, parentID: nil, depth: 0),
            DragReorderRow(id: b, parentID: nil, depth: 0),
        ]
        c.beginDrag(rowID: dragged, originalHeight: 44, cursorY: 100)
        let target = DragTarget.between(beforeID: b, afterID: a, parentID: nil)
        // Two identical setResolvedTarget calls: the controller emits 1:1 with
        // each call. Coalescing (suppressing unchanged targets) is the modifier's
        // job (DragReorderable's `if resolved != previous` guard), tested there.
        c.setResolvedTarget(target)
        c.setResolvedTarget(target)
        c.endDrag()

        let events = await waitForEvents(spy, count: 4)
        XCTAssertEqual(events.filter { $0.name == "drag.start" }.count, 1)
        XCTAssertEqual(events.filter { $0.name == "drag.over" }.count, 2)
        XCTAssertEqual(events.filter { $0.name == "drag.drop" }.count, 1)

        let start = try XCTUnwrap(events.first { $0.name == "drag.start" })
        XCTAssertEqual(start.payload["draggedID"], .string(dragged.uuidString))
        XCTAssertEqual(start.payload["sourceIndex"], .int(1))

        let drop = try XCTUnwrap(events.first { $0.name == "drag.drop" })
        XCTAssertEqual(drop.payload["kind"], .string("between"))
        XCTAssertEqual(drop.payload["draggedID"], .string(dragged.uuidString))
    }

    func test_rejected_drop_is_still_captured() async throws {
        let spy = SpyDiagnosticSink()
        let c = DragController(onDrop: { _, _ in })
        c.diagnosticLog = spy
        let dragged = UUID()
        c.flatRows = [DragReorderRow(id: dragged, parentID: nil, depth: 0)]
        c.beginDrag(rowID: dragged, originalHeight: 44, cursorY: 0)
        c.setResolvedTarget(.rejected)
        c.endDrag()   // .rejected never calls the handler, but drag.drop MUST emit
        let events = await waitForEvents(spy, count: 3)
        let drop = try XCTUnwrap(events.first { $0.name == "drag.drop" })
        XCTAssertEqual(drop.payload["kind"], .string("rejected"))
    }

    func test_no_sink_is_a_silent_noop() async throws {
        let c = DragController(onDrop: { _, _ in })   // no diagnosticLog wired
        c.flatRows = [DragReorderRow(id: UUID(), parentID: nil, depth: 0)]
        c.beginDrag(rowID: c.flatRows[0].id, originalHeight: 44, cursorY: 0)
        c.setResolvedTarget(.none)
        c.endDrag()   // must not crash without a sink
    }
}
