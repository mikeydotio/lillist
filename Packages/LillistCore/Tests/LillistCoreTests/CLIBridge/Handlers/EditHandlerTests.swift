import Testing
import Foundation
@testable import LillistCore

@Suite("CLIBridge.EditHandler")
struct EditHandlerTests {
    @Test("Edits title")
    func editTitle() async throws {
        let p = try await TestStore.make()
        let id = try await TaskStore(persistence: p).create(title: "Old")
        try await CLIBridge.EditHandler.run(
            token: id.uuidString,
            newTitle: "New",
            newNotes: nil,
            startToken: nil, deadlineToken: nil,
            persistence: p, now: Date(), calendar: .current
        )
        let rec = try await TaskStore(persistence: p).fetch(id: id)
        #expect(rec.title == "New")
    }

    @Test("Edits deadline")
    func editDeadline() async throws {
        let p = try await TestStore.make()
        let id = try await TaskStore(persistence: p).create(title: "T")
        try await CLIBridge.EditHandler.run(
            token: id.uuidString,
            newTitle: nil, newNotes: nil,
            startToken: nil, deadlineToken: "2026-06-01",
            persistence: p, now: Date(), calendar: .current
        )
        let rec = try await TaskStore(persistence: p).fetch(id: id)
        #expect(rec.deadline != nil)
        #expect(rec.deadlineHasTime == false)
    }

    @Test("Unset flags leave fields unchanged")
    func partialEdit() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let id = try await tasks.create(title: "Keep")
        try await tasks.update(id: id) { $0.notes = "kept" }
        try await CLIBridge.EditHandler.run(
            token: id.uuidString,
            newTitle: nil, newNotes: nil,
            startToken: nil, deadlineToken: nil,
            persistence: p, now: Date(), calendar: .current
        )
        let rec = try await tasks.fetch(id: id)
        #expect(rec.notes == "kept")
        #expect(rec.title == "Keep")
    }
}
