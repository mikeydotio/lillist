# Performance Budgets and Paging Implementation Plan

> **📍 STATUS — ⬜ PENDING — Wave 6.**
>
> Part of the **Foundation Hardening** program. **Single source of truth for progress, wave order, and cross-plan coordination:** [`2026-05-29-foundation-hardening-index.md`](2026-05-29-foundation-hardening-index.md). New to this project? Read the index first, then the review ([`docs/reviews/2026-05-28-foundation-review.md`](../../reviews/2026-05-28-foundation-review.md)) for *why* this work exists, then `CLAUDE.md` for conventions + build/test commands. Execute task-by-task with `superpowers:subagent-driven-development`.
>
> ⚠️ **Wave 1 (`store-swap-safety`) is merged to `main`.** It changed several shared files (`MigrationCoordinator`, `PersistenceHost`, `QuarantineManager`, `MigrationJournal`, both `AppEnvironment`s, `PersistenceController`). **Re-Read every file before editing and anchor by code structure — the line numbers in this plan may have drifted.**

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish an executing, assertion-gated performance-test home that proves the design-doc §761 smart-filter budget (< 100ms against 10,000 tasks), and bound the currently-unbounded main task-list fetches with `fetchBatchSize` plus an explicit paging API so the UI no longer faults+DTO-projects the whole store on every reload.

**Architecture:** A new `Tests/LillistCoreTests/Performance/` XCTest suite (the first `XCTestCase`-based files in LillistCore — kept physically and conventionally isolated from the Swift Testing suites) seeds 1k/10k in-memory fixtures via a shared `PerfFixture` builder, then asserts a hard wall-clock budget with an explicit timed assertion (because `swift test` has no stored `measure()` baseline to fail against) while also emitting `measure(metrics: [XCTClockMetric()])` for human-visible trend data. On the production side, every batch-fetch list query in `TaskStore`/`TaskStore+Queries`/`SmartFilterStore` gains a `fetchBatchSize` so Core Data faults rows in pages, and `children(of:)` / `evaluate(group:)` gain optional `limit`/`offset` paging overloads (additive, defaulted, so all 100+ existing call sites compile unchanged). The budget contract and the paging policy are documented in `engineering-notes.md`.

**Tech Stack:** Swift 6.2, Core Data (`NSPersistentContainer` in-memory store), XCTest performance metrics (`measure`/`XCTClockMetric`/`XCTMeasureOptions`), Swift Testing (existing suites, left untouched).

**Source findings:** `critic: design §761 unmet perf budget + unbounded TaskStore fetch` (Blind spot #2 — design §761 assertion-tested "< 100ms against 10,000 tasks" budget never written; `TaskStore.children(of:)` and the `SmartFilterStore.evaluate`/`tasks(forTag:)` list fetches have no `fetchBatchSize`/`fetchLimit`/paging and fault+project every row on the main-queue `viewContext` per reload).

---

## File Structure

### Create

| Path | Responsibility |
|------|----------------|
| `Packages/LillistCore/Tests/LillistCoreTests/Performance/PerfFixture.swift` | One reusable in-memory fixture builder: seeds N flat root tasks (+ a known sub-tree and a tagged subset) into a `PersistenceController(.inMemory)` synchronously enough to drive the perf suites; exposes the seeded `SmartFilter` id and the parent id whose children form a measured list. No assertions — pure setup. |
| `Packages/LillistCore/Tests/LillistCoreTests/Performance/SmartFilterPerformanceTests.swift` | The §761 budget: `XCTestCase` asserting `SmartFilterStore.evaluate(id:)` against a 10,000-task fixture completes under the documented 100ms wall-clock budget, plus a `measure()` trend block and a 1,000-task sanity rung. |
| `Packages/LillistCore/Tests/LillistCoreTests/Performance/TaskListFetchPerformanceTests.swift` | Bench + budget for the main list fetches: `TaskStore.children(of:)`, the paged `children(of:limit:offset:)`, and `TaskStore.tasks(forTag:)` against 1k/10k fixtures; asserts the paged fetch is materially cheaper than the unbounded fetch. |
| `Packages/LillistCore/Tests/LillistCoreTests/Performance/PerfBudget.swift` | Single source of truth for the numeric budgets + a `XCTAssertWithinBudget` helper that times a synchronous block and hard-asserts against a budget (the gate `swift test` actually enforces, independent of `measure()` baselines). |

### Modify

| Path | Lines (current) | Change |
|------|-----------------|--------|
| `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift` | `children(of:)` at 203-218; `nextPosition` fetch at 534-545 | Add `fetchBatchSize` to the `children` fetch; add a `children(of:limit:offset:)` paged overload that delegates to the existing one's body. |
| `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore+Queries.swift` | `tasks(forTag:)` fetch at 49-54; `pinned()` fetch at 13-19 | Add `fetchBatchSize` to both list fetches. |
| `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift` | `evaluate(id:)` 267-280; `evaluate(group:)` 291-311 | Add `fetchBatchSize`; add `limit`/`offset` paging params to `evaluate(group:)` (mapping to `fetchLimit`/`fetchOffset`). |
| `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift` | doc comment 4-16 | Tighten the existing "suitable for `NSFetchedResultsController`" note to point at the new paging policy doc; no behavior change. |
| `docs/engineering-notes.md` | append-only, after the last entry | New dated entry documenting the §761 budget contract, the `swift test`-has-no-baseline gotcha, and the `fetchBatchSize`/paging policy. |

> **Cross-plan note:** `TaskStore.swift` is also edited by `breadcrumb-truthfulness` [P1], `fractional-ordering-compaction` [P1], and `background-context-seam` [P2]. This plan touches only the `children(of:)` fetch (lines ~203-218) and adds a new `children(of:limit:offset:)` method + a `fetchBatchSize` constant — it does **not** touch the mutator `defer`/breadcrumb sites, the `reorder` body, or `purgeAll`. `SmartFilterStore.swift` is also edited by `fractional-ordering-compaction` (its `reorder`, not its `evaluate` extension). Land additively; if a conflict arises, the additive `fetchBatchSize` line and the new overload rebase cleanly onto either.

---

### Task 1: Establish the perf-test home and budget contract

**Files:**
- Create `Packages/LillistCore/Tests/LillistCoreTests/Performance/PerfBudget.swift`
- Create `Packages/LillistCore/Tests/LillistCoreTests/Performance/PerfFixture.swift`

This task creates the shared scaffolding (budget constants + timed-assertion helper + fixture builder) and proves it compiles and the fixture seeds the expected row counts. No production code changes yet.

- [ ] **Step 1: Write the budget + helper file.** This is non-TDD scaffolding (a helper + constants), verified by a compile + a smoke test in Step 3. Create `Packages/LillistCore/Tests/LillistCoreTests/Performance/PerfBudget.swift` with the COMPLETE contents:

```swift
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
```

- [ ] **Step 2: Write the fixture builder.** Create `Packages/LillistCore/Tests/LillistCoreTests/Performance/PerfFixture.swift` with the COMPLETE contents:

```swift
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
```

- [ ] **Step 3: Write a smoke test proving the fixture seeds the right counts.** Append the following `XCTestCase` to the BOTTOM of `Packages/LillistCore/Tests/LillistCoreTests/Performance/PerfFixture.swift` (co-located so the scaffolding self-verifies without a measured budget):

```swift
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
```

- [ ] **Step 4: Run the smoke test, expect pass.** Command:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter PerfFixtureSmokeTests
```

Expected: `Test Suite 'PerfFixtureSmokeTests' passed` with `Executed 2 tests, with 0 failures` (the `testBudgetHelperFailsLoud...` failure is absorbed by `XCTExpectFailure`).

- [ ] **Step 5: Commit.**

```bash
cd /Volumes/Code/mikeyward/Lillist && \
git add Packages/LillistCore/Tests/LillistCoreTests/Performance/PerfBudget.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Performance/PerfFixture.swift && \
git commit -m "test(perf): establish perf-test home with budget gate and fixture builder

Adds the first XCTest-based files in LillistCore, isolated under
Tests/LillistCoreTests/Performance/. PerfBudget defines the numeric
budgets + an XCTAssertWithinBudget helper that hard-asserts a median
wall-clock cost (the gate swift test actually enforces, since there is
no stored measure() baseline). PerfFixture seeds large in-memory
fixtures; a smoke test verifies seed counts and that the budget gate
can fail. No production code changed yet."
```

---

### Task 2: Assert the design §761 smart-filter budget (< 100ms / 10,000 tasks)

**Files:**
- Create `Packages/LillistCore/Tests/LillistCoreTests/Performance/SmartFilterPerformanceTests.swift`

This is the headline finding: §761 promises an assertion-tested budget; none exists. We write a failing-until-proven budget assertion, then confirm it passes against the real (already-fast) evaluator so the contract is locked in as a regression gate.

- [ ] **Step 1: Write the budget test.** Create `Packages/LillistCore/Tests/LillistCoreTests/Performance/SmartFilterPerformanceTests.swift` with the COMPLETE contents:

```swift
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
```

- [ ] **Step 2: Run the budget test, expect pass against the real evaluator.** Command:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter SmartFilterPerformanceTests
```

Expected: `Test Suite 'SmartFilterPerformanceTests' passed`, `Executed 3 tests, with 0 failures`. The console prints the measured median (e.g. `SmartFilter.evaluate(id:) over 10k tasks: median 12.3ms exceeded budget 100.0ms` is the FAILURE wording; on pass there is no message). If this *fails* on first run, the finding is real and the production fix is `fetchBatchSize` in Task 4 — re-run after Task 4. (Expectation: it passes today; the value is the locked-in regression gate.)

- [ ] **Step 3: No implementation change needed — the test gates existing code.** This is a pure regression-gate test against already-fast production code. There is no Red→Green production edit for this task; the §761 contract is the deliverable. (If Step 2 surprised us by failing, Task 4's batching is the remedy and this step becomes "re-run after Task 4 to confirm green.") Confirm by re-reading the test's intent: it locks the budget, so any future regression in `NSPredicateCompiler`/`evaluate` turns this red.

- [ ] **Step 4: Run the full LillistCore suite to confirm no collateral breakage.** Command:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter Perf
```

Expected: both perf suites pass — `SmartFilterPerformanceTests` (3 tests) and `PerfFixtureSmokeTests` from Task 1 (2 tests); `with 0 failures`. The filter `Perf` is a substring of all these suite names. (`--filter PerformanceTests` would miss `PerfFixtureSmokeTests` because that class name does not contain the substring "PerformanceTests".)

- [ ] **Step 5: Commit.**

```bash
cd /Volumes/Code/mikeyward/Lillist && \
git add Packages/LillistCore/Tests/LillistCoreTests/Performance/SmartFilterPerformanceTests.swift && \
git commit -m "test(perf): assert design §761 smart-filter budget (<100ms / 10k tasks)

Closes the long-standing gap that §761 promised an assertion-tested
'<100ms against 10,000 tasks' smart-filter budget but none existed.
Adds an executing budget gate (median wall-clock hard assertion), an
XCTClockMetric trend companion, and a 1k sanity rung. Gates the
existing evaluator as a regression tripwire."
```

---

### Task 3: Bench the main TaskStore list fetches against 1k/10k fixtures

**Files:**
- Create `Packages/LillistCore/Tests/LillistCoreTests/Performance/TaskListFetchPerformanceTests.swift`

The review's second half: `TaskStore.children(of:)` is the unbounded main-queue funnel. We add a benchmark + budget for it (and `tasks(forTag:)`) BEFORE adding batching, so the batching change in Task 4 is measured against a real baseline.

- [ ] **Step 1: Write the fetch benchmark suite.** Create `Packages/LillistCore/Tests/LillistCoreTests/Performance/TaskListFetchPerformanceTests.swift` with the COMPLETE contents:

```swift
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
```

- [ ] **Step 2: Run the suite, expect a compile failure (the paged overload doesn't exist yet).** Command:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter TaskListFetchPerformanceTests
```

Expected: a COMPILE error, not a test failure — `error: incorrect argument labels in call (have 'of:limit:offset:', expected 'of:')` (or `extra arguments at positions #2, #3 in call`) pointing at `store.children(of: nil, limit: 100, offset: 0)`. This is the Red: the paging API in Task 4 must exist before this compiles.

- [ ] **Step 3: Implement is deferred to Task 4.** The production change that makes this compile and pass (`children(of:limit:offset:)` + `fetchBatchSize`) is Task 4. Do NOT add a stub here — proceed to Task 4, then return to Step 4. (This keeps the production change in one reviewable commit rather than scattering a throwaway stub.)

- [ ] **Step 4: After Task 4 lands, run the suite, expect pass.** Command:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter TaskListFetchPerformanceTests
```

Expected: `Test Suite 'TaskListFetchPerformanceTests' passed`, `Executed 5 tests, with 0 failures`.

- [ ] **Step 5: Commit (after Task 4 is implemented and this is green).**

```bash
cd /Volumes/Code/mikeyward/Lillist && \
git add Packages/LillistCore/Tests/LillistCoreTests/Performance/TaskListFetchPerformanceTests.swift && \
git commit -m "test(perf): bench main TaskStore list fetches (children, tag) at 1k/10k

Benchmarks the previously-unbounded children(of:) / tasks(forTag:)
fetches the UI runs every reload, adds budget gates, and proves the
new paged children(of:limit:offset:) window is strictly cheaper than
the unbounded fetch. Pairs with the fetchBatchSize/paging production
change."
```

---

### Task 4: Add `fetchBatchSize` and a paged `children` overload to TaskStore

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift` (`children(of:)` at lines 203-218; add new overload + a private batch-size constant)

The production fix for the unbounded main-queue funnel: faulting in pages via `fetchBatchSize`, plus an additive paged API so callers that only need a window don't project the whole store. The existing `children(of:)` keeps its signature so all 100+ call sites compile unchanged.

- [ ] **Step 1: The failing test already exists** — `TaskListFetchPerformanceTests.testPagedChildrenFetchReturnsRequestedWindow` and `...IsCheaperThanUnbounded` from Task 3 fail to compile because `children(of:limit:offset:)` does not exist. (Confirmed in Task 3 Step 2.) That is the Red for this task.

- [ ] **Step 2: Confirm the Red.** Command:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "testPagedChildrenFetchReturnsRequestedWindow" 2>&1 | tail -20
```

Expected: a compile error referencing `children(of:limit:offset:)` / extra arguments — the suite does not build.

- [ ] **Step 3: Implement `fetchBatchSize` + the paged overload.** Replace the existing `children(of:)` method (currently lines 203-218) in `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift` with the COMPLETE replacement below. It (a) adds a module-private default batch size, (b) routes the existing API through a shared `childrenFetchRequest` builder that sets `fetchBatchSize`, and (c) adds the additive `children(of:limit:offset:)` overload:

```swift
    public func children(of parentID: UUID?) async throws -> [TaskRecord] {
        try await context.perform { [self] in
            let req = try childrenFetchRequest(parentID: parentID, in: context)
            return try context.fetch(req).map(record(from:))
        }
    }

    /// Paged variant of `children(of:)`. Returns at most `limit` rows
    /// starting at `offset`, in the same `position`/`createdAt` order.
    ///
    /// The UI uses this so a reload faults and DTO-projects only the
    /// visible window instead of the whole sibling set (see the
    /// `fetchBatchSize` policy in `docs/engineering-notes.md`). `offset`
    /// beyond the end yields an empty array; `limit <= 0` is treated as
    /// "no limit" (parity with `NSFetchRequest.fetchLimit == 0`).
    public func children(of parentID: UUID?, limit: Int, offset: Int) async throws -> [TaskRecord] {
        try await context.perform { [self] in
            let req = try childrenFetchRequest(parentID: parentID, in: context)
            req.fetchLimit = max(0, limit)
            req.fetchOffset = max(0, offset)
            return try context.fetch(req).map(record(from:))
        }
    }

    /// Shared builder for the `children` fetch. `fetchBatchSize` makes Core
    /// Data return faults in pages of `Self.listFetchBatchSize` and only
    /// realize each page as it's touched — so even the unbounded overload no
    /// longer fully materializes a huge sibling set up front. Must be called
    /// inside `context.perform`.
    private func childrenFetchRequest(parentID: UUID?, in ctx: NSManagedObjectContext) throws -> NSFetchRequest<LillistTask> {
        let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
        if let parentID {
            let parent = try fetchManagedObject(id: parentID, in: ctx)
            req.predicate = NSPredicate(format: "parent == %@ AND deletedAt == nil", parent)
        } else {
            req.predicate = NSPredicate(format: "parent == nil AND deletedAt == nil")
        }
        req.sortDescriptors = [
            NSSortDescriptor(key: "position", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true)
        ]
        req.fetchBatchSize = Self.listFetchBatchSize
        return req
    }
```

Then add the batch-size constant. Insert it immediately after the `breadcrumbs` property declaration (currently ends at line 20, `public var breadcrumbs: BreadcrumbBuffer?`), before the `recordCrumb` helper:

```swift
    /// Page size for list fetches. Core Data returns rows as faults in
    /// pages of this size and only realizes each page when touched, so a
    /// reload over a large sibling set doesn't fault+project every row on
    /// the main-queue `viewContext` at once. See the foundation review's
    /// "unbounded TaskStore fetch" finding and `docs/engineering-notes.md`.
    static let listFetchBatchSize = 100
```

- [ ] **Step 4: Run the paged-window + full perf suites, expect pass.** Commands:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter TaskListFetchPerformanceTests && \
swift test --package-path Packages/LillistCore --filter TaskStoreHierarchyTests && \
swift test --package-path Packages/LillistCore --filter TaskStoreCRUDTests
```

Expected: all three suites pass with `0 failures`. `TaskStoreHierarchyTests`/`TaskStoreCRUDTests` confirm the refactored `children(of:)` still behaves identically (same predicate, same sort, same DTO mapping); `TaskListFetchPerformanceTests` now compiles and its 5 tests pass.

- [ ] **Step 5: Commit.**

```bash
cd /Volumes/Code/mikeyward/Lillist && \
git add Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift && \
git commit -m "perf(stores): batch + page TaskStore.children to bound the reload funnel

The main task-list fetch was unbounded: every reload faulted and
DTO-projected the whole sibling set on the main-queue viewContext.
Route children(of:) through a shared request builder that sets
fetchBatchSize (100) so Core Data faults rows in pages, and add an
additive children(of:limit:offset:) overload so the UI can fetch only
the visible window. Existing children(of:) signature is unchanged so
all call sites compile as-is. Closes the review's unbounded-fetch
finding."
```

---

### Task 5: Add `fetchBatchSize` to the remaining list fetches and paging to `evaluate(group:)`

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore+Queries.swift` (`pinned()` 13-19; `tasks(forTag:)` 49-54)
- Modify `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift` (`evaluate(id:)` 274-279; `evaluate(group:)` 300-310)

Round out the batching: the tag/pinned fetches and both `evaluate` overloads get `fetchBatchSize`, and `evaluate(group:)` (used by iOS Search) gains optional `limit`/`offset` paging.

- [ ] **Step 1: Write the failing test** for the new `evaluate(group:limit:offset:)` paging. Append this `XCTestCase` to the BOTTOM of `Packages/LillistCore/Tests/LillistCoreTests/Performance/SmartFilterPerformanceTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the new test, expect a compile failure.** Command:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter SmartFilterPagingTests 2>&1 | tail -20
```

Expected: a COMPILE error — `error: extra arguments at positions #2, #3 in call` (or `incorrect argument label`) at `store.evaluate(group: group, limit: 50, offset: 0)`, because `evaluate(group:)` has no `limit`/`offset` parameters yet.

- [ ] **Step 3: Implement the batching + paging.** Three edits:

  **(3a)** In `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift`, replace the `evaluate(group:)` method (currently lines 291-311) with the COMPLETE replacement that adds `limit`/`offset` + `fetchBatchSize`:

```swift
    public func evaluate(
        group: PredicateGroup,
        sort: SortField = .modifiedAt,
        ascending: Bool = false,
        now: Date = Date(),
        calendar: Calendar = .current,
        includeArchived: Bool = false,
        limit: Int = 0,
        offset: Int = 0
    ) async throws -> [TaskStore.TaskRecord] {
        try await context.perform { [self] in
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicateCompiler.compile(
                group,
                now: now,
                calendar: calendar,
                includeArchived: includeArchived
            )
            req.sortDescriptors = Self.sortDescriptors(field: sort, ascending: ascending)
            req.fetchBatchSize = TaskStore.listFetchBatchSize
            req.fetchLimit = max(0, limit)
            req.fetchOffset = max(0, offset)
            let tasks = try context.fetch(req)
            return tasks.map { Self.record(from: $0) }
        }
    }
```

  **(3b)** In the same file, add `fetchBatchSize` to `evaluate(id:)`. Replace its body's request setup (currently lines 274-276) — change:

```swift
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicateCompiler.compile(rec.group, now: now, calendar: calendar)
            req.sortDescriptors = Self.sortDescriptors(field: rec.sortField, ascending: rec.sortAscending)
```

  to:

```swift
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicateCompiler.compile(rec.group, now: now, calendar: calendar)
            req.sortDescriptors = Self.sortDescriptors(field: rec.sortField, ascending: rec.sortAscending)
            req.fetchBatchSize = TaskStore.listFetchBatchSize
```

  **(3c)** In `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore+Queries.swift`, add `fetchBatchSize` to the two list fetches. In `pinned()` (lines 13-18), after the `sortDescriptors` assignment add the batch-size line:

```swift
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "isPinned == YES AND deletedAt == nil")
            req.sortDescriptors = [
                NSSortDescriptor(key: "position", ascending: true),
                NSSortDescriptor(key: "createdAt", ascending: true)
            ]
            req.fetchBatchSize = TaskStore.listFetchBatchSize
```

  and in `tasks(forTag:)` (lines 49-51), after its `sortDescriptors` assignment:

```swift
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "deletedAt == nil AND ANY tags.id IN %@", Array(matchTagIDs))
            req.sortDescriptors = SmartFilterStore.sortDescriptors(field: sort, ascending: ascending)
            req.fetchBatchSize = TaskStore.listFetchBatchSize
```

- [ ] **Step 4: Run the paging test + the SmartFilter/Queries regression suites, expect pass.** Commands:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter SmartFilterPagingTests && \
swift test --package-path Packages/LillistCore --filter SmartFilterStore && \
swift test --package-path Packages/LillistCore --filter TaskStoreQueriesTests
```

Expected: all pass with `0 failures`. `--filter SmartFilterStore` matches all three existing suites (`SmartFilterStoreCRUDTests`, `SmartFilterStorePinReorderTests`, `SmartFilterStoreEvaluateTests`) which confirm the `fetchBatchSize` additions and the new defaulted params didn't change result sets; `SmartFilterPagingTests` (2 tests) passes. (`--filter SmartFilterStoreTests` would match zero suites — the Swift Testing structs use `SmartFilterStoreCRUDTests` / `SmartFilterStorePinReorderTests` / `SmartFilterStoreEvaluateTests`.)

- [ ] **Step 5: Commit.**

```bash
cd /Volumes/Code/mikeyward/Lillist && \
git add Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift \
        Packages/LillistCore/Sources/LillistCore/Stores/TaskStore+Queries.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Performance/SmartFilterPerformanceTests.swift && \
git commit -m "perf(stores): batch evaluate/pinned/tag fetches; page evaluate(group:)

Sets fetchBatchSize on evaluate(id:), evaluate(group:), pinned(), and
tasks(forTag:) so large result sets fault in pages instead of fully
materializing on the main-queue viewContext. Adds defaulted
limit/offset paging to evaluate(group:) (the iOS Search path) with a
paging contract test. All existing signatures compile unchanged."
```

---

### Task 6: Document the budget contract and paging policy in engineering-notes

**Files:**
- Modify `docs/engineering-notes.md` (append a new dated entry at the end)
- Modify `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift` (doc comment, lines 4-16)

Capture the non-obvious lessons: the §761 budget number, the `swift test`-has-no-`measure()`-baseline gotcha (so future contributors don't "fix" the explicit assertion away), and the `fetchBatchSize`/paging policy.

- [ ] **Step 1: Insert the engineering-notes entry in date order.** The file currently ends with a `## 2026-05-29 — Store-swap safety` entry. The new `## 2026-05-28` entry must be inserted **immediately before that `## 2026-05-29` heading** to preserve ascending date order — do NOT append it at the very end of the file. Read the current tail first to confirm the position, then insert the block above `## 2026-05-29`:

```markdown
## 2026-05-28 — Performance budgets are gated by explicit timed assertions, not `measure()` baselines

**Context.** Design §761 promises an assertion-tested smart-filter budget
("< 100ms against 10,000 tasks"). The perf suite lives at
`Packages/LillistCore/Tests/LillistCoreTests/Performance/` — the *only*
`XCTestCase`-based files in LillistCore (every other suite is Swift
Testing). They are deliberately segregated there.

**Gotcha 1 — `measure()` does not fail under `swift test`.** XCTest's
`measure(metrics:)` records performance numbers and, *in Xcode*, diffs them
against a stored baseline to fail on regression. Under `swift test` (SwiftPM)
there is **no baseline store**, so `measure()` runs the block and reports a
number but **never fails the build**, no matter how slow. Therefore the real
budget gate is `XCTAssertWithinBudget` in `PerfBudget.swift`: it times a
synchronous block `PerfBudget.assertionReps` times (after a warm-up), takes
the **median** (so one scheduling spike can't flake CI), and hard-asserts it
against a constant. The `measure()` blocks are kept only for human-visible
trend data in Xcode. **Do not delete the explicit `XCTAssertWithinBudget`
gates in favour of `measure()` — that silently removes the regression
tripwire.**

**Gotcha 2 — async stores, synchronous timing.** The stores are `async`;
the budget helper times a *synchronous* closure. Each timed block bridges
the actor boundary with a `DispatchSemaphore` (`Task { await … }; sem.wait()`)
so the evaluation still runs on the `viewContext` queue exactly as in
production, but the wall-clock measurement stays synchronous and
deterministic. Seeding (10k `create` calls) happens *outside* the timed
block — only the fetch/evaluate is measured.

**Policy — list fetches are batched; the UI pages.** Every list fetch in
`TaskStore`/`TaskStore+Queries`/`SmartFilterStore` sets
`fetchBatchSize = TaskStore.listFetchBatchSize` (100) so Core Data returns
rows as faults in pages and only realizes each page when touched, instead of
faulting and DTO-projecting an entire sibling/result set on the main-queue
`viewContext` per reload. For windows the UI doesn't fully scroll, prefer the
paged overloads — `TaskStore.children(of:limit:offset:)` and
`SmartFilterStore.evaluate(group:limit:offset:)` — which map to
`fetchLimit`/`fetchOffset`. The `NSPredicateCompiler` doc comment notes the
compiled predicate is also `NSFetchedResultsController`-ready; an FRC-backed
list is the natural next step if a single window proves insufficient, but
YAGNI until a real screen needs it.
```

- [ ] **Step 2: Verify the entry rendered and the file is still valid Markdown.** Command:

```bash
cd /Volumes/Code/mikeyward/Lillist && tail -40 docs/engineering-notes.md && echo "---heading count---" && grep -c "^## " docs/engineering-notes.md
```

Expected: the new `## 2026-05-28 — Performance budgets…` heading appears at the tail; the heading count incremented by exactly 1 versus before.

- [ ] **Step 3: Tighten the NSPredicateCompiler doc comment.** In `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift`, replace the second sentence of the top doc comment (currently lines 5-6):

```swift
/// Translates a `PredicateGroup` into an `NSPredicate` over the `LillistTask`
/// entity. The compiled predicate is suitable for `NSFetchRequest.predicate`
/// and `NSFetchedResultsController`.
```

  with:

```swift
/// Translates a `PredicateGroup` into an `NSPredicate` over the `LillistTask`
/// entity. The compiled predicate is suitable for `NSFetchRequest.predicate`
/// and `NSFetchedResultsController`. Callers running it for a list set
/// `fetchBatchSize`/`fetchLimit` per the paging policy in
/// `docs/engineering-notes.md` so large result sets fault in pages.
```

- [ ] **Step 4: Verify the package still builds (doc-comment change is source).** Command:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift build --package-path Packages/LillistCore 2>&1 | tail -5
```

Expected: `Build complete!` with no warnings (warnings are errors on this target).

- [ ] **Step 5: Commit.**

```bash
cd /Volumes/Code/mikeyward/Lillist && \
git add docs/engineering-notes.md Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift && \
git commit -m "docs(perf): document the §761 budget contract and fetch-paging policy

Records why the perf gate is an explicit XCTAssertWithinBudget median
assertion (swift test has no measure() baseline to fail against), the
async-store/synchronous-timing bridge, and the fetchBatchSize + paged-
overload policy. Points the NSPredicateCompiler doc comment at it."
```

---

### Task 7: Full-suite verification

**Files:** none (verification only)

- [ ] **Step 1: Run the complete LillistCore test suite.** Command:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore 2>&1 | tail -15
```

Expected: the entire suite passes — the original 649 Swift Testing tests plus the new XCTest perf suites (`PerfFixtureSmokeTests`, `SmartFilterPerformanceTests`, `SmartFilterPagingTests`, `TaskListFetchPerformanceTests`). Final line resembles `Test Suite 'All tests' passed` / `with 0 failures`. The perf suites add minutes (10k seeding × several fixtures) — that is expected.

- [ ] **Step 2: Confirm no warnings crept in (warnings-as-errors target).** Command:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift build --package-path Packages/LillistCore --build-tests 2>&1 | grep -i "warning:" || echo "no warnings"
```

Expected: `no warnings`.

- [ ] **Step 3: Confirm the LillistUI host suite is unaffected (no shared files, but the stores are linked).** Command:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistUI 2>&1 | tail -5
```

Expected: passes; this plan changed no LillistUI source and only added defaulted params / a new overload to LillistCore, so nothing downstream breaks.

- [ ] **Step 4: Review the git log for the focused-commit trail.** Command:

```bash
cd /Volumes/Code/mikeyward/Lillist && git log --oneline -7
```

Expected: the six conventional commits from Tasks 1-6 (`test(perf):` ×3, `perf(stores):` ×2, `docs(perf):` ×1) atop the prior history, each small and focused.

---

## Self-review checklist

- **Finding `critic: design §761 unmet perf budget`** — closed by **Task 2** (`SmartFilterPerformanceTests.testSmartFilterEvaluate10kUnder100ms` hard-asserts the < 100ms / 10,000-task budget via `XCTAssertWithinBudget`, with a 1k sanity rung and an `XCTClockMetric` trend companion), enabled by **Task 1**'s `PerfBudget`/`PerfFixture` scaffolding and documented in **Task 6**.
- **Finding `critic: unbounded TaskStore fetch`** — closed by **Task 4** (`fetchBatchSize` + the additive `children(of:limit:offset:)` paged overload on `TaskStore.children`) and **Task 5** (`fetchBatchSize` on `evaluate(id:)`/`evaluate(group:)`/`pinned()`/`tasks(forTag:)`, plus `limit`/`offset` paging on the iOS-Search `evaluate(group:)` path), benchmarked by **Task 3** (`TaskListFetchPerformanceTests` proves the paged window beats the unbounded fetch and stays under budget), and documented in **Task 6**.
- **Perf-test home established** — **Task 1** creates `Tests/LillistCoreTests/Performance/` with a shared budget/fixture, the first and only `XCTestCase` files in LillistCore, segregated from the Swift Testing suites; **Task 6** documents the budget contract and the `measure()`-has-no-baseline gotcha in `engineering-notes.md`.
- **Strengths preserved** — the airtight DTO boundary is untouched (every new code path still returns `TaskRecord` via the existing `record(from:)`); no `NSManagedObject` escapes; the existing `children(of:)` / `evaluate` signatures are unchanged (all 100+ call sites compile as-is); the synchronous AsyncStream registration pattern is not touched; date math is untouched. No `.xcdatamodel` edit, so the `CompileCoreDataModel` mtime-touch ritual is not required for this plan.
- **DRY/YAGNI** — one `PerfFixture` builder feeds all suites; one `PerfBudget`/`XCTAssertWithinBudget` gates all budgets; one `childrenFetchRequest` builder backs both `children` overloads; paging is added only to the two entry points the UI actually needs (`children`, `evaluate(group:)`), not speculatively everywhere; no FRC adopted (deferred until a real screen needs it, per the doc comment).
