import Foundation
@testable import LillistCore

/// Seeds large in-memory fixtures for the performance suites.
///
/// All seeding happens against a single `PersistenceController(.inMemory)`
/// so no disk I/O is in the measured path. Seeding is *not* part of any
/// budget — only the fetch/evaluate calls the tests time are.
enum PerfFixture {
    /// A seeded fixture plus the handles the perf tests need to measure.
    struct Seeded {
        let persistence: PersistenceController
        let taskStore: TaskStore
        let smartFilterStore: SmartFilterStore
        /// A saved filter matching every `.todo` task (≈ the full set).
        let todoFilterID: UUID
        /// Number of root tasks seeded (== `count`).
        let rootCount: Int
        /// A tag whose tasks form a measured tag-list fetch.
        let tagID: UUID
    }

    /// Seed `count` root tasks. A deterministic subset (every 10th) is
    /// tagged with a single shared tag, and one task is given five children
    /// so the hierarchy/children fetch has a non-trivial parent to measure.
    /// All tasks are `.todo` so the seeded "todo" smart filter matches the
    /// whole set — the §761 worst case.
    static func seed(count: Int) async throws -> Seeded {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let taskStore = TaskStore(persistence: persistence)
        let tagStore = TagStore(persistence: persistence)
        let smartFilterStore = SmartFilterStore(persistence: persistence)

        let tagID = try await tagStore.create(name: "perf")

        for i in 0..<count {
            let id = try await taskStore.create(title: "perf-task-\(i)")
            if i % 10 == 0 {
                try await taskStore.assignTag(taskID: id, tagID: tagID)
            }
        }

        // One parent with five children, so `children(of:)` has a real
        // sub-tree to fetch (separate from the flat root list).
        let parentID = try await taskStore.create(title: "perf-parent")
        for j in 0..<5 {
            _ = try await taskStore.create(title: "perf-child-\(j)", parent: parentID)
        }

        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .status, op: .is, value: .statusSet([.todo])))
        ])
        let todoFilterID = try await smartFilterStore.create(name: "All Todo", group: group)

        return Seeded(
            persistence: persistence,
            taskStore: taskStore,
            smartFilterStore: smartFilterStore,
            todoFilterID: todoFilterID,
            rootCount: count + 1, // + the perf-parent root
            tagID: tagID
        )
    }
}

import XCTest

/// Cheap correctness guard for the perf scaffolding — runs in the normal
/// suite (small N), so a broken fixture fails fast instead of inside a
/// minutes-long perf run.
final class PerfFixtureSmokeTests: XCTestCase {
    func testSeedProducesExpectedCounts() async throws {
        let seeded = try await PerfFixture.seed(count: 50)
        let roots = try await seeded.taskStore.children(of: nil)
        XCTAssertEqual(roots.count, seeded.rootCount, "every seeded root should be a non-deleted root child")

        let todoResults = try await seeded.smartFilterStore.evaluate(id: seeded.todoFilterID)
        // 50 flat roots + 1 parent + 5 children = 56 todo tasks.
        XCTAssertEqual(todoResults.count, 56)

        let tagged = try await seeded.taskStore.tasks(forTag: seeded.tagID)
        // Every 10th of the first 50 (indices 0,10,20,30,40) == 5 tasks.
        XCTAssertEqual(tagged.count, 5)
    }

    func testBudgetHelperFailsLoudWhenOverBudget() {
        // The gate must actually be able to fail. Run a deliberately-over-budget
        // block inside an asserted-failure expectation so the helper's teeth
        // are tested without making the suite red.
        XCTExpectFailure("intentional over-budget block proves the gate bites") {
            XCTAssertWithinBudget(0.0, name: "always-over") {
                var s = 0
                for i in 0..<10_000 { s &+= i }
                _ = s
            }
        }
    }
}
