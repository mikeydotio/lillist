import XCTest
import Foundation
import LillistCore

/// Mirrors the LillistCore path `TaskEntityQuery.suggestedEntities()` takes:
/// the same "not-trashed, not-closed" predicate group evaluated with a
/// limit of 20. The intent itself can't be `@testable import`-ed from this
/// standalone bundle, so we exercise the shared store call directly and
/// pin the bound that Shortcuts depends on.
final class SuggestedEntitiesLimitTests: XCTestCase {
    func test_suggestions_predicate_with_limit_returns_at_most_twenty() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let taskStore = TaskStore(persistence: persistence)
        let filters = SmartFilterStore(persistence: persistence)

        for i in 0..<30 {
            _ = try await taskStore.create(title: "Open task \(i)")
        }

        let recent = PredicateGroup(
            combinator: .all,
            predicates: [
                .leaf(Leaf(field: .inTrash, op: .is, value: .bool(false))),
                .leaf(Leaf(field: .status, op: .isNot, value: .statusSet([.closed])))
            ]
        )

        let suggested = try await filters.evaluate(
            group: recent,
            sort: .modifiedAt,
            ascending: false,
            limit: 20
        )
        XCTAssertEqual(suggested.count, 20, "suggestedEntities must cap at 20 rows")
    }
}
