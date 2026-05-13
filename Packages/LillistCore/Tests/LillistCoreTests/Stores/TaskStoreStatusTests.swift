import Testing
import Foundation
@testable import LillistCore

@Suite("TaskStore status")
struct TaskStoreStatusTests {
    @Test("Transition to closed sets closedAt")
    func toClosed() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "T")
        try await store.transition(id: id, to: .closed)
        let record = try await store.fetch(id: id)
        #expect(record.status == .closed)
        #expect(record.closedAt != nil)
    }

    @Test("Transition out of closed clears closedAt")
    func outOfClosed() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "T")
        try await store.transition(id: id, to: .closed)
        try await store.transition(id: id, to: .todo)
        let record = try await store.fetch(id: id)
        #expect(record.status == .todo)
        #expect(record.closedAt == nil)
    }

    @Test("Transition appends a system journal entry")
    func journalEntryCreated() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let journals = JournalStore(persistence: p)
        let id = try await store.create(title: "T")
        try await store.transition(id: id, to: .started)
        let entries = try await journals.entries(forTask: id)
        let statusChanges = entries.filter { $0.kind == .statusChange }
        #expect(statusChanges.count == 1)
    }

    @Test("Self-transition is a no-op")
    func selfTransition() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let journals = JournalStore(persistence: p)
        let id = try await store.create(title: "T")
        try await store.transition(id: id, to: .todo)
        let entries = try await journals.entries(forTask: id)
        #expect(entries.contains(where: { $0.kind == .statusChange }) == false)
    }

    @Test("Transition bumps modifiedAt")
    func modifiedBumped() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "T")
        let before = try await store.fetch(id: id).modifiedAt
        try await Task.sleep(nanoseconds: 10_000_000)
        try await store.transition(id: id, to: .started)
        let after = try await store.fetch(id: id).modifiedAt
        #expect((after ?? .distantPast) > (before ?? .distantPast))
    }
}
