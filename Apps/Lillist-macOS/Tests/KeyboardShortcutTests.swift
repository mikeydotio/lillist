import XCTest
import LillistCore
import LillistUI

@MainActor
final class KeyboardShortcutTests: XCTestCase {
    func test_markClosedNotification_transitionsStatus() async throws {
        let p = try await PersistenceController(configuration: .inMemory)
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "Test")

        try await store.transition(id: id, to: .closed)
        let r = try await store.fetch(id: id)
        XCTAssertEqual(r.status, .closed)
        XCTAssertNotNil(r.closedAt)
    }

    func test_toggleStarted_cyclesViaStatusCycler() async throws {
        let p = try await PersistenceController(configuration: .inMemory)
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "Test")
        var current = try await store.fetch(id: id).status

        current = StatusCycler.nextOnSpace(from: current)
        try await store.transition(id: id, to: current)
        let s1 = try await store.fetch(id: id).status
        XCTAssertEqual(s1, .started)

        current = StatusCycler.nextOnSpace(from: current)
        try await store.transition(id: id, to: current)
        let s2 = try await store.fetch(id: id).status
        XCTAssertEqual(s2, .todo)
    }

    func test_indentOutdentReparentsCorrectly() async throws {
        let p = try await PersistenceController(configuration: .inMemory)
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "A")
        let b = try await store.create(title: "B")
        try await store.reparent(id: b, newParent: a)
        let kids1 = try await store.children(of: a).map(\.id)
        XCTAssertEqual(kids1, [b])
        try await store.reparent(id: b, newParent: nil)
        let kids2 = try await store.children(of: a)
        XCTAssertEqual(kids2.count, 0)
        let roots = try await store.children(of: nil).map(\.id)
        XCTAssertTrue(roots.contains(b))
    }

    // MARK: - Plan 19 Task 8: arrow-key selection-advance contract

    func test_arrowKey_downAdvancesSelectionByOne() {
        let ids = (0..<5).map { _ in UUID() }
        var selection: UUID? = ids[2]
        selection = SelectionAdvance.advance(current: selection, ordered: ids, direction: 1)
        XCTAssertEqual(selection, ids[3])
    }

    func test_arrowKey_upAdvancesSelectionByMinusOne() {
        let ids = (0..<5).map { _ in UUID() }
        var selection: UUID? = ids[2]
        selection = SelectionAdvance.advance(current: selection, ordered: ids, direction: -1)
        XCTAssertEqual(selection, ids[1])
    }

    func test_arrowKey_clampsAtBottomEdge() {
        let ids = (0..<3).map { _ in UUID() }
        let selection = SelectionAdvance.advance(current: ids.last, ordered: ids, direction: 1)
        XCTAssertEqual(selection, ids.last)
    }

    func test_arrowKey_clampsAtTopEdge() {
        let ids = (0..<3).map { _ in UUID() }
        let selection = SelectionAdvance.advance(current: ids.first, ordered: ids, direction: -1)
        XCTAssertEqual(selection, ids.first)
    }

    func test_arrowKey_emptyListReturnsCurrentUnchanged() {
        let prior: UUID? = UUID()
        let selection = SelectionAdvance.advance(current: prior, ordered: [], direction: 1)
        XCTAssertEqual(selection, prior)
    }

    func test_arrowKey_nilSelectionDownPicksFirst() {
        let ids = (0..<3).map { _ in UUID() }
        let selection = SelectionAdvance.advance(current: nil, ordered: ids, direction: 1)
        XCTAssertEqual(selection, ids.first)
    }

    func test_arrowKey_nilSelectionUpPicksLast() {
        let ids = (0..<3).map { _ in UUID() }
        let selection = SelectionAdvance.advance(current: nil, ordered: ids, direction: -1)
        XCTAssertEqual(selection, ids.last)
    }
}
