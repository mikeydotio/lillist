import XCTest

/// Single source of truth for Lillist's performance budgets and the
/// assertion gate that `swift test` actually enforces.
///
/// `XCTestCase.measure(metrics:)` emits useful trend numbers, but under
/// `swift test` (SwiftPM, no Xcode baseline store) it never *fails* on a
/// regression — there is no recorded baseline to compare against. So every
/// budget in this suite is enforced by an explicit `XCTAssertWithinBudget`
/// that times a block once (warmed) and hard-asserts the wall-clock cost,
/// independent of `measure()`.
enum PerfBudget {
    /// Design doc §761: a smart-filter evaluation over 10,000 tasks must
    /// complete in under 100ms. Asserted in `SmartFilterPerformanceTests`.
    static let smartFilter10kSeconds: TimeInterval = 0.100

    /// The main task-list fetch (`children(of:)`) over 10,000 sibling rows.
    /// Not promised by the design doc, but the review flagged it as the
    /// unbounded main-queue funnel. Generous headroom — the point is to
    /// catch an order-of-magnitude regression, not to micro-tune.
    static let childrenFetch10kSeconds: TimeInterval = 0.250

    /// Number of timed repetitions averaged for an `XCTAssertWithinBudget`
    /// assertion. Keeps a single slow scheduling hiccup from flaking the gate.
    static let assertionReps = 5
}

/// Time `block` `PerfBudget.assertionReps` times (after one warm-up run that
/// is not counted) and assert the *median* wall-clock duration is under
/// `budget`. Median, not mean, so a single GC/scheduling spike can't fail an
/// otherwise-healthy run. Synchronous: callers pre-`await` any async setup and
/// pass an already-loaded closure.
func XCTAssertWithinBudget(
    _ budget: TimeInterval,
    name: String,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ block: () -> Void
) {
    block() // warm-up — fault caches, JIT, first-touch allocations.
    var samples: [TimeInterval] = []
    samples.reserveCapacity(PerfBudget.assertionReps)
    for _ in 0..<PerfBudget.assertionReps {
        let start = DispatchTime.now()
        block()
        let end = DispatchTime.now()
        samples.append(Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000)
    }
    let median = samples.sorted()[samples.count / 2]
    XCTAssertLessThan(
        median,
        budget,
        "\(name): median \(median * 1000)ms exceeded budget \(budget * 1000)ms (samples: \(samples.map { $0 * 1000 }))",
        file: file,
        line: line
    )
}
