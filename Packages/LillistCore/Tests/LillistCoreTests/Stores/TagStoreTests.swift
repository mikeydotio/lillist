import Testing
import Foundation
@testable import LillistCore

@Suite("TagStore")
struct TagStoreTests {
    @Test("Create tag with name and tint")
    func create() async throws {
        let p = try await TestStore.make()
        let store = TagStore(persistence: p)
        let id = try await store.create(name: "Work", tintColor: "#FF0000")
        let tag = try await store.fetch(id: id)
        #expect(tag.name == "Work")
        #expect(tag.tintColor == "#FF0000")
        #expect(tag.parentID == nil)
    }

    @Test("Empty name rejected")
    func emptyName() async throws {
        let p = try await TestStore.make()
        let store = TagStore(persistence: p)
        await #expect(throws: LillistError.self) {
            _ = try await store.create(name: "")
        }
    }

    @Test("Sibling name collision auto-suffixes")
    func collisionAutoSuffix() async throws {
        let p = try await TestStore.make()
        let store = TagStore(persistence: p)
        _ = try await store.create(name: "Work")
        let id2 = try await store.create(name: "Work")
        let id3 = try await store.create(name: "Work")
        #expect(try await store.fetch(id: id2).name == "Work (2)")
        #expect(try await store.fetch(id: id3).name == "Work (3)")
    }

    @Test("Rename collision auto-suffixes")
    func renameCollision() async throws {
        let p = try await TestStore.make()
        let store = TagStore(persistence: p)
        _ = try await store.create(name: "Work")
        let other = try await store.create(name: "Home")
        try await store.rename(id: other, to: "Work")
        #expect(try await store.fetch(id: other).name == "Work (2)")
    }

    @Test("Rename to same name is a no-op")
    func renameNoOp() async throws {
        let p = try await TestStore.make()
        let store = TagStore(persistence: p)
        let id = try await store.create(name: "Work")
        try await store.rename(id: id, to: "Work")
        #expect(try await store.fetch(id: id).name == "Work")
    }

    @Test("Delete removes the tag")
    func delete() async throws {
        let p = try await TestStore.make()
        let store = TagStore(persistence: p)
        let id = try await store.create(name: "Tmp")
        try await store.delete(id: id)
        await #expect(throws: LillistError.notFound) {
            _ = try await store.fetch(id: id)
        }
    }
}
