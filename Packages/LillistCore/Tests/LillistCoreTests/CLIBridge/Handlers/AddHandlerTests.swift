import Testing
import Foundation
@testable import LillistCore

@Suite("CLIBridge.AddHandler")
struct AddHandlerTests {
    @Test("Creates a root task and returns its UUID")
    func basicAdd() async throws {
        let p = try await TestStore.make()
        let id = try await CLIBridge.AddHandler.run(
            title: "Buy milk",
            notes: "",
            startToken: nil,
            deadlineToken: nil,
            tagNames: [],
            parentToken: nil,
            statusToken: nil,
            persistence: p,
            now: Date(),
            calendar: Calendar.current
        )
        let record = try await TaskStore(persistence: p).fetch(id: id)
        #expect(record.title == "Buy milk")
        #expect(record.status == .todo)
    }

    @Test("Applies start and deadline tokens")
    func datesApplied() async throws {
        let p = try await TestStore.make()
        let id = try await CLIBridge.AddHandler.run(
            title: "Demo",
            notes: "",
            startToken: "2026-06-01",
            deadlineToken: "2026-06-15T09:00:00Z",
            tagNames: [],
            parentToken: nil,
            statusToken: nil,
            persistence: p,
            now: Date(),
            calendar: Calendar.current
        )
        let record = try await TaskStore(persistence: p).fetch(id: id)
        #expect(record.start != nil)
        #expect(record.startHasTime == false)
        #expect(record.deadline != nil)
        #expect(record.deadlineHasTime == true)
    }

    @Test("Applies tag names creating them as needed")
    func tagsCreated() async throws {
        let p = try await TestStore.make()
        let id = try await CLIBridge.AddHandler.run(
            title: "Demo",
            notes: "",
            startToken: nil, deadlineToken: nil,
            tagNames: ["Work"],
            parentToken: nil, statusToken: nil,
            persistence: p, now: Date(), calendar: .current
        )
        let tagIDs = try await TaskStore(persistence: p).tagIDs(forTask: id)
        #expect(tagIDs.count == 1)
    }

    @Test("Parent token resolves via fuzzy match")
    func parentResolved() async throws {
        let p = try await TestStore.make()
        let parentID = try await TaskStore(persistence: p).create(title: "Project")
        let child = try await CLIBridge.AddHandler.run(
            title: "subtask",
            notes: "",
            startToken: nil, deadlineToken: nil,
            tagNames: [],
            parentToken: "Project",
            statusToken: nil,
            persistence: p, now: Date(), calendar: .current
        )
        let rec = try await TaskStore(persistence: p).fetch(id: child)
        #expect(rec.parentID == parentID)
    }

    @Test("Status token applied")
    func statusApplied() async throws {
        let p = try await TestStore.make()
        let id = try await CLIBridge.AddHandler.run(
            title: "Demo",
            notes: "",
            startToken: nil, deadlineToken: nil,
            tagNames: [],
            parentToken: nil,
            statusToken: "started",
            persistence: p, now: Date(), calendar: .current
        )
        let rec = try await TaskStore(persistence: p).fetch(id: id)
        #expect(rec.status == .started)
    }

    @Test("Reuses an existing tag rather than duplicating it")
    func reusesExistingTag() async throws {
        let p = try await TestStore.make()
        let existing = try await TagStore(persistence: p).create(name: "Inbox")
        let id = try await CLIBridge.AddHandler.run(
            title: "T",
            notes: "",
            startToken: nil, deadlineToken: nil,
            tagNames: ["Inbox"],
            parentToken: nil, statusToken: nil,
            persistence: p, now: Date(), calendar: .current
        )
        let assigned = try await TaskStore(persistence: p).tagIDs(forTask: id)
        #expect(assigned == [existing])
    }
}
