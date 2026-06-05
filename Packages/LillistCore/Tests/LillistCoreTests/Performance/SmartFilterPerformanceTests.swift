import XCTest
@testable import LillistCore

/// Design doc §761: a smart-filter evaluation over 10,000 tasks must
/// complete in under 100ms. This is the only place that contract is
/// asserted — keep it executing under `swift test`.
final class SmartFilterPerformanceTests: XCTestCase {
    /// The §761 contract. Hard-asserts the budget (the real gate) and also
    /// emits an `XCTClockMetric` trend for humans reading Xcode results.
    func testSmartFilterEvaluate10kUnder100ms() async throws {
        let seeded = try await PerfFixture.seed(count: 10_000)
        let store = seeded.smartFilterStore
        let filterID = seeded.todoFilterID

        // Pull the async evaluation across the actor boundary once per timed
        // rep using a semaphore so the timed block stays synchronous (the
        // helper measures wall-clock around a sync closure). The evaluation
        // itself runs on the viewContext's queue exactly as in production.
        func evaluateBlocking() {
            let sem = DispatchSemaphore(value: 0)
            Task {
                _ = try? await store.evaluate(id: filterID)
                sem.signal()
            }
            sem.wait()
        }

        XCTAssertWithinBudget(
            PerfBudget.smartFilter10kSeconds,
            name: "SmartFilter.evaluate(id:) over 10k tasks"
        ) {
            evaluateBlocking()
        }
    }

    /// Trend-only companion (does not fail the build under `swift test`):
    /// records the XCTClockMetric so a regression shows up in Xcode's
    /// performance results UI when run there.
    func testSmartFilterEvaluate10kTrend() async throws {
        let seeded = try await PerfFixture.seed(count: 10_000)
        let store = seeded.smartFilterStore
        let filterID = seeded.todoFilterID

        func evaluateBlocking() {
            let sem = DispatchSemaphore(value: 0)
            Task {
                _ = try? await store.evaluate(id: filterID)
                sem.signal()
            }
            sem.wait()
        }

        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTClockMetric()], options: options) {
            evaluateBlocking()
        }
    }

    /// 1,000-task sanity rung: at a tenth of the worst case the evaluation
    /// should comfortably clear a tenth of the budget. Catches a regression
    /// that scales super-linearly before it blows the 10k gate.
    func testSmartFilterEvaluate1kWellUnderBudget() async throws {
        let seeded = try await PerfFixture.seed(count: 1_000)
        let store = seeded.smartFilterStore
        let filterID = seeded.todoFilterID

        func evaluateBlocking() {
            let sem = DispatchSemaphore(value: 0)
            Task {
                _ = try? await store.evaluate(id: filterID)
                sem.signal()
            }
            sem.wait()
        }

        XCTAssertWithinBudget(
            PerfBudget.smartFilter10kSeconds / 10.0,
            name: "SmartFilter.evaluate(id:) over 1k tasks"
        ) {
            evaluateBlocking()
        }
    }
}

/// Paging contract for the ad-hoc evaluate (iOS Search uses this path).
final class SmartFilterPagingTests: XCTestCase {
    func testEvaluateGroupReturnsRequestedWindow() async throws {
        let seeded = try await PerfFixture.seed(count: 1_000)
        let store = seeded.smartFilterStore
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .status, op: .is, value: .statusSet([.todo])))
        ])

        let page = try await store.evaluate(group: group, limit: 50, offset: 0)
        XCTAssertEqual(page.count, 50)

        let next = try await store.evaluate(group: group, limit: 50, offset: 50)
        XCTAssertEqual(next.count, 50)

        XCTAssertTrue(Set(page.map(\.id)).isDisjoint(with: Set(next.map(\.id))))
    }

    func testEvaluateGroupUnpagedReturnsAll() async throws {
        let seeded = try await PerfFixture.seed(count: 100)
        let store = seeded.smartFilterStore
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .status, op: .is, value: .statusSet([.todo])))
        ])
        // 100 flat roots + 1 parent + 5 children = 106 todo tasks.
        let all = try await store.evaluate(group: group)
        XCTAssertEqual(all.count, 106)
    }
}
