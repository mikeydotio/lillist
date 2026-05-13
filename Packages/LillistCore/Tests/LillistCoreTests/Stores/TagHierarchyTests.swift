import Testing
import Foundation
@testable import LillistCore

@Suite("Tag hierarchy")
struct TagHierarchyTests {
    @Test("Create with parent")
    func createWithParent() async throws {
        let p = try await TestStore.make()
        let store = TagStore(persistence: p)
        let work = try await store.create(name: "Work")
        let email = try await store.create(name: "Email", parent: work)
        #expect(try await store.fetch(id: email).parentID == work)
    }

    @Test("Sibling collision is namespaced to parent")
    func siblingsScopedToParent() async throws {
        let p = try await TestStore.make()
        let store = TagStore(persistence: p)
        let a = try await store.create(name: "A")
        let b = try await store.create(name: "B")
        _ = try await store.create(name: "Email", parent: a)
        let underB = try await store.create(name: "Email", parent: b)
        #expect(try await store.fetch(id: underB).name == "Email")
    }

    @Test("List children of nil returns root tags")
    func rootList() async throws {
        let p = try await TestStore.make()
        let store = TagStore(persistence: p)
        _ = try await store.create(name: "A")
        _ = try await store.create(name: "B")
        let roots = try await store.children(of: nil)
        #expect(roots.count == 2)
    }

    @Test("Reparent moves tag under new parent")
    func reparent() async throws {
        let p = try await TestStore.make()
        let store = TagStore(persistence: p)
        let a = try await store.create(name: "A")
        let b = try await store.create(name: "B")
        let child = try await store.create(name: "child", parent: a)
        try await store.reparent(id: child, newParent: b)
        #expect(try await store.fetch(id: child).parentID == b)
    }

    @Test("Reparent rejects cycle")
    func cycle() async throws {
        let p = try await TestStore.make()
        let store = TagStore(persistence: p)
        let a = try await store.create(name: "A")
        let b = try await store.create(name: "B", parent: a)
        let c = try await store.create(name: "C", parent: b)
        await #expect(throws: LillistError.self) {
            try await store.reparent(id: a, newParent: c)
        }
    }

    @Test("Delete cascades to descendants")
    func cascadeDelete() async throws {
        let p = try await TestStore.make()
        let store = TagStore(persistence: p)
        let a = try await store.create(name: "A")
        let b = try await store.create(name: "B", parent: a)
        let c = try await store.create(name: "C", parent: b)
        try await store.delete(id: a)
        for id in [a, b, c] {
            await #expect(throws: LillistError.notFound) {
                _ = try await store.fetch(id: id)
            }
        }
    }
}
