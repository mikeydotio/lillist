import Testing
import Foundation
@testable import LillistCore

@Suite("TaskStore ordering")
struct TaskStoreOrderingTests {
    @Test("Reorder between two siblings inserts at midpoint")
    func reorderBetween() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parent = try await store.create(title: "P")
        let a = try await store.create(title: "A", parent: parent)
        let b = try await store.create(title: "B", parent: parent)
        let c = try await store.create(title: "C", parent: parent)
        try await store.reorder(id: c, after: a, before: b)
        let children = try await store.children(of: parent)
        #expect(children.map(\.title) == ["A", "C", "B"])
    }

    @Test("Reorder to the head sets position before first sibling")
    func reorderToHead() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parent = try await store.create(title: "P")
        let a = try await store.create(title: "A", parent: parent)
        let b = try await store.create(title: "B", parent: parent)
        try await store.reorder(id: b, after: nil, before: a)
        let titles = (try await store.children(of: parent)).map(\.title)
        #expect(titles == ["B", "A"])
    }

    @Test("Reorder to the tail sets position after last sibling")
    func reorderToTail() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parent = try await store.create(title: "P")
        let a = try await store.create(title: "A", parent: parent)
        let b = try await store.create(title: "B", parent: parent)
        try await store.reorder(id: a, after: b, before: nil)
        let titles = (try await store.children(of: parent)).map(\.title)
        #expect(titles == ["B", "A"])
    }

    @Test("Reorder rejects mixed-parent neighbors")
    func mixedParents() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let p1 = try await store.create(title: "P1")
        let p2 = try await store.create(title: "P2")
        let a = try await store.create(title: "A", parent: p1)
        let b = try await store.create(title: "B", parent: p2)
        let c = try await store.create(title: "C", parent: p1)
        await #expect(throws: LillistError.self) {
            try await store.reorder(id: c, after: a, before: b)
        }
    }

    @Test("Reorder rejects out-of-order anchors")
    func outOfOrderAnchors() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parent = try await store.create(title: "P")
        let a = try await store.create(title: "A", parent: parent)
        let b = try await store.create(title: "B", parent: parent)
        let c = try await store.create(title: "C", parent: parent)
        // Ask to drop C with after=B, before=A — anchors are inverted.
        await #expect(throws: LillistError.self) {
            try await store.reorder(id: c, after: b, before: a)
        }
    }
}
