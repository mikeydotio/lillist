import Testing
import Foundation
@testable import LillistCore

@Suite("JournalStore")
struct JournalStoreTests {
    @Test("Append a user note")
    func appendNote() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let journals = JournalStore(persistence: p)
        let task = try await tasks.create(title: "T")
        let id = try await journals.appendNote(taskID: task, body: "stuck on auth")
        let entries = try await journals.entries(forTask: task)
        #expect(entries.count == 1)
        #expect(entries[0].id == id)
        #expect(entries[0].body == "stuck on auth")
        #expect(entries[0].kind == .note)
    }

    @Test("Edit a user note sets editedAt and updates body")
    func editNote() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let journals = JournalStore(persistence: p)
        let task = try await tasks.create(title: "T")
        let id = try await journals.appendNote(taskID: task, body: "before")
        try await Task.sleep(nanoseconds: 10_000_000)
        try await journals.editNote(id: id, body: "after")
        let entry = try await journals.fetch(id: id)
        #expect(entry.body == "after")
        #expect(entry.editedAt != nil)
    }

    @Test("Editing a system entry throws")
    func systemUneditable() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let journals = JournalStore(persistence: p)
        let task = try await tasks.create(title: "T")
        try await tasks.transition(id: task, to: .started)
        let entries = try await journals.entries(forTask: task)
        let statusEntry = entries.first(where: { $0.kind == .statusChange })!
        await #expect(throws: LillistError.self) {
            try await journals.editNote(id: statusEntry.id, body: "bogus")
        }
    }

    @Test("Delete a user note")
    func deleteNote() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let journals = JournalStore(persistence: p)
        let task = try await tasks.create(title: "T")
        let id = try await journals.appendNote(taskID: task, body: "x")
        try await journals.delete(id: id)
        await #expect(throws: LillistError.notFound) {
            _ = try await journals.fetch(id: id)
        }
    }

    @Test("Deleting a system entry throws")
    func systemUndeletable() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let journals = JournalStore(persistence: p)
        let task = try await tasks.create(title: "T")
        try await tasks.transition(id: task, to: .started)
        let statusEntry = (try await journals.entries(forTask: task)).first(where: { $0.kind == .statusChange })!
        await #expect(throws: LillistError.self) {
            try await journals.delete(id: statusEntry.id)
        }
    }

    @Test("Entries returned in ascending createdAt order")
    func order() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let journals = JournalStore(persistence: p)
        let task = try await tasks.create(title: "T")
        _ = try await journals.appendNote(taskID: task, body: "first")
        try await Task.sleep(nanoseconds: 10_000_000)
        _ = try await journals.appendNote(taskID: task, body: "second")
        let entries = try await journals.entries(forTask: task)
        #expect(entries.map(\.body) == ["first", "second"])
    }
}
