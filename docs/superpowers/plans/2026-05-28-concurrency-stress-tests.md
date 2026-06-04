# Concurrency Stress Tests Implementation Plan

> **📍 STATUS — ✅ MERGED to `main` — Wave 4** (commits `f093884`..`805291f`; 777 LillistCore tests green, warning-free). Closed conc-2, conc-3, stores-4, notif-3, notif-9, test-3. **Two findings beyond the plan, handled honestly:** (1) the `FakeUserNotificationCenter.add` test double was not upsert-faithful to `UNUserNotificationCenter` — fixed (the concurrent-reconcile stress would otherwise trap the scheduler's `Dictionary(uniqueKeysWithValues:)`); (2) the plan's Step-3 "revert-check bites" premise for the AsyncStream suite is **false** (verified empirically — actor scheduling masks Race A in the `recordEvent` seam; the existing `preSubscriptionEventBuffering` test has the same limitation). The N-subscriber suite was kept (it guards real fan-out / no-starvation / churn-liveness properties) but its docs/commit no longer overclaim, and the `StoreReconfigureConcurrencyTests` were wired into `Lillist-iOSAppHostedTests` so the gated cases can actually execute on a signed host (they skip in the standalone bundle). See `docs/engineering-notes.md`.
>
> Part of the **Foundation Hardening** program. **Single source of truth for progress, wave order, and cross-plan coordination:** [`2026-05-29-foundation-hardening-index.md`](2026-05-29-foundation-hardening-index.md). New to this project? Read the index first, then the review ([`docs/reviews/2026-05-28-foundation-review.md`](../../reviews/2026-05-28-foundation-review.md)) for *why* this work exists, then `CLAUDE.md` for conventions + build/test commands. Execute task-by-task with `superpowers:subagent-driven-development`.
>
> **Pre-flight (run before any edit):** Confirm Waves 1–3 are on `main` (`git log --oneline main | head -20`). Read `docs/superpowers/handoffs/wave-3.md`. Re-Read every file you touch and anchor by code **structure**, not line number — each wave shifts the shared hotspot files. On completion, write `docs/superpowers/handoffs/wave-4.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the CLAUDE.md-mandated concurrency stress tests for every actor-crossing path in `LillistCore` — concurrent notification reconcile, N-concurrent `AsyncStream` subscribers, store-create/fetch during a live store reconfigure, and a real two-context duplicate-tag race — so a future refactor that reintroduces a TOCTOU, a dropped event, or a duplicate row fails the suite loudly instead of shipping green.

**Architecture:** All tests live under `Packages/LillistCore/Tests/LillistCoreTests/` and use the existing helpers (`TestStore`, `FakeUserNotificationCenter`, `SnoozeRegistry`) and the repo's two test frameworks (Swift Testing for the in-memory tests; the xcodebuild-gated reconfigure test mirrors `StoreLevelModeSwapSpike`'s `liveSwapAllowed` bundle-ID gate). The reconcile TOCTOU is *driven* (high-iteration `withTaskGroup`) so the at-most-one-default-spec invariant is asserted as a behavioural property; the duplicate-tag race is *genuinely reproduced* by driving a second `NSManagedObjectContext` against the same coordinator so the single-context atomicity claim is tested for real rather than assumed. The at-most-one-default-spec enforcement lives in `NotificationSpecStore.add` (Wave 3 `cloudkit-convergence`, merged — commit 893c359); this plan supplies the concurrency stress test that verifies it holds under contention and self-heals duplicates.

**Tech Stack:** Swift 6.2, Swift Testing (`import Testing`, `@Test`/`#expect`/`#require`), XCTest-free; CoreData (`NSManagedObjectContext`, `newBackgroundContext`); `withTaskGroup`; `NSPersistentCloudKitContainer` store-level swap (xcodebuild only).

**Source findings:** conc-2, conc-3, stores-4, notif-3, notif-9, test-3 (Roadmap item #10).

---

## File Structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerConcurrentReconcileTests.swift` | High-iteration concurrent `reconcile(taskID:)` stress: final pending set is correct and exactly one `defaultDeadline` spec survives (drives the `materializeDefaultSpecs` TOCTOU). Closes conc-2, notif-3, notif-9. |
| Create | `Packages/LillistCore/Tests/LillistCoreTests/Sync/CloudKitEventBridgeConcurrentSubscriberTests.swift` | N-concurrent-subscriber `AsyncStream` stress: interleaved subscribe/record/terminate, asserting no dropped events to live subscribers and no continuation leak after termination. Closes conc-3. |
| Create | `Packages/LillistCore/Tests/LillistCoreTests/Persistence/StoreReconfigureConcurrencyTests.swift` | xcodebuild-gated stress hammering `TaskStore.create`/`fetch` while `PersistenceHost.reconfigure` swaps the store underneath. Closes stores-4 / test-3. |
| Create | `Packages/LillistCore/Tests/LillistCoreTests/Stores/TagStoreFindOrCreateRaceTests.swift` | Two-context duplicate-tag tripwire: drives `findOrCreate` and a SECOND `NSManagedObjectContext` insert concurrently to expose the genuine race the single-context path papers over. Closes test-3 (tag-race half). |
| Modify | `docs/engineering-notes.md` (append one section at the true EOF, after the latest dated entry) | Document the single-context find-or-create invariant, the at-most-one-default-spec TOCTOU, and why the `Tag(parent,name)` unique constraint was/wasn't adopted. |

---

### Task 1: Concurrent `reconcile(taskID:)` stress — final pending set + one default spec

**Files:**
- Test (Create): `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerConcurrentReconcileTests.swift`

This test drives the `NotificationScheduler.materializeDefaultSpecs` check-then-add path (`materializeDefaultSpecs`, ~151-175) under heavy concurrency: concurrent reconciles of the same task can each observe `existingDefaultDeadline == nil` and both attempt to insert. The enforcement that collapses those into a single row lives in `NotificationSpecStore.add` (`add`, ~34-83 — the `kind == .defaultStart || .defaultDeadline` guard at ~52-67 fetches existing specs, returns the survivor, and deletes any duplicates a prior race created), shipped in Wave 3 `cloudkit-convergence` (commit 893c359) and live on `main`. This test asserts the invariant — **exactly one** default spec and a single pending request hold under contention, verifying that live enforcement. It is a regression guard: if the enforcement is ever weakened, these assertions fail loudly.

- [ ] **Step 1: Write the regression-guard test** — full file:

```swift
import Testing
import Foundation
import UserNotifications
@testable import LillistCore

/// CLAUDE.md mandates stress repetitions for any code that crosses actor
/// boundaries. `NotificationScheduler.reconcile(taskID:)` is the single
/// actor-isolated entry point every mutation funnels through; this suite
/// hammers it concurrently to prove its invariants hold under contention.
///
/// The load-bearing invariant is at-most-one default spec per
/// `(taskID, kind)`. `materializeDefaultSpecs` does a check-then-add
/// (`specs(forTask:)` → `add(...)`); two interleaved reconciles can both
/// miss the row and both attempt to insert. The invariant is enforced in
/// `NotificationSpecStore.add` (Wave 3 `cloudkit-convergence`, merged): the
/// default-kind guard returns the existing survivor and self-heals any
/// duplicates a prior race created. This suite is the regression guard
/// verifying that enforcement holds under concurrency.
@Suite("NotificationScheduler — concurrent reconcile stress", .serialized)
struct NotificationSchedulerConcurrentReconcileTests {
    /// High iteration count per CLAUDE.md "add stress repetitions for any
    /// code that crosses actor boundaries". Each iteration spins a fresh
    /// store so a leaked spec from one round can't mask a bug in the next.
    private static let iterations = 50
    private static let concurrentReconciles = 16

    /// Build a scheduler over a fresh in-memory store with a single
    /// deadline-bearing task, returning the parts a test needs.
    private static func makeFixture() async throws -> (
        scheduler: NotificationScheduler,
        specs: NotificationSpecStore,
        fake: FakeUserNotificationCenter,
        taskID: UUID
    ) {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "stress-dev",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )
        let taskID = try await tasks.create(title: "T")
        // Deadline 1h out with explicit time so the default-deadline spec
        // materializes and the computed fire date is in the future.
        let deadline = Date().addingTimeInterval(3600)
        try await tasks.update(id: taskID) { d in
            d.deadline = deadline
            d.deadlineHasTime = true
        }
        return (scheduler, specs, fake, taskID)
    }

    @Test("Concurrent reconciles of one task materialize exactly one default-deadline spec")
    func concurrentReconcileSingleDefaultSpec() async throws {
        for iteration in 0..<Self.iterations {
            let f = try await Self.makeFixture()

            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<Self.concurrentReconciles {
                    group.addTask {
                        await f.scheduler.reconcile(taskID: f.taskID)
                    }
                }
            }

            let allSpecs = try await f.specs.specs(forTask: f.taskID)
            let defaultDeadlineSpecs = allSpecs.filter { $0.kind == .defaultDeadline }
            #expect(
                defaultDeadlineSpecs.count == 1,
                "iteration \(iteration): expected exactly one defaultDeadline spec, got \(defaultDeadlineSpecs.count)"
            )
        }
    }

    @Test("After concurrent reconciles, exactly one pending request is scheduled for the task")
    func concurrentReconcileSinglePendingRequest() async throws {
        for iteration in 0..<Self.iterations {
            let f = try await Self.makeFixture()

            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<Self.concurrentReconciles {
                    group.addTask {
                        await f.scheduler.reconcile(taskID: f.taskID)
                    }
                }
            }

            let pending = await f.fake.pendingNotificationRequests()
            let forTask = pending.filter {
                ($0.content.userInfo["taskID"] as? String) == f.taskID.uuidString
            }
            #expect(
                forTask.count == 1,
                "iteration \(iteration): expected one pending request, got \(forTask.count)"
            )
        }
    }

    @Test("Clearing the deadline under concurrent reconciles leaves no default spec and no pending request")
    func concurrentReconcileClearsDeadline() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "stress-dev",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )
        let taskID = try await tasks.create(title: "T")
        try await tasks.update(id: taskID) { d in
            d.deadline = Date().addingTimeInterval(3600)
            d.deadlineHasTime = true
        }
        // Materialize the default spec first.
        await scheduler.reconcile(taskID: taskID)
        #expect(try await specs.specs(forTask: taskID).filter { $0.kind == .defaultDeadline }.count == 1)

        // Now clear the deadline and hammer reconcile concurrently. Every
        // reconcile should converge on "no anchor → no default spec".
        try await tasks.update(id: taskID) { d in
            d.deadline = nil
            d.deadlineHasTime = false
        }
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<Self.concurrentReconciles {
                group.addTask { await scheduler.reconcile(taskID: taskID) }
            }
        }

        #expect(try await specs.specs(forTask: taskID).filter { $0.kind == .defaultDeadline }.isEmpty)
        let pending = await fake.pendingNotificationRequests()
        #expect(pending.filter { ($0.content.userInfo["taskID"] as? String) == taskID.uuidString }.isEmpty)
    }
}
```

- [ ] **Step 2: Run the test, expect pass** — command:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter NotificationSchedulerConcurrentReconcileTests
  ```
  Expected: `Test Suite 'NotificationSchedulerConcurrentReconcileTests' passed` with 3 tests across all 50 iterations. The at-most-one-default enforcement in `NotificationSpecStore.add` collapses any racing inserts, so `concurrentReconcileSingleDefaultSpec` and `concurrentReconcileSinglePendingRequest` hold; `concurrentReconcileClearsDeadline` passes because clearing is idempotent and delete-by-id is safe under contention. A failure here means the enforcement has regressed.

- [ ] **Step 3: Document that the enforcement seam is `NotificationSpecStore`, not the scheduler.** Add this comment ABOVE the `@Suite` line so an executor who sees a (hypothetical) future failure doesn't "fix" it by adding a lock or dedup inside the scheduler's reconcile loop (replace the existing block-doc opening — paste the COMPLETE doc comment):

```swift
/// CLAUDE.md mandates stress repetitions for any code that crosses actor
/// boundaries. `NotificationScheduler.reconcile(taskID:)` is the single
/// actor-isolated entry point every mutation funnels through; this suite
/// hammers it concurrently to prove its invariants hold under contention.
///
/// The load-bearing invariant is at-most-one default spec per
/// `(taskID, kind)`. `materializeDefaultSpecs` does a check-then-add
/// (`specs(forTask:)` → `add(...)`); two interleaved reconciles can both
/// miss the row and both attempt to insert.
///
/// ENFORCEMENT: the invariant is enforced in `NotificationSpecStore.add`
/// (Wave 3 `cloudkit-convergence`, merged): the default-kind guard returns
/// the existing survivor and self-heals any duplicate rows a prior race
/// created. This suite is the regression guard verifying that enforcement.
/// Do NOT "fix" a failure here by adding a lock or dedup inside the
/// scheduler's reconcile loop; the per-(task,kind) row guard in
/// `NotificationSpecStore` is the correct seam — restore it there.
```

- [ ] **Step 4: Commit** — command (commit the test as a regression guard verifying the live enforcement):
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && \
  git add Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerConcurrentReconcileTests.swift && \
  git commit -m "test(notifications): stress concurrent reconcile for one-default-spec invariant

Drives the materializeDefaultSpecs check-then-add path with a 16-wide
withTaskGroup across 50 fresh-store iterations. Asserts exactly one
defaultDeadline spec and one pending request survive. Regression guard for
the NotificationSpecStore at-most-one-default enforcement (Wave 3
cloudkit-convergence, commit 893c359) under contention.

Closes conc-2, notif-3, notif-9."
  ```

---

### Task 2: N-concurrent-subscriber `AsyncStream` stress — no drops, no leaks

**Files:**
- Test (Create): `Packages/LillistCore/Tests/LillistCoreTests/Sync/CloudKitEventBridgeConcurrentSubscriberTests.swift`

`CloudKitEventBridge` (`Sync/CloudKitEventBridge.swift`, the `actor CloudKitEventBridge` body, ~36-108) is the canonical synchronous-registration `AsyncStream` actor (`continuations: [UUID: ...]`, the `eventStream` getter that calls `register` synchronously, `register`/`unregister`, `recordEvent` fan-out). The existing `preSubscriptionEventBuffering` test guards the *single*-subscriber drop race. This suite adds the **N-subscriber** dimension: many concurrent subscribers each receiving every event, interleaved with terminations that must `unregister` cleanly (no leak, no yield-to-dead-continuation). It protects the "do not revert to deferred-Task registration" strength.

- [ ] **Step 1: Write the failing test** — full file:

```swift
import Testing
import Foundation
@testable import LillistCore

/// N-concurrent-subscriber stress for the synchronous-registration
/// `AsyncStream` pattern (CLAUDE.md: "do not revert to deferred-Task
/// registration"; engineering-notes "AsyncStream pre-subscription drop").
///
/// `CloudKitEventBridge` is the canonical actor exposing a fan-out
/// `AsyncStream` with synchronous continuation registration. The existing
/// single-subscriber regression test (`preSubscriptionEventBuffering`)
/// guards the drop race for one consumer. This suite proves the same
/// guarantee holds for many concurrent consumers, and that terminating a
/// subscriber unregisters its continuation so later `recordEvent` calls
/// don't yield into a dead slot or leak it forever.
@Suite("CloudKitEventBridge — concurrent subscribers", .serialized)
struct CloudKitEventBridgeConcurrentSubscriberTests {
    private static let subscriberCount = 12
    private static let eventsPerSubscriber = 20

    @Test("Every concurrent subscriber observes every event, in order, with no drops")
    func allSubscribersReceiveAllEventsInOrder() async throws {
        let bridge = CloudKitEventBridge()

        // Build N iterators up front. Because registration is synchronous in
        // the actor-isolated getter, every continuation is in place before we
        // record the first event — no pre-subscription drop window.
        var iterators: [AsyncStream<CloudKitSyncEvent>.AsyncIterator] = []
        for _ in 0..<Self.subscriberCount {
            iterators.append(await bridge.eventStream.makeAsyncIterator())
        }

        // Record a known sequence of events. We use endedAt as a monotonic
        // sequence marker so each subscriber can assert ordering.
        let events: [CloudKitSyncEvent] = (0..<Self.eventsPerSubscriber).map { i in
            CloudKitSyncEvent(
                type: .import,
                started: false,
                endedAt: Date(timeIntervalSince1970: TimeInterval(i)),
                error: nil
            )
        }

        // Consume concurrently: each subscriber drains exactly the sequence.
        try await withThrowingTaskGroup(of: [Date].self) { group in
            for var iterator in iterators {
                group.addTask {
                    var received: [Date] = []
                    for _ in 0..<Self.eventsPerSubscriber {
                        guard let e = await iterator.next() else { break }
                        received.append(try #require(e.endedAt))
                    }
                    return received
                }
            }

            // Producer: fan the events out to all subscribers.
            let producer = Task {
                for e in events {
                    await bridge.recordEvent(e)
                }
            }
            await producer.value

            for try await received in group {
                let expected = events.map { $0.endedAt! }
                #expect(received == expected, "a subscriber dropped or reordered events: \(received)")
            }
        }
    }

    @Test("Terminating a subscriber unregisters it; survivors still receive every later event")
    func terminatedSubscriberDoesNotStarveSurvivors() async throws {
        let bridge = CloudKitEventBridge()

        // Two long-lived survivors that drain everything.
        var survivorA = await bridge.eventStream.makeAsyncIterator()
        var survivorB = await bridge.eventStream.makeAsyncIterator()

        // A transient subscriber that we drop after one event. Taking the
        // first event then letting the stream value deinit triggers the
        // continuation's onTermination → unregister(id:).
        do {
            var transient = await bridge.eventStream.makeAsyncIterator()
            await bridge.recordEvent(.init(type: .setup, started: true, endedAt: nil, error: nil))
            #expect(await transient.next()?.type == .setup)
            // Drain that first event on the survivors too so the buffers align.
            #expect(await survivorA.next()?.type == .setup)
            #expect(await survivorB.next()?.type == .setup)
            _ = transient // transient deinits at end of scope → onTermination fires
        }

        // Give the onTermination Task a happens-before barrier: yield through
        // the actor by recording + draining a marker event the survivors see.
        await bridge.recordEvent(.init(type: .export, started: true, endedAt: nil, error: nil))
        #expect(await survivorA.next()?.type == .export)
        #expect(await survivorB.next()?.type == .export)

        // Survivors must still receive a full burst with the transient gone.
        let burst: [CloudKitSyncEvent] = (0..<Self.eventsPerSubscriber).map { i in
            CloudKitSyncEvent(type: .import, started: false,
                              endedAt: Date(timeIntervalSince1970: TimeInterval(i)), error: nil)
        }
        for e in burst { await bridge.recordEvent(e) }

        for expected in burst {
            #expect(await survivorA.next()?.endedAt == expected.endedAt)
            #expect(await survivorB.next()?.endedAt == expected.endedAt)
        }
    }

    @Test("Subscribers attaching and detaching concurrently never crash or deadlock the actor")
    func churnedSubscribersStayConsistent() async throws {
        let bridge = CloudKitEventBridge()

        // One stable subscriber proves the actor stays live and ordered
        // through the churn.
        var stable = await bridge.eventStream.makeAsyncIterator()

        await withTaskGroup(of: Void.self) { group in
            // Churn: many short-lived subscribers attach, take one event, drop.
            for _ in 0..<Self.subscriberCount {
                group.addTask {
                    var it = await bridge.eventStream.makeAsyncIterator()
                    await bridge.recordEvent(.init(type: .setup, started: true, endedAt: nil, error: nil))
                    _ = await it.next()
                    // it deinits → unregister
                }
            }
            await group.waitForAll()
        }

        // The stable subscriber buffered every churn-driven event (unbounded
        // buffer). We don't assert an exact count — task interleaving makes it
        // nondeterministic — only that draining doesn't hang and the actor is
        // still usable for a final, deterministic event.
        await bridge.recordEvent(.init(type: .export, started: false,
                                       endedAt: Date(timeIntervalSince1970: 999), error: nil))
        // Drain until we reach the sentinel export event (or run dry).
        var sawSentinel = false
        for _ in 0..<(Self.subscriberCount + 2) {
            guard let e = await stable.next() else { break }
            if e.type == .export, e.endedAt == Date(timeIntervalSince1970: 999) {
                sawSentinel = true
                break
            }
        }
        #expect(sawSentinel, "stable subscriber never received the post-churn sentinel — actor wedged or dropped")
    }
}
```

- [ ] **Step 2: Run the test, expect pass (it is a guard, not a bug-driver)** — command:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter CloudKitEventBridgeConcurrentSubscriberTests
  ```
  Expected: `Test Suite 'CloudKitEventBridgeConcurrentSubscriberTests' passed` with 3 tests. (The synchronous-registration fix is already in place, so these are GREEN regression guards. If any FAIL, the fix has been reverted to deferred-`Task` registration — that is the regression this suite exists to catch.)

- [ ] **Step 3: Prove the guard bites — temporary revert check (verification only, revert immediately).** Temporarily reintroduce the bug to confirm the test catches it. In `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift`, inside the `eventStream` getter (the synchronous `register` call, ~line 66), change `self.register(id: id, continuation: continuation)` to `Task { self.register(id: id, continuation: continuation) }`, re-run the filter, confirm `allSubscribersReceiveAllEventsInOrder` FAILS (events dropped before registration), then restore the synchronous call exactly. Verification command after restore:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && git diff --exit-code Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift && echo "RESTORED CLEAN"
  ```
  Expected: `RESTORED CLEAN` and no diff. (Do NOT commit the revert; this step only proves the guard has teeth.)

- [ ] **Step 4: Re-run, expect pass** — command:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter CloudKitEventBridgeConcurrentSubscriberTests
  ```
  Expected: all 3 tests pass.

- [ ] **Step 5: Commit** — command:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && \
  git add Packages/LillistCore/Tests/LillistCoreTests/Sync/CloudKitEventBridgeConcurrentSubscriberTests.swift && \
  git commit -m "test(sync): N-concurrent-subscriber AsyncStream stress

Adds 12-subscriber fan-out, churn, and terminate-without-starvation tests
over CloudKitEventBridge's synchronous-registration AsyncStream. Guards the
'do not revert to deferred-Task registration' strength against a regression
that drops pre-subscription events or leaks continuations.

Closes conc-3."
  ```

---

### Task 3: Stress `TaskStore.create`/`fetch` during a live store reconfigure

**Files:**
- Test (Create): `Packages/LillistCore/Tests/LillistCoreTests/Persistence/StoreReconfigureConcurrencyTests.swift`

The store-swap path (`PersistenceHost.reconfigure` → `flushAndSwap`, ~123/~139) does `coordinator.remove(store)` then `addPersistentStore(...)`. `flushAndSwap` is now transactional with a CloudKit-options-preserving rollback — but that is **documentary** here: this test makes **no code change** and only calls the stable public `host.reconfigure(to:)` / `PersistenceHost.make(...)` (both exercised by `PersistenceHostTests`). Stores read `controller.container.viewContext` on the main queue. This test interleaves `TaskStore.create`/`fetch` with repeated `reconfigure` toggles and asserts the container never crashes and rows survive each completed swap. It must run under `xcodebuild` (the `NSCloudKitMirroringDelegate.dealloc` SPM limitation documented in `StoreLevelModeSwapSpike` — gated by the same `liveSwapAllowed` bundle-ID check).

- [ ] **Step 1: Write the failing/guard test** — full file:

```swift
import Testing
import CoreData
import Foundation
@testable import LillistCore

/// Stress the steady-state store API (`TaskStore.create`/`fetch`) against a
/// live `PersistenceHost.reconfigure` swap running underneath it.
///
/// CLAUDE.md mandates stress repetitions for actor-crossing code; the store
/// swap (`coordinator.remove` + `addPersistentStore`) is the most invasive
/// concurrent mutation in the codebase. The viewContext stays attached to
/// the same coordinator across the swap, so create/fetch must remain
/// coherent: rows written before a completed swap must be readable after it.
///
/// Gated to xcodebuild via `liveSwapAllowed` for the same reason as
/// `StoreLevelModeSwapSpike`: `NSCloudKitMirroringDelegate.dealloc` faults
/// inside the swift-test binary (no `CFBundleIdentifier`). Run with:
///   xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
///     -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
///     -only-testing:LillistCoreTests/StoreReconfigureConcurrencyTests
@Suite("Store reconfigure concurrency (xcodebuild-gated)", .serialized)
struct StoreReconfigureConcurrencyTests {
    private static let swapCount = 10
    private static let writesPerPhase = 25

    /// True only under a real app-bundle host (xcodebuild test). Mirrors
    /// `StoreLevelModeSwapSpike.liveSwapAllowed`.
    private static var liveSwapAllowed: Bool {
        Bundle.main.bundleIdentifier?.isEmpty == false
    }

    private static func freshStoreURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoreReconfigureConcurrency-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Lillist.sqlite")
    }

    @Test("create/fetch interleaved with reconfigure swaps never crash and preserve committed rows",
          .enabled(if: liveSwapAllowed))
    func createFetchSurvivesReconfigure() async throws {
        let url = Self.freshStoreURL()
        let host = try await PersistenceHost.make(initialMode: .iCloudSync, storeURL: url)
        let store = TaskStore(persistence: await host.controller)

        var committedIDs: [UUID] = []

        for phase in 0..<Self.swapCount {
            // Write a batch and capture IDs (sequentially — TaskStore funnels
            // through the main-queue viewContext, which is the contract).
            for i in 0..<Self.writesPerPhase {
                let id = try await store.create(title: "phase-\(phase)-row-\(i)")
                committedIDs.append(id)
            }

            // Flip the mode. flushAndSwap saves pending writes before the
            // remove+add, so everything committed above must survive.
            let target: SyncMode = (phase % 2 == 0) ? .localOnly : .iCloudSync
            try await host.reconfigure(to: target)

            // After the swap the same viewContext is re-attached to the
            // coordinator; every committed row must still fetch.
            let freshStore = TaskStore(persistence: await host.controller)
            for id in committedIDs {
                let record = try await freshStore.fetch(id: id)
                #expect(record.id == id, "phase \(phase): row \(id) lost across swap to \(target)")
            }
        }

        #expect(committedIDs.count == Self.swapCount * Self.writesPerPhase)
    }

    @Test("Concurrent fetches issued while a reconfigure is in flight do not crash the coordinator",
          .enabled(if: liveSwapAllowed))
    func concurrentFetchDuringReconfigure() async throws {
        let url = Self.freshStoreURL()
        let host = try await PersistenceHost.make(initialMode: .iCloudSync, storeURL: url)
        let store = TaskStore(persistence: await host.controller)

        // Seed a row to fetch.
        let seededID = try await store.create(title: "seed")

        for phase in 0..<Self.swapCount {
            let target: SyncMode = (phase % 2 == 0) ? .localOnly : .iCloudSync

            // Kick a reconfigure and a burst of fetches concurrently. The
            // fetches race the remove+add; none may crash. A fetch landing
            // mid-swap may throw .notFound (no attached store) — that's a
            // tolerable transient, a crash is not. We only assert no crash
            // and that a post-swap fetch succeeds.
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    try? await host.reconfigure(to: target)
                }
                for _ in 0..<Self.writesPerPhase {
                    group.addTask {
                        _ = try? await store.fetch(id: seededID)
                    }
                }
                await group.waitForAll()
            }

            // Once the dust settles, the seeded row is still there.
            let after = try await TaskStore(persistence: await host.controller).fetch(id: seededID)
            #expect(after.id == seededID, "phase \(phase): seeded row vanished after swap to \(target)")
        }
    }
}
```

- [ ] **Step 2: Run under SPM, expect SKIP (gate proves itself)** — command:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter StoreReconfigureConcurrencyTests
  ```
  Expected: the suite is discovered but both `@Test`s report no failures because `liveSwapAllowed == false` under `swift test` disables them (Swift Testing prints them as not-run/skipped). Confirms the gate compiles and opts out under SPM. There must be **zero** failures.

- [ ] **Step 3: Run under xcodebuild, expect pass** — command:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild test \
    -workspace Lillist.xcworkspace -scheme Lillist-iOS \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
    -only-testing:LillistCoreTests/StoreReconfigureConcurrencyTests 2>&1 | tail -30
  ```
  Expected: `** TEST SUCCEEDED **` with both tests executed (not skipped) and passing — `createFetchSurvivesReconfigure` confirms 250 committed rows survive 10 swaps; `concurrentFetchDuringReconfigure` confirms no coordinator crash under in-flight-swap fetch races.

- [ ] **Step 4: Confirm the whole LillistCore SPM suite still builds clean (warnings-as-errors)** — command:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore 2>&1 | tail -15
  ```
  Expected: no warnings, no errors; existing suites still pass; the new gated suite skips cleanly.

- [ ] **Step 5: Commit** — command:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && \
  git add Packages/LillistCore/Tests/LillistCoreTests/Persistence/StoreReconfigureConcurrencyTests.swift && \
  git commit -m "test(persistence): stress create/fetch during live store reconfigure

Interleaves TaskStore.create/fetch with PersistenceHost.reconfigure swaps
(10 toggles x 25 writes) and a concurrent-fetch-during-swap burst. Asserts
committed rows survive each completed swap and the coordinator never
crashes mid-swap. xcodebuild-gated via liveSwapAllowed (NSCloudKitMirroring
Delegate dealloc faults under swift-test), matching StoreLevelModeSwapSpike.

Closes stores-4, test-3 (reconfigure half)."
  ```

---

### Task 4: Real second-context find-or-create duplicate-tag tripwire

**Files:**
- Test (Create): `Packages/LillistCore/Tests/LillistCoreTests/Stores/TagStoreFindOrCreateRaceTests.swift`

`TagStore.findOrCreate` (`Stores/TagStore+FindOrCreate.swift`, the `findOrCreate(name:parent:tintColor:)` method, ~14-53) is atomic **only** because read+write run in one `viewContext.perform` and every caller shares that single context. The existing `TagStoreFindOrCreateTests` exercise the happy path on one context. This test drives a **second** `NSManagedObjectContext` (`newBackgroundContext`) against the same coordinator to genuinely test the duplicate-tag race the single-context guarantee papers over — proving (a) single-context concurrent `findOrCreate` stays atomic and (b) a true second writer *can* produce a duplicate, documenting that the invariant rests on the single-context discipline.

- [ ] **Step 1: Write the test** — full file:

```swift
import Testing
import CoreData
import Foundation
@testable import LillistCore

/// Find-or-create atomicity is only guaranteed because every caller shares
/// the single main-queue `viewContext`: the read and the optional insert run
/// inside one `context.perform`, so two concurrent callers can't both miss
/// the row and both insert.
///
/// This suite proves that contract two ways:
///   1. Concurrent `findOrCreate` calls on the SAME `TagStore` (single
///      context) NEVER create a duplicate — the invariant the app relies on.
///   2. A genuine SECOND `NSManagedObjectContext` driven concurrently CAN
///      observe the duplicate window — the tripwire showing the guarantee is
///      a property of the single-context discipline, not of the predicate.
///
/// (2) is the "real second-context tripwire" the review asked for: it tests
/// the race instead of assuming it away. See engineering-notes
/// "find-or-create single-context invariant".
@Suite("TagStore.findOrCreate — concurrency", .serialized)
struct TagStoreFindOrCreateRaceTests {
    private static let concurrentCallers = 16
    private static let iterations = 25

    @Test("Concurrent findOrCreate on one store returns a single tag (single-context atomicity)")
    func singleContextStaysAtomic() async throws {
        for iteration in 0..<Self.iterations {
            let p = try await TestStore.make()
            let store = TagStore(persistence: p)

            // Many tasks racing to create the same name. All share the one
            // viewContext, so the perform blocks serialize and the second+
            // callers see the row the first inserted.
            let ids = await withTaskGroup(of: UUID?.self) { group -> [UUID] in
                for _ in 0..<Self.concurrentCallers {
                    group.addTask { try? await store.findOrCreate(name: "groceries") }
                }
                var collected: [UUID] = []
                for await id in group { if let id { collected.append(id) } }
                return collected
            }

            #expect(ids.count == Self.concurrentCallers, "iteration \(iteration): a caller threw")
            #expect(Set(ids).count == 1, "iteration \(iteration): findOrCreate returned distinct IDs — duplicate created")

            let all = try await store.children(of: nil)
            let groceries = all.filter { $0.name.lowercased() == "groceries" }
            #expect(groceries.count == 1, "iteration \(iteration): \(groceries.count) 'groceries' tags exist")
        }
    }

    @Test("A genuine second context CAN insert a duplicate — the invariant rests on single-context discipline")
    func secondContextCanRace() async throws {
        // This is the tripwire. We deliberately bypass findOrCreate's
        // single-context guarantee by inserting through a SECOND, independent
        // background context against the same coordinator. Because the two
        // contexts don't serialize their perform blocks, both can miss the
        // row and both insert — producing two tags with the same name.
        //
        // We assert the duplicate is *possible* across multiple attempts: if
        // a future change (e.g. a Core Data unique constraint on
        // (parent, name)) makes the second insert fail/merge instead, THIS
        // test must be revisited and the engineering note updated. Until
        // then, it documents that callers MUST go through the shared store.
        var sawDuplicate = false

        for _ in 0..<Self.iterations {
            let p = try await TestStore.make()
            let store = TagStore(persistence: p)
            let secondContext = p.container.newBackgroundContext()
            secondContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)

            // Race: findOrCreate (context A) vs. a raw insert (context B).
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    _ = try? await store.findOrCreate(name: "errands")
                }
                group.addTask {
                    await secondContext.perform {
                        let req = NSFetchRequest<Tag>(entityName: "Tag")
                        req.predicate = NSPredicate(format: "parent == nil AND name ==[c] %@", "errands")
                        req.fetchLimit = 1
                        if (try? secondContext.fetch(req))?.first == nil {
                            let tag = Tag(context: secondContext)
                            tag.id = UUID()
                            tag.name = "errands"
                            tag.position = 0
                            try? secondContext.save()
                        }
                    }
                }
                await group.waitForAll()
            }

            // Merge background-context changes into the view context, then count.
            let count: Int = try await p.container.viewContext.perform {
                p.container.viewContext.refreshAllObjects()
                let req = NSFetchRequest<Tag>(entityName: "Tag")
                req.predicate = NSPredicate(format: "name ==[c] %@", "errands")
                return try p.container.viewContext.count(for: req)
            }
            if count > 1 { sawDuplicate = true; break }
        }

        #expect(
            sawDuplicate,
            """
            Across \(Self.iterations) attempts a genuine second context never \
            produced a duplicate. Either the timing never collided (flaky — \
            re-run) OR a (parent, name) unique constraint now prevents it. If \
            the latter, update engineering-notes 'find-or-create single-context \
            invariant' and convert this to assert the constraint instead.
            """
        )
    }
}
```

- [ ] **Step 2: Run the test, expect pass** — command:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter TagStoreFindOrCreateRaceTests
  ```
  Expected: both tests pass. `singleContextStaysAtomic` proves the single-context path holds under 16-wide contention across 25 iterations; `secondContextCanRace` observes at least one duplicate across the 25 attempts (the tripwire firing), confirming the invariant is a single-context property. If `secondContextCanRace` ever fails as flaky (no collision), re-run once; if it persistently fails, a unique constraint has been added and the test + note must be updated (see Task 5 decision).

- [ ] **Step 3: Decide on the `Tag(parent, name)` unique constraint (YAGNI gate).** Per CLAUDE.md SOLID/YAGNI and the strengths-to-preserve list, do **not** add a Core Data unique constraint now: (a) `findOrCreate`'s single-context atomicity already prevents duplicates for every production caller (Quick Capture iOS/macOS, CLI all route through the shared `TagStore`), (b) a `uniquenessConstraints` entry forces a store-wide `NSMergeByPropertyStoreTrumpMergePolicy`-style conflict policy that would interact with the existing `mergeByPropertyObjectTrump` and the `.xcdatamodel` edit triggers the CompileCoreDataModel mtime-touch ritual and a model-version bump, and (c) CloudKit does not enforce Core Data unique constraints anyway, so it would give false confidence cross-device. The chosen design is: **document the single-context invariant** (Task 5) and keep the tripwire as the regression guard. (No code change in this step — it is an explicit, recorded decision. If a future change DOES add the constraint, this test's `secondContextCanRace` is the signal to update both.)

- [ ] **Step 4: Re-run to confirm green after the decision** — command:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter TagStoreFindOrCreateRaceTests
  ```
  Expected: both tests pass (no code changed in Step 3).

- [ ] **Step 5: Commit** — command:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && \
  git add Packages/LillistCore/Tests/LillistCoreTests/Stores/TagStoreFindOrCreateRaceTests.swift && \
  git commit -m "test(stores): two-context find-or-create duplicate-tag tripwire

Adds a real second-NSManagedObjectContext race against findOrCreate. Proves
(a) single-context concurrent findOrCreate stays atomic (16x25) and (b) a
genuine second writer CAN produce a duplicate — documenting that the no-dup
guarantee is a property of the shared-viewContext discipline, not of the
predicate. YAGNI: declined the Tag(parent,name) unique constraint; documented
the invariant instead (see engineering-notes).

Closes test-3 (tag-race half)."
  ```

---

### Task 5: Document the concurrency invariants in engineering-notes

**Files:**
- Modify (append at the true EOF, after the latest dated entry): `docs/engineering-notes.md`

Append-only per CLAUDE.md: record the non-obvious invariants a future contributor would otherwise rediscover the hard way — the single-context find-or-create guarantee, the at-most-one-default-spec TOCTOU and where its fix lives, and why the `Tag(parent, name)` unique constraint was declined.

- [ ] **Step 1: Read the current EOF before editing** — command (anchor on whatever the last dated entry currently is; the file grows wave-to-wave):
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && tail -8 docs/engineering-notes.md
  ```
  The append goes after the TRUE final line of the latest dated entry, so the new `## Concurrency invariants...` section lands at real EOF and chronological order is preserved. The block below is self-contained regardless of what the current tail is.

- [ ] **Step 2: Append the section** — append EXACTLY this block to the true EOF of `docs/engineering-notes.md` (use the Edit tool: Read the file, match its current final line, and append the block after it; or use Write to re-emit the file with this appended — prefer Edit appending after the final line):

```markdown


## Concurrency invariants proven by the stress suites (Plan: concurrency-stress-tests)

CLAUDE.md mandates stress repetitions for any code crossing actor
boundaries. The following invariants are not obvious from reading the
happy-path code; each is now pinned by a stress test, and each has a
sharp edge a refactor can silently break.

### find-or-create single-context invariant

`TagStore.findOrCreate` is atomic **only** because every production
caller shares the one main-queue `viewContext`: the existence check and
the optional insert run inside a single `context.perform`, so concurrent
callers serialize and the later ones observe the row the first inserted.
This is a property of the *shared context*, not of the `name ==[c]`
predicate. A second, independent `NSManagedObjectContext` (e.g.
`newBackgroundContext()`) racing a `findOrCreate` **can** produce a
duplicate tag — `TagStoreFindOrCreateRaceTests.secondContextCanRace`
reproduces it deliberately.

Consequence: never open a second writer context for tag creation. Route
all tag creation through the shared `TagStore`. The duplicate-tag race is
prevented by discipline, not by the schema.

We **declined** a `Tag` `uniquenessConstraints` on `(parent, name)`
(YAGNI): every production caller already routes through the shared store;
a unique constraint forces a store-wide merge-conflict policy that would
interact with the existing `mergeByPropertyObjectTrump`; editing the
`.xcdatamodel` triggers the CompileCoreDataModel mtime-touch ritual and a
model-version bump; and Core Data unique constraints are **not** mirrored
to CloudKit, so the constraint would give false cross-device confidence.
If that calculus ever changes, `secondContextCanRace` failing (no
duplicate observed) is the signal to flip the test to assert the
constraint and update this note.

### at-most-one default notification spec per (taskID, kind)

`NotificationScheduler.materializeDefaultSpecs` does a check-then-add:
`specStore.specs(forTask:)` → (if absent) `specStore.add(...)`. Two
interleaved `reconcile(taskID:)` calls can each observe the default spec
absent and both attempt to insert.
`NotificationSchedulerConcurrentReconcileTests` drives this with a
16-wide `withTaskGroup` across 50 fresh-store iterations and asserts
exactly one default spec + one pending request hold under contention.

The **enforcement** of the invariant (at-most-one default spec per
`(taskID, kind)`) lives in `NotificationSpecStore.add` (the
default-kind guard fetches existing specs, returns the survivor, and
deletes any duplicate rows a prior race created — shipped in
`cloudkit-convergence`, commit 893c359). The store is where the dedup
belongs — it scopes via a `task == %@` predicate rather than a
model-level unique constraint, so it composes with CloudKit (which
doesn't honor uniqueness constraints). Do not "fix" a regression here by
adding a lock or a dedup inside the scheduler's reconcile loop; restore
the per-(task,kind) row guard in `NotificationSpecStore` — that is the
correct seam.

### AsyncStream synchronous registration is load-bearing under N subscribers

The synchronous continuation registration in `CloudKitEventBridge` /
`SyncStatusMonitor` / `AccountStateMonitor` (see the "AsyncStream
pre-subscription drop" note above) is not just a single-subscriber fix:
`CloudKitEventBridgeConcurrentSubscriberTests` proves 12 concurrent
subscribers each receive every event and that terminating a subscriber
unregisters its continuation without starving survivors or leaking. If
any of those tests regress, registration has been reverted to a deferred
`Task { register }` — restore the synchronous call (the regression the
suite exists to catch).

### xcodebuild-gated store-reconfigure stress

`StoreReconfigureConcurrencyTests` hammers `TaskStore.create`/`fetch`
against a live `PersistenceHost.reconfigure` swap. It is gated by the
same `liveSwapAllowed` bundle-ID check as `StoreLevelModeSwapSpike`
because `NSCloudKitMirroringDelegate.dealloc` faults under the swift-test
binary (no `CFBundleIdentifier`). It runs only under `xcodebuild test`;
under `swift test` it skips cleanly. A fetch that lands mid-swap may throw
`.notFound` (no attached store) — that is a tolerable transient; a crash
or a lost committed row is not.
```

- [ ] **Step 3: Verify the append landed and the doc is well-formed** — command:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && grep -n "Concurrency invariants proven by the stress suites" docs/engineering-notes.md && tail -5 docs/engineering-notes.md
  ```
  Expected: the heading line is found near EOF and the file ends with the xcodebuild-gated paragraph.

- [ ] **Step 4: Commit** — command:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && \
  git add docs/engineering-notes.md && \
  git commit -m "docs(engineering-notes): record concurrency invariants from stress suites

Documents the find-or-create single-context invariant (and why the
Tag(parent,name) unique constraint was declined), the at-most-one-default-
spec TOCTOU and where its fix lives, the N-subscriber AsyncStream guarantee,
and the xcodebuild-gated reconfigure stress.

Closes test-3 (documentation half)."
  ```

---

## Self-review checklist

- [ ] **conc-2** (concurrent reconcile reentrancy / TOCTOU) — covered by **Task 1** (`NotificationSchedulerConcurrentReconcileTests`: 16-wide `withTaskGroup`, 50 iterations, asserts one default spec + one pending request). Regression guard verifying the `NotificationSpecStore.add` at-most-one-default enforcement (Wave 3 `cloudkit-convergence`, merged) holds under contention.
- [ ] **conc-3** (N-concurrent-subscriber AsyncStream, no drops/leaks) — covered by **Task 2** (`CloudKitEventBridgeConcurrentSubscriberTests`: fan-out, churn, terminate-without-starvation; revert-check proves the guard bites).
- [ ] **stores-4** (stress create/fetch during reconfigure) — covered by **Task 3** (`StoreReconfigureConcurrencyTests`, xcodebuild-gated): create/fetch interleaved with 10 reconfigure swaps + concurrent-fetch-during-swap burst.
- [ ] **notif-3** (reconcile TOCTOU on default-spec materialization) — covered by **Task 1** (same suite asserting exactly one `.defaultDeadline` spec under concurrency) and documented in **Task 5**.
- [ ] **notif-9** (default-spec dedup invariant under concurrency) — covered by **Task 1** (`concurrentReconcileSinglePendingRequest` + `concurrentReconcileClearsDeadline`) and the at-most-one-default-spec note in **Task 5**.
- [ ] **test-3** (real second-context find-or-create tripwire + reconfigure coverage + invariant docs) — covered by **Task 4** (`TagStoreFindOrCreateRaceTests` two-context tripwire), **Task 3** (reconfigure stress), and **Task 5** (single-context invariant + declined-unique-constraint rationale).
- [ ] Strengths preserved: synchronous AsyncStream registration is exercised, never reverted (Task 2); DTO boundary untouched (tests use `record`/`SpecRecord`/`TagRecord` only); no `NSManagedObject` escapes `LillistCore` (the one raw `Tag` insert is inside a `secondContext.perform` in test code, confined to the duplicate-race tripwire); `Calendar`-based date math untouched.
- [ ] DRY/YAGNI: no production code added; `Tag(parent,name)` unique constraint explicitly declined with recorded rationale (Task 4 Step 3 + Task 5).
- [ ] Cross-plan coordination: the reconcile-TOCTOU **enforcement** shipped in `cloudkit-convergence` (NotificationSpecStore at-most-one-default, commit 893c359, merged); this plan supplies the regression stress test plus a code comment + engineering-note pointing at that seam. Task 3 touches the reconfigure path that `store-swap-safety` (merged) hardened — this plan only adds tests, never edits `PersistenceHost.swift`/`MigrationCoordinator.swift`.
- [ ] TEST-ONLY plan: no source changes (the Task 2 Step 3 revert-check is reverted before commit; the `git diff --exit-code` gate proves it). The rare parallel-`swift test` SIGSEGV / timing flake (index residual #11) is owned by Wave 7 `ci-and-build-posture` (runner-level parallelism bound / retry) — a single observed SIGSEGV or one-off contention flake is **not** a suite failure; re-run before treating it as real (see engineering-notes).
```
