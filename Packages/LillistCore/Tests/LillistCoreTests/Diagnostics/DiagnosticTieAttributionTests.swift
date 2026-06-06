import XCTest
import CoreData
@testable import LillistCore

/// Regression for the "anchors out of order" reorder bug. The RCA
/// (`.rca/reorder-anchors-out-of-order/`) found that two *separate processes*
/// (e.g. the Share Extension + the app, or a CloudKit import) can mint rows at
/// an equal `position` because `nextPosition` is a non-atomic `max + 1` read.
/// The diagnostic-logging feature's job is to make that observable: the log must
/// show a position tie attributed to two *distinct* writers.
///
/// This same-container, two-author variant runs under `swift test`. Full
/// cross-*process* attribution is signed-Mac / app-hosted only.
final class DiagnosticTieAttributionTests: XCTestCase {
    func test_observer_attributes_a_position_tie_to_distinct_authors() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let container = persistence.container

        // Two contexts on one coordinator, stamped with distinct per-process
        // authors — modelling the app and the Share Extension writing concurrently.
        let ctxApp = container.newBackgroundContext()
        ctxApp.transactionAuthor = PersistenceController.localTransactionAuthor
        let ctxExt = container.newBackgroundContext()
        ctxExt.transactionAuthor = PersistenceController.shareExtensionTransactionAuthor

        let tiePosition = 5.0
        try await insertTask(in: ctxApp, title: "from app", position: tiePosition)
        try await insertTask(in: ctxExt, title: "from extension", position: tiePosition)

        let spy = SpyDiagnosticSink()
        let observer = DiagnosticHistoryObserver(
            persistence: persistence,
            tokenStore: PersistentHistoryTokenStore(suiteName: "t.\(UUID().uuidString)", key: PersistentHistoryTokenStore.diagnosticsKey),
            sink: spy,
            process: .app
        )
        await observer.processPendingHistory()

        let inserts = await spy.events.filter { $0.name == "LillistTask.insert" }
        XCTAssertEqual(inserts.count, 2)

        let positions = inserts.compactMap { event -> Double? in
            if case .double(let d)? = event.payload["position"] { return d }
            return nil
        }
        XCTAssertEqual(positions, [tiePosition, tiePosition], "both creates landed at the same position — the degenerate tie")

        let authors = Set(inserts.compactMap { event -> String? in
            if case .string(let s)? = event.payload["author"] { return s }
            return nil
        })
        XCTAssertEqual(
            authors,
            [PersistenceController.localTransactionAuthor, PersistenceController.shareExtensionTransactionAuthor],
            "the tie is attributed to two distinct writing processes — the attribution the RCA flagged as missing"
        )
    }

    private func insertTask(in ctx: NSManagedObjectContext, title: String, position: Double) async throws {
        try await ctx.perform {
            let task = LillistTask(context: ctx)
            task.id = UUID()
            task.title = title
            task.notes = ""
            task.status = .todo
            task.startHasTime = false
            task.deadlineHasTime = false
            task.isPinned = false
            task.createdAt = Date()
            task.modifiedAt = task.createdAt
            task.position = position
            try ctx.save()
        }
    }
}
