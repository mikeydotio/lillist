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
}
