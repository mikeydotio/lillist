# Hypothesis Report

## 5 Whys Analysis

### Chain (Primary)

1. **Symptom:** `currentStatus` reads stale state — `inProgress=true, error=nil` (state after applying only event 1) when the test expects `inProgress=false, error=err` (state after applying event 2). Reproduces 8/30 (27%) under stress.

2. **Why does the read return event-1 state when event 2 was recorded before the read?** Because the consumer task's `await self?.apply(event2)` hasn't yet completed on the `SyncStatusMonitor` actor at the moment the test's `await monitor.currentStatus` reads the property. Verified by stress reproduction (`EVIDENCE.md` §8): the failure signature is consistent with "second event in flight, not yet applied."

3. **Why isn't the apply completed before the read?** Because there is **no happens-before relationship** between `await bridge.recordEvent(event2)` returning and the consumer's `apply(event2)` finishing. The chain has three asynchronous hops:
   - Bridge actor receives recordEvent → yields the event into the AsyncStream.
   - Consumer task (in `for await event in stream`) wakes from suspension when the buffer has the event.
   - Consumer enqueues `await self?.apply(event2)` on the SyncStatusMonitor actor.
   
   The test's `await monitor.currentStatus` also enqueues on that actor. **Swift actors are not strictly FIFO across competing tasks** — the test's hop can be processed before the consumer's hop, even when enqueued later. Verified at `EVIDENCE.md` §2 (lines 122-211).

4. **Why does the test rely on this fragile ordering?** Because the test uses `for _ in 0..<5 { await Task.yield() }` as a synchronization primitive. `Task.yield()` is documented as a cooperative-scheduling *hint* — it allows other tasks to run, but does not guarantee a specific task does run, does not enforce happens-before, and does not coordinate across actor boundaries. Five yields just raise the probability the consumer runs first; they do not guarantee it. Under load (parallel suite execution, contended cooperative pool), the probability drops enough that the race becomes observable. Verified at `EVIDENCE.md` §3 (lines 261-280) and §7-8 (lines 481-590).

5. **Why was yield-polling chosen as the sync primitive in the first place?** Because the Sync subsystem's publication API gives test authors no deterministic way to wait for "event applied to monitor state":
   - `CloudKitEventBridge.recordEvent` returns when the bridge has yielded to its subscriber buffers, NOT when downstream consumers have processed.
   - `SyncStatusMonitor.currentStatus` is a synchronous read of mutable state.
   - Only `SyncStatusMonitor.statusStream` (the iterator-based API, lines 35-54) offers a true happens-before: `iterator.next()` blocks until `apply()` has both updated `currentStatus` and yielded the new state to subscribers (lines 70-73). One test (`statusStream`, line 62-73) uses this primitive correctly and is immune to the flake.

6. **Why doesn't the Sync subsystem expose a "wait until applied" affordance for tests, given that the iterator-based one exists?** Two contributing structural choices:
   - **A. Fire-and-forget continuation registration.** Both `bridge.eventStream` (line 52-62) and `monitor.statusStream` (line 35-45) wrap their `register(...)` call in `Task { ... }`. The getter returns before the registration runs. Because the bridge has no pre-subscription buffer, events arriving before the registration Task completes are **silently dropped** (`recordEvent` iterates an empty dictionary; verified `EVIDENCE.md` §1). This forces tests to yield-poll just to "wait until subscription is set up."
   - **B. Default test pattern habituated to yield-polling.** Once the first test used `for _ in 0..<5 { Task.yield() }` to work around the Task-wrapped registration race, subsequent tests copied the pattern. 11 of 14 yield-polling sites in `Sync/` tests follow this template (`EVIDENCE.md` §6).

### Chain (Alternative — Race A only)

For the observed failure mode (`inProgress=true, error=nil`), the consumer must have successfully processed event 1 — therefore the bridge continuation was registered by the time event 1 was recorded. So Race A (pre-subscription drop) is NOT the dominant explanation for THIS test. However, the same pattern would cause Race A to manifest in `setupStarted` (a one-event test): if the registration Task hasn't run before `recordEvent`, the only event would be dropped, and the test would see `idle` instead of `inProgress=true`. That specific failure mode has not been observed but is structurally possible.

---

## Fishbone Analysis

| Category | Potential Causes |
|----------|-----------------|
| **Code** | Race B: actor reentrancy with non-FIFO ordering between consumer's apply and test's read. Race A: silent event drop when continuation registration Task hasn't run. |
| **Architecture** | No buffering in `CloudKitEventBridge` for pre-subscription events. Two-actor pipeline (bridge → monitor) with no end-to-end sync primitive exposed to callers. Fire-and-forget `Task { register }` defers a same-actor synchronous call. |
| **Dependencies** | Swift cooperative scheduler's lack of FIFO actor guarantees is by design, but the code patterns implicitly assume it. |
| **Environment** | Race amplified by parallel test execution (`Package.swift:28-31`, no `.serialized` trait) and cooperative pool contention. |
| **Process** | Yield-polling pattern propagated across 11 test sites. Compiler warnings ("no async operations") were silenced (4 fix commits) without addressing the underlying ordering hazard. |
| **Data** | N/A — failure is purely temporal. |

---

## Hypotheses (Ranked by Evidence)

### H1: Compound — yield-polling masks a missing happens-before in the Sync pipeline. — Confidence: HIGH

- **Statement:** The flake is the surface of two distinct but related defects: (A) `Task { self.register(...) }` defers continuation registration past the AsyncStream getter's return, and the bridge has no buffering, so pre-subscription events are silently dropped; (B) the consumer's `await self?.apply(event)` competes with the test's `await monitor.currentStatus` on the same actor executor without FIFO guarantees, so the test can read pre-apply state. Tests cope with both by `Task.yield()` polling, which is not a happens-before primitive. The observed failure mode is Race B specifically; Race A is a latent hazard that would manifest in single-event tests if the registration Task is slow.
- **5 Whys chain:** Primary, above.
- **Evidence for:**
  - `EVIDENCE.md` §1: bridge has no pre-subscription buffer — line 54 confirms `for continuation in continuations.values` on an empty dict drops the event.
  - `EVIDENCE.md` §2: traces both race windows. Failure-mode analysis at §2.3 (line 185-211) confirms the observed pattern matches Race B for `exportFails` and `importCompletes`.
  - `EVIDENCE.md` §8: race reproduces 8/30 = 27% under stress; failure mode always "second event missed", consistent with Race B.
  - `EVIDENCE.md` §3: the `statusStream` test uses `iterator.next()` and is immune.
  - `INVESTIGATOR.md`: the `Task { }` wrapper has been present since first commit (7507a03), never justified by commit message or comment beyond "house style."
- **Evidence against:** None found. Each leg of the explanation is concretely tied to specific code lines and a reproduction.
- **Falsification test:** If H1 is true:
  - Removing `Task { }` from both getters AND switching tests to iterator-based sync should eliminate the flake (run the stress reproduction post-fix).
  - The fix should NOT require any additional yields.
  - Production code that calls `attach(to:)` followed quickly by `monitor.start()` should not lose initial events (less directly testable but structurally implied).
- **Prevents recurrence?** YES. (1) Synchronous registration removes the pre-subscription drop window. (2) Switching to iterator.next() in tests gives a real happens-before across the pipeline, immune to scheduler decisions. (3) Documenting the pattern (or making yield-polling impossible by deleting the redundant yield-polling code) prevents the anti-pattern from propagating.

### H2: Single-cause — only Race B (apply-vs-read ordering) matters. — Confidence: MEDIUM

- **Statement:** The flake is caused exclusively by the actor-reentrancy race between consumer apply and test read. Race A is theoretical; the `Task { register }` wrapper has never actually caused a drop in any test we can reproduce, so it's not part of the root cause.
- **Evidence for:**
  - Observed failure mode is consistent with Race B only; the first event is always applied successfully in the failing test, so subscription must have completed before event 1.
  - Removing yield-polling and switching to iterator.next() alone would fix the observed flake.
- **Evidence against:**
  - `setupStarted` (single-event test) has no second event to provide cover for a Race A drop. If Race A fires there, the test sees `idle` state. That failure hasn't been observed in 30 runs, but the structural hazard remains for production startup (where CKContainer events can arrive within microseconds of `attach(to:)`).
  - The `Task { register }` pattern is unnecessary even ignoring the race — the registration call is same-actor synchronous and doesn't need to be deferred. Keeping it leaves a hazard with no upside.
- **Falsification test:** If H2 is correct, fixing only the test pattern (not the producer code) should eliminate ALL observable flakes for arbitrary stress repetitions.
- **Prevents recurrence?** Partially. Fixes the observed flake but leaves Race A as a latent hazard.

### H3: Environmental — parallel test execution is the proximate cause. — Confidence: LOW

- **Statement:** The race is masked entirely by serializing the SyncStatusMonitor test suite (`@Suite(.serialized)`). With serialization, the cooperative pool isn't contended, yields complete the consumer's work in time, and the race never manifests.
- **Evidence for:**
  - Isolated runs of the failing test pass 20/20 (`EVIDENCE.md` §7) — the race only triggers under load.
- **Evidence against:**
  - Serialization is symptom masking, not a fix. The race still exists in production where the same code runs without test-level serialization.
  - Production CloudKit events arrive at unpredictable times relative to `attach(to:)` and `monitor.start()`. The latent hazard remains.
  - `EVIDENCE.md` §5 explicitly addresses this — the compiler can't flag the `Task { register }` because the body is type-correct; the bug is temporal, not structural-typesafety.
- **Falsification test:** Adding `.serialized` would mask the flake but reproduction with manual stress (3 parallel `swift test` invocations) would still surface a related production race when CloudKit events arrive faster than registration. Hard to test directly.
- **Prevents recurrence?** NO. Masks the test failure without removing the hazard.

---

## Recommended Investigation Priority

1. Verify **H1** by spawning the hypothesis-challenger with the full evidence to look for falsifiers. If it survives, proceed to remediation that addresses BOTH races (A and B) plus the test pattern.
2. Specific question for the challenger: is there any reason the `Task { }` wrapper around `self.register(...)` is needed — does dropping it break Swift 6 strict concurrency, or break the AsyncStream contract, or otherwise have a non-obvious cost?
