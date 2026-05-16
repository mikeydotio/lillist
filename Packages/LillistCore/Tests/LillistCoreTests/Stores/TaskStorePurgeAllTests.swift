import Testing
import Foundation
import LillistCore

@Suite("TaskStore.purgeAll")
struct TaskStorePurgeAllTests {
    @Test("Purges every trashed task and returns the count")
    func purgesTrashed() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let a = try await store.create(title: "a")
        let b = try await store.create(title: "b")
        let c = try await store.create(title: "c")
        try await store.softDelete(id: a)
        try await store.softDelete(id: c)

        let purged = try await store.purgeAll()

        #expect(purged == 2)
        let remaining = try await store.children(of: nil).map(\.id)
        #expect(remaining == [b])
        let trash = try await store.trashed()
        #expect(trash.isEmpty)
    }

    @Test("No-op when trash is empty")
    func emptyTrash() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        _ = try await store.create(title: "a")
        let purged = try await store.purgeAll()
        #expect(purged == 0)
    }

    @Test("Cascades to descendants of a trashed parent")
    func cascadesToDescendants() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let parent = try await store.create(title: "parent")
        _ = try await store.create(title: "child", parent: parent)
        try await store.softDelete(id: parent)

        let purged = try await store.purgeAll()
        #expect(purged == 2)
    }
}
