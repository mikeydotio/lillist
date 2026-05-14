import XCTest
import LillistCore
import LillistUI

@MainActor
final class DragDropInteractionTests: XCTestCase {
    func test_dropOnto_reparents() async throws {
        let p = try await PersistenceController(configuration: .inMemory)
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "A")
        let b = try await store.create(title: "B")
        try await store.reparent(id: b, newParent: a)
        let kidsOfA = try await store.children(of: a).map(\.id)
        XCTAssertEqual(kidsOfA, [b])
        let roots = try await store.children(of: nil).map(\.id)
        XCTAssertEqual(roots, [a])
    }

    func test_dropBetween_reorders() async throws {
        let p = try await PersistenceController(configuration: .inMemory)
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "A")
        let b = try await store.create(title: "B")
        let c = try await store.create(title: "C")
        // Drop C before A → order becomes [C, A, B]
        try await store.reorder(id: c, after: nil, before: a)
        let order = try await store.children(of: nil).map(\.id)
        XCTAssertEqual(order, [c, a, b])
    }

    func test_classify_dropPosition_maps_to_correct_action() {
        XCTAssertEqual(DropPosition.classify(yInRow: 2,  rowHeight: 44), .before)
        XCTAssertEqual(DropPosition.classify(yInRow: 22, rowHeight: 44), .onto)
        XCTAssertEqual(DropPosition.classify(yInRow: 42, rowHeight: 44), .after)
    }
}
