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

    @Test("60 successive same-region inserts keep positions strictly increasing")
    func repeatedSameGapInsertsCompact() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parent = try await store.create(title: "P")
        // Two stable bookends; every insert targets the gap between them.
        let head = try await store.create(title: "head", parent: parent)
        let tail = try await store.create(title: "tail", parent: parent)

        // Repeatedly drop a fresh row into the (head, currentSecond) gap.
        // Without compaction the midpoint underflows and positions collide.
        for i in 0..<60 {
            let row = try await store.create(title: "row\(i)", parent: parent)
            let children = try await store.children(of: parent)
            // The row immediately after `head` in current order is the
            // "before" anchor; `head` is the "after" anchor.
            let afterID = head
            let beforeID = children.first { $0.id != head && $0.id != row }!.id
            try await store.reorder(id: row, after: afterID, before: beforeID)
        }

        let positions = (try await store.children(of: parent)).map(\.position)
        // Strictly increasing — no collisions, no underflow.
        for i in 1..<positions.count {
            #expect(positions[i] > positions[i - 1])
        }
        // All distinct.
        #expect(Set(positions).count == positions.count)
        _ = tail
    }

    // MARK: - Placement

    @Test("create(placement: .top) inserts each new root task above the rest")
    func createAtTopReversesOrder() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        _ = try await store.create(title: "A", placement: .top)
        _ = try await store.create(title: "B", placement: .top)
        _ = try await store.create(title: "C", placement: .top)
        // Each capture lands at the head, so the newest is first.
        let titles = (try await store.children(of: nil)).map(\.title)
        #expect(titles == ["C", "B", "A"])
    }

    @Test("create(placement: .top) into an empty group is the only/first child")
    func createAtTopEmptyGroup() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parent = try await store.create(title: "P")
        _ = try await store.create(title: "only", parent: parent, placement: .top)
        let titles = (try await store.children(of: parent)).map(\.title)
        #expect(titles == ["only"])
    }

    @Test("create(placement: .top) lands above earlier .bottom-appended siblings")
    func topInsertSitsAboveAppendedSiblings() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        // Default placement appends (the historical behavior the rest of the
        // suite relies on).
        _ = try await store.create(title: "first")
        _ = try await store.create(title: "second")
        // A top capture must jump ahead of both.
        _ = try await store.create(title: "newest", placement: .top)
        let titles = (try await store.children(of: nil)).map(\.title)
        #expect(titles == ["newest", "first", "second"])
    }

    @Test("create default placement still appends to the bottom")
    func defaultPlacementAppends() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        _ = try await store.create(title: "A")
        _ = try await store.create(title: "B")
        _ = try await store.create(title: "C")
        let titles = (try await store.children(of: nil)).map(\.title)
        #expect(titles == ["A", "B", "C"])
    }
}
