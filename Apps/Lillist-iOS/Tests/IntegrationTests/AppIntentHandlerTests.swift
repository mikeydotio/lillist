import XCTest
import Foundation
import LillistCore

/// Exercises the CLIBridge handlers that App Intent `perform()` bodies call,
/// against an in-memory `PersistenceController`. Cannot `@testable import
/// ShortcutsActions` (standalone test bundle, no signed app host); covers
/// the same path the intents take by calling the handlers directly.
final class AppIntentHandlerTests: XCTestCase {
    func test_AddHandler_creates_a_task() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)

        let id = try await CLIBridge.AddHandler.run(
            title: "Read paper",
            notes: "",
            startToken: nil,
            deadlineToken: nil,
            tagNames: ["research"],
            parentToken: nil,
            statusToken: nil,
            persistence: persistence,
            now: Date(),
            calendar: .current
        )

        let record = try await TaskStore(persistence: persistence).fetch(id: id)
        XCTAssertEqual(record.title, "Read paper")

        let tagIDs = try await TaskStore(persistence: persistence).tagIDs(forTask: id)
        XCTAssertEqual(tagIDs.count, 1)
    }

    func test_StatusHandler_transitions_status_to_closed() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let store = TaskStore(persistence: persistence)
        let id = try await store.create(title: "Done me")

        try await CLIBridge.StatusHandler.run(
            token: id.uuidString,
            to: .closed,
            note: nil,
            persistence: persistence
        )

        let refreshed = try await store.fetch(id: id)
        XCTAssertEqual(refreshed.status, .closed)
    }

    func test_SearchHandler_returns_matching_tasks() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let store = TaskStore(persistence: persistence)
        _ = try await store.create(title: "Buy bread")
        _ = try await store.create(title: "Write tests")

        let hits = try await CLIBridge.SearchHandler.run(
            query: "bread",
            scopeToken: nil,
            persistence: persistence
        )
        XCTAssertEqual(hits.map(\.title), ["Buy bread"])
    }

    func test_NoteHandler_appends_a_journal_note() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let store = TaskStore(persistence: persistence)
        let id = try await store.create(title: "Big project")

        _ = try await CLIBridge.NoteHandler.run(
            token: id.uuidString,
            body: "blocked on legal",
            persistence: persistence
        )

        let entries = try await JournalStore(persistence: persistence).entries(forTask: id)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].body, "blocked on legal")
    }
}
