import Testing
import Foundation
import CoreData
@testable import LillistCore

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

    @Test("purgeAll twice in a row: second call returns 0")
    func idempotent() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let a = try await store.create(title: "a")
        try await store.softDelete(id: a)

        let first = try await store.purgeAll()
        #expect(first == 1)
        let second = try await store.purgeAll()
        #expect(second == 0)
    }

    @Test("GUARD: purgeAll cascades to journal entries (no orphans left in store)")
    func purgeCascadesToJournalEntries() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let journals = JournalStore(persistence: persistence)
        let parent = try await store.create(title: "parent")
        let child = try await store.create(title: "child", parent: parent)
        _ = try await journals.appendNote(taskID: child, body: "child note")
        try await store.softDelete(id: parent)

        let purged = try await store.purgeAll()
        #expect(purged == 2)

        let remainingJournals: Int = try await persistence.container.viewContext.perform {
            let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
            return try persistence.container.viewContext.count(for: req)
        }
        #expect(remainingJournals == 0)
        let remainingTasks = try await store.children(of: nil)
        #expect(remainingTasks.isEmpty)
    }

    @Test("RED: purgeAll cascade count math holds on a multi-level tree")
    func purgeCountMatchesMultiLevelCascade() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let parent = try await store.create(title: "parent")
        let child = try await store.create(title: "child", parent: parent)
        _ = try await store.create(title: "grandchild", parent: child)

        // Soft-deleting the parent cascades the soft-delete down the whole
        // subtree (applySoftDelete recurses), so all three rows are trashed.
        try await store.softDelete(id: parent)

        let purged = try await store.purgeAll()
        #expect(purged == 3)

        let remainingTaskRows: Int = try await persistence.container.viewContext.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            return try persistence.container.viewContext.count(for: req)
        }
        #expect(remainingTaskRows == 0)
    }

    @Test("CascadeReaper recursion reaches a deep (4-level) tree")
    func purgeCountMatchesDeepCascade() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let parent = try await store.create(title: "parent")
        let child = try await store.create(title: "child", parent: parent)
        let grandchild = try await store.create(title: "grandchild", parent: child)
        _ = try await store.create(title: "great-grandchild", parent: grandchild)

        try await store.softDelete(id: parent)

        let purged = try await store.purgeAll()
        #expect(purged == 4)

        let remainingTaskRows: Int = try await persistence.container.viewContext.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            return try persistence.container.viewContext.count(for: req)
        }
        #expect(remainingTaskRows == 0)
    }
}
