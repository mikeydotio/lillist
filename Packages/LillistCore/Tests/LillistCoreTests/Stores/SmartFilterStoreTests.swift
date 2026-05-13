import Testing
import Foundation
@testable import LillistCore

@Suite("SmartFilterStore — CRUD")
struct SmartFilterStoreCRUDTests {
    private func sampleGroup() -> PredicateGroup {
        .init(combinator: .all, predicates: [
            .leaf(.init(field: .status, op: .is, value: .statusSet([.todo])))
        ])
    }

    @Test("Create returns an id and the row is fetchable")
    func createAndFetch() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        let id = try await store.create(name: "Today", group: sampleGroup())
        let rec = try await store.fetch(id: id)
        #expect(rec.name == "Today")
        #expect(rec.group.combinator == .all)
        #expect(rec.group.predicates.count == 1)
    }

    @Test("Create rejects empty name")
    func emptyNameRejected() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        await #expect(throws: LillistError.self) {
            _ = try await store.create(name: "  ", group: PredicateGroup(combinator: .all, predicates: []))
        }
    }

    @Test("Fetch unknown id throws notFound")
    func fetchNotFound() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        await #expect(throws: LillistError.notFound) {
            _ = try await store.fetch(id: UUID())
        }
    }

    @Test("List returns rows in position order")
    func listOrder() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        let a = try await store.create(name: "A", group: sampleGroup())
        let b = try await store.create(name: "B", group: sampleGroup())
        let c = try await store.create(name: "C", group: sampleGroup())
        let list = try await store.list()
        #expect(list.map(\.id) == [a, b, c])
    }

    @Test("Update mutates fields")
    func update() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        let id = try await store.create(name: "Today", group: sampleGroup())
        try await store.update(id: id) { draft in
            draft.name = "Today (renamed)"
            draft.tintColor = "#ff8800"
            draft.sortField = .deadline
            draft.sortAscending = false
        }
        let r = try await store.fetch(id: id)
        #expect(r.name == "Today (renamed)")
        #expect(r.tintColor == "#ff8800")
        #expect(r.sortField == .deadline)
        #expect(r.sortAscending == false)
    }

    @Test("Update can replace the predicate group")
    func updateGroup() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        let id = try await store.create(name: "X", group: sampleGroup())
        let newGroup = PredicateGroup(combinator: .any, predicates: [
            .leaf(.init(field: .isPinned, op: .is, value: .bool(true)))
        ])
        try await store.update(id: id) { d in d.group = newGroup }
        let r = try await store.fetch(id: id)
        #expect(r.group.combinator == .any)
    }

    @Test("Delete removes the row")
    func delete() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        let id = try await store.create(name: "X", group: sampleGroup())
        try await store.delete(id: id)
        await #expect(throws: LillistError.notFound) {
            _ = try await store.fetch(id: id)
        }
    }
}

@Suite("SmartFilterStore — pinning and reorder")
struct SmartFilterStorePinReorderTests {
    private func sample() -> PredicateGroup {
        .init(combinator: .all, predicates: [])
    }

    @Test("setPinned toggles isPinned")
    func setPinned() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        let id = try await store.create(name: "X", group: sample())
        try await store.setPinned(id: id, pinned: true)
        #expect(try await store.fetch(id: id).isPinned == true)
        try await store.setPinned(id: id, pinned: false)
        #expect(try await store.fetch(id: id).isPinned == false)
    }

    @Test("reorder moves a row between two siblings")
    func reorder() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        let a = try await store.create(name: "A", group: sample())
        let b = try await store.create(name: "B", group: sample())
        let c = try await store.create(name: "C", group: sample())
        // Move C between A and B → expected order A, C, B
        try await store.reorder(id: c, after: a, before: b)
        let list = try await store.list()
        #expect(list.map(\.id) == [a, c, b])
    }

    @Test("reorder to head and tail")
    func reorderEdges() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        let a = try await store.create(name: "A", group: sample())
        let b = try await store.create(name: "B", group: sample())
        let c = try await store.create(name: "C", group: sample())
        try await store.reorder(id: c, after: nil, before: a)
        #expect(try await store.list().map(\.id) == [c, a, b])
        try await store.reorder(id: c, after: b, before: nil)
        #expect(try await store.list().map(\.id) == [a, b, c])
    }
}
