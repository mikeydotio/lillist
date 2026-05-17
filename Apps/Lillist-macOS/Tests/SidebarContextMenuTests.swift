import Testing
import LillistCore
import Foundation

@Suite("Sidebar context-menu wiring contract")
struct SidebarContextMenuTests {
    @Test("Tag rename mutation flows through TagStore")
    func tagRenameThroughStore() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let tags = TagStore(persistence: persistence)
        let id = try await tags.create(name: "old")
        try await tags.rename(id: id, to: "new")
        let fetched = try await tags.fetch(id: id)
        #expect(fetched.name == "new")
    }

    @Test("Tag tint-color mutation flows through TagStore")
    func tagTintThroughStore() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let tags = TagStore(persistence: persistence)
        let id = try await tags.create(name: "groceries")
        try await tags.setTintColor(id: id, hex: "#FF0000")
        let fetched = try await tags.fetch(id: id)
        #expect(fetched.tintColor == "#FF0000")
    }

    @Test("Tag delete removes it from children(of: nil)")
    func tagDelete() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let tags = TagStore(persistence: persistence)
        let id = try await tags.create(name: "delete-me")
        try await tags.delete(id: id)
        let roots = try await tags.children(of: nil)
        #expect(!roots.map(\.id).contains(id))
    }

    @Test("Pinned task unpin mutation persists")
    func pinnedTaskUnpin() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let tasks = TaskStore(persistence: persistence)
        let id = try await tasks.create(title: "pinned")
        try await tasks.update(id: id) { $0.isPinned = true }
        try await tasks.update(id: id) { $0.isPinned = false }
        let pinned = try await tasks.pinned()
        #expect(!pinned.map(\.id).contains(id))
    }

    @Test("Pinned task rename mutation flows through TaskStore")
    func pinnedTaskRename() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let tasks = TaskStore(persistence: persistence)
        let id = try await tasks.create(title: "old title")
        try await tasks.update(id: id) { $0.title = "new title" }
        let fetched = try await tasks.fetch(id: id)
        #expect(fetched.title == "new title")
    }

    @Test("Filter rename mutation flows through SmartFilterStore")
    func filterRename() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let filters = SmartFilterStore(persistence: persistence)
        let group = PredicateGroup(combinator: .all, predicates: [])
        let id = try await filters.create(name: "old", group: group)
        try await filters.update(id: id) { $0.name = "new" }
        let fetched = try await filters.fetch(id: id)
        #expect(fetched.name == "new")
    }

    @Test("Filter delete removes it from list()")
    func filterDelete() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let filters = SmartFilterStore(persistence: persistence)
        let group = PredicateGroup(combinator: .all, predicates: [])
        let id = try await filters.create(name: "delete-me", group: group)
        try await filters.delete(id: id)
        let all = try await filters.list()
        #expect(!all.map(\.id).contains(id))
    }
}
