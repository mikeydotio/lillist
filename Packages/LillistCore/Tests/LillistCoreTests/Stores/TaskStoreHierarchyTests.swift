import Testing
import Foundation
@testable import LillistCore

@Suite("TaskStore hierarchy")
struct TaskStoreHierarchyTests {
    @Test("List children returns tasks ordered by position")
    func listChildrenOrdered() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parent = try await store.create(title: "Parent")
        let a = try await store.create(title: "A", parent: parent)
        let b = try await store.create(title: "B", parent: parent)
        let c = try await store.create(title: "C", parent: parent)
        let children = try await store.children(of: parent)
        let titles = children.map(\.title)
        #expect(titles == ["A", "B", "C"])
        _ = a; _ = b; _ = c
    }

    @Test("List children of nil returns root tasks")
    func listRoots() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        _ = try await store.create(title: "X")
        _ = try await store.create(title: "Y")
        let roots = try await store.children(of: nil)
        #expect(roots.count == 2)
    }

    @Test("Reparent moves a task under a new parent")
    func reparent() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "A")
        let b = try await store.create(title: "B")
        try await store.reparent(id: a, newParent: b)
        let record = try await store.fetch(id: a)
        #expect(record.parentID == b)
    }

    @Test("Reparent to root sets parent to nil")
    func reparentToRoot() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "A")
        let b = try await store.create(title: "B", parent: a)
        try await store.reparent(id: b, newParent: nil)
        #expect(try await store.fetch(id: b).parentID == nil)
    }

    @Test("Reparent rejects cycle (parent under its own descendant)")
    func cyclePrevention() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "A")
        let b = try await store.create(title: "B", parent: a)
        let c = try await store.create(title: "C", parent: b)
        await #expect(throws: LillistError.self) {
            try await store.reparent(id: a, newParent: c)
        }
    }

    @Test("Reparent rejects self as parent")
    func selfParent() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let a = try await store.create(title: "A")
        await #expect(throws: LillistError.self) {
            try await store.reparent(id: a, newParent: a)
        }
    }

    @Test("Hard delete cascades to children")
    func cascadeDelete() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parent = try await store.create(title: "Parent")
        let child = try await store.create(title: "Child", parent: parent)
        let grandchild = try await store.create(title: "Grandchild", parent: child)
        try await store.hardDelete(id: parent)
        for id in [parent, child, grandchild] {
            await #expect(throws: LillistError.notFound) {
                _ = try await store.fetch(id: id)
            }
        }
    }
}
