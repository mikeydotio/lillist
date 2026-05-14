import XCTest
import LillistCore

@MainActor
final class BlockedFollowUpTests: XCTestCase {
    func test_scheduleFollowUp_createsSiblingAndJournalEntry() async throws {
        let p = try await PersistenceController(configuration: .inMemory)
        let taskStore = TaskStore(persistence: p)
        let journalStore = JournalStore(persistence: p)

        let blocked = try await taskStore.create(title: "Big project")
        try await taskStore.transition(id: blocked, to: .blocked)

        let followUp = try await taskStore.scheduleFollowUp(
            parentTaskID: blocked,
            title: "Follow up on 'Big project'",
            deadline: Date().addingTimeInterval(86400)
        )

        let f = try await taskStore.fetch(id: followUp)
        let b = try await taskStore.fetch(id: blocked)
        XCTAssertEqual(f.parentID, b.parentID)

        let entries = try await journalStore.entries(forTask: blocked)
        XCTAssertTrue(entries.contains { $0.kind == .createdFollowUp })
    }
}
