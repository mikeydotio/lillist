import Testing
import Foundation
@testable import LillistCore

@Suite("TaskStore.scheduleFollowUp")
struct TaskStoreFollowUpTests {
    @Test("Creates a sibling with status .todo, given title and deadline")
    func createsSibling() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let parent = try await tasks.create(title: "Project")
        let blocked = try await tasks.create(title: "Wait on team", parent: parent)
        try await tasks.transition(id: blocked, to: .blocked)

        let when = Date().addingTimeInterval(24 * 3600)
        let followUp = try await tasks.scheduleFollowUp(
            parentTaskID: blocked,
            title: "Follow up",
            deadline: when
        )

        let followUpRecord = try await tasks.fetch(id: followUp)
        #expect(followUpRecord.title == "Follow up")
        #expect(followUpRecord.status == .todo)
        #expect(followUpRecord.deadline == when)
        // Same parent as the blocked task (i.e., sibling).
        #expect(followUpRecord.parentID == parent)
    }

    @Test("Blocked task gets a createdFollowUp journal entry with payload referencing the follow-up")
    func journalEntry() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let journals = JournalStore(persistence: p)
        let parent = try await tasks.create(title: "Project")
        let blocked = try await tasks.create(title: "Wait", parent: parent)
        try await tasks.transition(id: blocked, to: .blocked)

        let followUp = try await tasks.scheduleFollowUp(
            parentTaskID: blocked,
            title: "Follow up",
            deadline: Date().addingTimeInterval(24 * 3600)
        )

        let entries = try await journals.entries(forTask: blocked)
        let followUpEntries = entries.filter { $0.kind == .createdFollowUp }
        #expect(followUpEntries.count == 1)

        let payload = followUpEntries[0].payload!
        let decoded = try JSONSerialization.jsonObject(with: payload) as? [String: String]
        #expect(decoded?["followUpTaskID"] == followUp.uuidString)
    }

    @Test("Root-level blocked task creates a root-level sibling")
    func rootLevel() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let blocked = try await tasks.create(title: "Wait")
        try await tasks.transition(id: blocked, to: .blocked)

        let followUp = try await tasks.scheduleFollowUp(
            parentTaskID: blocked,
            title: "Follow up",
            deadline: Date().addingTimeInterval(24 * 3600)
        )
        let followUpRecord = try await tasks.fetch(id: followUp)
        #expect(followUpRecord.parentID == nil)
    }

    @Test("Missing parent task throws .notFound")
    func missingParent() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        await #expect(throws: LillistError.notFound) {
            _ = try await tasks.scheduleFollowUp(
                parentTaskID: UUID(),
                title: "x",
                deadline: Date()
            )
        }
    }
}
