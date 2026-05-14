import Testing
import Foundation
@testable import LillistCore

@Suite("TagStore.findOrCreate")
struct TagStoreFindOrCreateTests {
    @Test("Creates a new tag when none exists with that name")
    func createsWhenAbsent() async throws {
        let p = try await TestStore.make()
        let store = TagStore(persistence: p)
        let id = try await store.findOrCreate(name: "groceries")
        let tag = try await store.fetch(id: id)
        #expect(tag.name == "groceries")
        #expect(tag.parentID == nil)
    }

    @Test("Returns the existing tag's id when one already exists (case-insensitive)")
    func returnsExistingCaseInsensitive() async throws {
        let p = try await TestStore.make()
        let store = TagStore(persistence: p)
        let firstID = try await store.findOrCreate(name: "Work")
        let secondID = try await store.findOrCreate(name: "work")
        #expect(firstID == secondID)
        let all = try await store.children(of: nil)
        #expect(all.count == 1)
    }

    @Test("Trims whitespace when matching")
    func trimsWhitespace() async throws {
        let p = try await TestStore.make()
        let store = TagStore(persistence: p)
        let firstID = try await store.findOrCreate(name: "  errands  ")
        let secondID = try await store.findOrCreate(name: "errands")
        #expect(firstID == secondID)
    }

    @Test("Rejects empty name")
    func rejectsEmpty() async throws {
        let p = try await TestStore.make()
        let store = TagStore(persistence: p)
        await #expect(throws: LillistError.self) {
            _ = try await store.findOrCreate(name: "   ")
        }
    }

    @Test("Scopes lookup to the given parent — same name under different parents creates two tags")
    func scopedToParent() async throws {
        let p = try await TestStore.make()
        let store = TagStore(persistence: p)
        let work = try await store.findOrCreate(name: "work")
        let personal = try await store.findOrCreate(name: "personal")
        let nameInWork = try await store.findOrCreate(name: "client-a", parent: work)
        let nameInPersonal = try await store.findOrCreate(name: "client-a", parent: personal)
        #expect(nameInWork != nameInPersonal)
    }
}
