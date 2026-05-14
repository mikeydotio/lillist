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

    func test_AddHandler_reuses_a_case_insensitive_existing_tag() async throws {
        // Regression: AddHandler.firstTagWithName used to be case-sensitive
        // while TagStore.findOrCreate (used by Quick Capture) is case-insensitive.
        // Quick Capture would normalize "Errands" → "errands" tag, then the
        // App Intent's AddHandler call with `tags: ["Errands"]` would create
        // a second "Errands" tag instead of reusing it. Both surfaces now
        // converge on a single tag.
        let persistence = try await PersistenceController(configuration: .inMemory)
        let tags = TagStore(persistence: persistence)
        _ = try await tags.findOrCreate(name: "errands")

        let id = try await CLIBridge.AddHandler.run(
            title: "Buy milk",
            notes: "",
            startToken: nil,
            deadlineToken: nil,
            tagNames: ["Errands"],
            parentToken: nil,
            statusToken: nil,
            persistence: persistence,
            now: Date(),
            calendar: .current
        )

        let allTags = try await tags.children(of: nil)
        XCTAssertEqual(allTags.count, 1, "Expected one tag row, not two — case differences should collapse")
        let taggedIDs = try await TaskStore(persistence: persistence).tagIDs(forTask: id)
        XCTAssertEqual(taggedIDs.count, 1)
        XCTAssertEqual(taggedIDs[0], allTags[0].id)
    }

    func test_SearchHandler_empty_query_returns_no_tasks() async throws {
        // SearchTasksIntent passes the user's query straight through. On
        // Foundation in iOS 18, `localizedStandardContains("")` returns
        // `false`, so an empty query yields nothing — which is the safe
        // behavior we want (no accidental full-database dump when a
        // Shortcut has an empty binding). This test pins that behavior so
        // a future Foundation change doesn't silently regress it.
        let persistence = try await PersistenceController(configuration: .inMemory)
        let store = TaskStore(persistence: persistence)
        _ = try await store.create(title: "Buy milk")
        _ = try await store.create(title: "Walk dog")

        let hits = try await CLIBridge.SearchHandler.run(
            query: "",
            scopeToken: nil,
            persistence: persistence
        )
        XCTAssertEqual(hits.count, 0, "Empty query must not match any task")
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
