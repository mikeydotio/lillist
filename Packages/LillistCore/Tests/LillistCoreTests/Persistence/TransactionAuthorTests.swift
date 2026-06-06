import XCTest
import CoreData
@testable import LillistCore

final class TransactionAuthorTests: XCTestCase {
    private func lastHistoryAuthor(_ persistence: PersistenceController) async throws -> String? {
        let ctx = persistence.makeBackgroundContext()
        return try await ctx.perform {
            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: nil as NSPersistentHistoryToken?)
            let result = try ctx.execute(request) as? NSPersistentHistoryResult
            let txns = result?.result as? [NSPersistentHistoryTransaction]
            return txns?.last?.author
        }
    }

    func test_custom_author_is_stamped_on_history_transactions() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory, transactionAuthor: "Lillist.shareExtension")
        let store = TaskStore(persistence: persistence)
        _ = try await store.create(title: "x")
        let author = try await lastHistoryAuthor(persistence)
        XCTAssertEqual(author, "Lillist.shareExtension")
    }

    func test_default_author_remains_localTransactionAuthor() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let store = TaskStore(persistence: persistence)
        _ = try await store.create(title: "x")
        let author = try await lastHistoryAuthor(persistence)
        XCTAssertEqual(author, PersistenceController.localTransactionAuthor)
        XCTAssertEqual(PersistenceController.localTransactionAuthor, "Lillist.app")
    }

    func test_per_process_author_constants_are_distinct() {
        let authors: Set<String> = [
            PersistenceController.localTransactionAuthor,
            PersistenceController.shareExtensionTransactionAuthor,
            PersistenceController.appIntentsTransactionAuthor,
            PersistenceController.macAppTransactionAuthor,
            PersistenceController.cliTransactionAuthor,
        ]
        XCTAssertEqual(authors.count, 5, "every process must carry a distinct author for attribution")
    }
}
