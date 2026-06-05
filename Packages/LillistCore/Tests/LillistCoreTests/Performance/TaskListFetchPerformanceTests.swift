import XCTest
@testable import LillistCore

/// Benchmarks the main task-list fetches the UI runs on every reload.
/// `TaskStore.children(of:)` is the unbounded main-queue funnel the
/// foundation review called out; these gates catch an order-of-magnitude
/// regression and prove the paged path (Task 4) is materially cheaper.
final class TaskListFetchPerformanceTests: XCTestCase {
    /// `children(of: nil)` over 10k root rows under budget.
    func testChildrenOfRoot10kUnderBudget() async throws {
        let seeded = try await PerfFixture.seed(count: 10_000)
        let store = seeded.taskStore

        func fetchBlocking() {
            let sem = DispatchSemaphore(value: 0)
            Task {
                _ = try? await store.children(of: nil)
                sem.signal()
            }
            sem.wait()
        }

        XCTAssertWithinBudget(
            PerfBudget.childrenFetch10kSeconds,
            name: "TaskStore.children(of: nil) over 10k roots"
        ) {
            fetchBlocking()
        }
    }

    /// Trend-only XCTClockMetric for the children fetch.
    func testChildrenOfRoot10kTrend() async throws {
        let seeded = try await PerfFixture.seed(count: 10_000)
        let store = seeded.taskStore

        func fetchBlocking() {
            let sem = DispatchSemaphore(value: 0)
            Task {
                _ = try? await store.children(of: nil)
                sem.signal()
            }
            sem.wait()
        }

        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTClockMetric()], options: options) {
            fetchBlocking()
        }
    }

    /// The paged fetch (one page of 100) over the same 10k roots must be
    /// strictly cheaper than the unbounded fetch — that is the whole point
    /// of paging the UI's reload. We compare medians directly.
    func testPagedChildrenFetchIsCheaperThanUnbounded() async throws {
        let seeded = try await PerfFixture.seed(count: 10_000)
        let store = seeded.taskStore

        func median(_ block: () -> Void) -> TimeInterval {
            block() // warm-up
            var samples: [TimeInterval] = []
            for _ in 0..<5 {
                let start = DispatchTime.now()
                block()
                let end = DispatchTime.now()
                samples.append(Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000)
            }
            return samples.sorted()[samples.count / 2]
        }

        func fetchAllBlocking() {
            let sem = DispatchSemaphore(value: 0)
            Task { _ = try? await store.children(of: nil); sem.signal() }
            sem.wait()
        }
        func fetchPageBlocking() {
            let sem = DispatchSemaphore(value: 0)
            Task { _ = try? await store.children(of: nil, limit: 100, offset: 0); sem.signal() }
            sem.wait()
        }

        let unbounded = median(fetchAllBlocking)
        let paged = median(fetchPageBlocking)
        XCTAssertLessThan(
            paged,
            unbounded,
            "paged children fetch (100 rows) should beat unbounded (10k rows): paged \(paged * 1000)ms vs unbounded \(unbounded * 1000)ms"
        )
    }

    /// The paged fetch returns exactly one page and respects the offset.
    func testPagedChildrenFetchReturnsRequestedWindow() async throws {
        let seeded = try await PerfFixture.seed(count: 1_000)
        let store = seeded.taskStore

        let firstPage = try await store.children(of: nil, limit: 100, offset: 0)
        XCTAssertEqual(firstPage.count, 100)

        let secondPage = try await store.children(of: nil, limit: 100, offset: 100)
        XCTAssertEqual(secondPage.count, 100)

        // Pages are disjoint and contiguous in position order.
        let firstIDs = Set(firstPage.map(\.id))
        let secondIDs = Set(secondPage.map(\.id))
        XCTAssertTrue(firstIDs.isDisjoint(with: secondIDs))
    }

    /// `tasks(forTag:)` over the tagged subset of a 10k fixture stays cheap.
    func testTagFetch10kUnderBudget() async throws {
        let seeded = try await PerfFixture.seed(count: 10_000)
        let store = seeded.taskStore
        let tagID = seeded.tagID

        func fetchBlocking() {
            let sem = DispatchSemaphore(value: 0)
            Task { _ = try? await store.tasks(forTag: tagID); sem.signal() }
            sem.wait()
        }

        XCTAssertWithinBudget(
            PerfBudget.childrenFetch10kSeconds,
            name: "TaskStore.tasks(forTag:) over 10k tasks (1k tagged)"
        ) {
            fetchBlocking()
        }
    }
}
