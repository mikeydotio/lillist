import XCTest
import CoreData
@testable import LillistCore

final class DiagnosticHistoryObserverTests: XCTestCase {
    func test_observer_emits_position_update_with_author_on_reorder() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let spy = SpyDiagnosticSink()
        let observer = DiagnosticHistoryObserver(
            persistence: persistence,
            tokenStore: PersistentHistoryTokenStore(suiteName: "t.\(UUID().uuidString)", key: PersistentHistoryTokenStore.diagnosticsKey),
            sink: spy,
            process: .app
        )
        let store = TaskStore(persistence: persistence)
        let a = try await store.create(title: "a")
        let b = try await store.create(title: "b")
        try await store.reorder(id: b, after: nil, before: a)   // moves b above a → position write
        await observer.processPendingHistory()
        let events = await spy.events
        XCTAssertTrue(
            events.contains { $0.name == "LillistTask.update" && $0.payload["changedProps"]?.containsName("position") == true },
            "observer must surface the position update derived from persistent history"
        )
        // Every data event carries an author attribution (here the app's own author).
        let updates = events.filter { $0.name == "LillistTask.update" }
        XCTAssertTrue(updates.allSatisfy { $0.payload["author"] == .string(PersistenceController.localTransactionAuthor) })
    }

    func test_observer_emits_inserts_for_creates_and_advances_watermark() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let spy = SpyDiagnosticSink()
        let tokens = PersistentHistoryTokenStore(suiteName: "t.\(UUID().uuidString)", key: PersistentHistoryTokenStore.diagnosticsKey)
        let observer = DiagnosticHistoryObserver(persistence: persistence, tokenStore: tokens, sink: spy, process: .app)
        let store = TaskStore(persistence: persistence)
        _ = try await store.create(title: "a")
        _ = try await store.create(title: "b")
        await observer.processPendingHistory()
        let firstInserts = await spy.events.filter { $0.name == "LillistTask.insert" }.count
        XCTAssertGreaterThanOrEqual(firstInserts, 2)
        let countAfterFirstPass = await spy.events.count
        // Second pass with no new writes must emit nothing (watermark advanced).
        await observer.processPendingHistory()
        let countAfterSecondPass = await spy.events.count
        XCTAssertEqual(countAfterSecondPass, countAfterFirstPass, "watermark must prevent re-emitting consumed history")
        XCTAssertGreaterThan(countAfterFirstPass, 0)
    }

    func test_event_seq_is_monotonic_across_emitted_events() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let spy = SpyDiagnosticSink()
        let observer = DiagnosticHistoryObserver(
            persistence: persistence,
            tokenStore: PersistentHistoryTokenStore(suiteName: "t.\(UUID().uuidString)", key: PersistentHistoryTokenStore.diagnosticsKey),
            sink: spy, process: .app
        )
        let store = TaskStore(persistence: persistence)
        _ = try await store.create(title: "a")
        _ = try await store.create(title: "b")
        await observer.processPendingHistory()
        let seqs = await spy.events.map(\.seq)
        XCTAssertEqual(seqs, seqs.sorted(), "per-process seq must be monotonically increasing")
        XCTAssertEqual(Set(seqs).count, seqs.count, "seq values must be unique")
    }
}
