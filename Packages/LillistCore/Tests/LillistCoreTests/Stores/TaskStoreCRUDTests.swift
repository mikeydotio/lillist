import Testing
import Foundation
@testable import LillistCore

@Suite("TaskStore CRUD")
struct TaskStoreCRUDTests {
    @Test("Create assigns id, timestamps, and default status")
    func create() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "Buy milk")
        let task = try await store.fetch(id: id)
        #expect(task.title == "Buy milk")
        #expect(task.status == .todo)
        #expect(task.createdAt != nil)
        #expect(task.modifiedAt != nil)
        #expect(task.deletedAt == nil)
        #expect(task.closedAt == nil)
    }

    @Test("Create rejects empty title")
    func emptyTitleRejected() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        await #expect(throws: LillistError.self) {
            _ = try await store.create(title: "")
        }
    }

    @Test("Fetch by unknown id throws notFound")
    func notFound() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        await #expect(throws: LillistError.notFound) {
            _ = try await store.fetch(id: UUID())
        }
    }

    @Test("Update modifies the title and bumps modifiedAt")
    func update() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "Original")
        let before = try await store.fetch(id: id).modifiedAt
        try await Task.sleep(nanoseconds: 10_000_000)
        try await store.update(id: id) { $0.title = "Updated" }
        let task = try await store.fetch(id: id)
        #expect(task.title == "Updated")
        #expect((task.modifiedAt ?? .distantPast) > (before ?? .distantPast))
    }

    @Test("Hard delete removes the task")
    func hardDelete() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "doomed")
        try await store.hardDelete(id: id)
        await #expect(throws: LillistError.notFound) {
            _ = try await store.fetch(id: id)
        }
    }
}
