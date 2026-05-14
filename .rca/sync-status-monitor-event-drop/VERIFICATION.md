# Root Cause Verification

## Verified Root Cause

The Sync subsystem's publication API combines two ordering hazards that together produce the observed flake: the producer (`CloudKitEventBridge.eventStream`) and the consumer-side stream (`SyncStatusMonitor.statusStream`) defer continuation registration via `Task { self.register(...) }` despite the call being a same-actor synchronous one, and the consumer's `await self?.apply(event)` competes with the test's `await monitor.currentStatus` on the monitor actor's executor with no FIFO guarantee. Tests cope by polling with `Task.yield()`, which is a cooperative-scheduling hint, not a happens-before barrier. Under cooperative-pool contention (parallel test execution), either race window can open and a "second event never applied" symptom appears.

## Causal Chain (Verified)

1. **Symptom** — Test reads `status.inProgress=true, status.error=nil`, the state after applying only event 1.
   *Verified by:* `EVIDENCE.md` §8 — 8/30 reproductions under stress with identical signature.

2. **Cause 1: Consumer's `apply(event2)` hasn't completed before the test's `currentStatus` read.**
   *Verified by:* `EVIDENCE.md` §2 (lines 122-211); `CHALLENGER.md` §3 — actors do not enforce source-order FIFO across competing tasks (26/1000 reorders observed in `scratch/exp4_actor_fifo.swift`).

3. **Cause 2: Two awaiters compete on the `SyncStatusMonitor` actor's executor** — the consumer's `await self?.apply(event)` hop (after `for await event in stream` resumes) and the test's `await monitor.currentStatus` hop. The actor processes whichever's partial-task arrives first; arrival depends on scheduler decisions.
   *Verified by:* `CHALLENGER.md` §5.6 — the race is strictly on the monitor's executor, confirmed by isolation-inference analysis of the consumer Task created inside `start()`.

4. **Cause 3: Tests use `for _ in 0..<5 { await Task.yield() }` as the synchronization primitive.** `Task.yield()` is documented as a cooperative-scheduling hint; it raises the probability that other tasks run but does not enforce any specific ordering.
   *Verified by:* `EVIDENCE.md` §3 (lines 234-280); `CHALLENGER.md` §3 — Race B reproduces ~0.5-2% even after Race A is fixed, while iterator pattern is 0/1000 (`scratch/exp5_race_b.swift`, `scratch/exp6_iterator_sync.swift`).

5. **Root Cause (structural): The publication primitives invite the yield-polling anti-pattern.**
   - The producer (`CloudKitEventBridge`) gates `continuation.yield(event)` on dictionary lookup; if `register` hasn't run, the loop body never executes and the event is never yielded. The continuation's AsyncStream buffer is alive (default `.unbounded`), but `recordEvent` doesn't use it because it iterates an empty dict.
   - The registration call is wrapped in `Task { self.register(...) }` despite being a same-actor synchronous call. The getter returns before registration completes. There is no need for this — Swift 6 strict-concurrency accepts a direct synchronous call inside the AsyncStream builder closure when the enclosing computed property is actor-isolated (`scratch/exp2_isolation.swift`, `scratch/exp3_synchronous_register.swift`).
   - The monitor exposes `currentStatus` as a synchronous read of mutable actor state, but offers no end-to-end "wait until applied" affordance other than `statusStream` (which one test uses correctly).
   - These choices together force tests to invent yield-polling, propagating the anti-pattern across 11 test sites in 3 files.

   *Verified by:* `EVIDENCE.md` §6, `CHALLENGER.md` §4 (each remediation step closes a distinct hazard, not whack-a-mole); `INVESTIGATOR.md` (the `Task { register }` wrapper has been present since the first commit without any justification beyond "house style").

## Heuristic Checks

| Heuristic | Pass/Fail | Notes |
|-----------|-----------|-------|
| Structural fix, not defensive check | PASS | The fix removes a precondition (deferred registration) and introduces a real sync primitive (iterator.next()) — no try/catch, retry, or defaults. |
| Prevents multiple symptom manifestations | PASS | Closes Race A (latent production hazard during attach + early events) and Race B (observed test flake); same fix prevents the SAME race from appearing in `setupStarted`, `importCompletes`, and the smoke test. |
| Violates no existing invariants | PASS | Synchronous register inside the actor maintains all actor isolation. iterator.next() uses the existing published statusStream API. |
| Doesn't require careful ordering | PASS | Once the producer registers synchronously and tests use the iterator, ordering is enforced by Swift's `await` semantics, not by test-author discipline. |
| Generalizable / teaches about architecture | PASS | The lesson generalizes: "Same-actor calls do not need Task wrappers; AsyncStream subscription should complete before the getter returns; tests must use the published stream as their sync primitive, not yield-polling." Already worth folding into the Sync subsystem's design notes. |
| Fix is at origin of bad state, not encounter point | PASS | The producer-side fix is at the origin (where the continuation should be registered). The test-side fix is at the consumer's sync point. Neither is a downstream guard. |

## Challenger's Assessment

The hypothesis-challenger ran 9 empirical experiments (`scratch/exp1-9.swift`) that collectively verified:
- Type-system safety of dropping `Task { register }` under Swift 6 strict-concurrency (no errors, no warnings).
- AsyncStream's `.unbounded` buffer holds pre-iterator yields correctly — the bridge bug is NOT a buffer bug, it's a "yield never called" bug.
- Race B is genuinely real and independent of Race A: 26/1000 actor reorders, 0.5-2% test failure rate even with synchronous register.
- The iterator pattern is deterministic: 0/1000 failures in 5 trials.
- Production blast radius of dropping the Task wrappers is **strictly improved** (closes a small observer-token leak window in `attach(to:)`).

### Challenges Raised

1. *"AsyncStream has no buffer — adding buffering to the bridge is the fix."* — **Refuted.** AsyncStream buffers; the bridge bug is that `yield` is never called for pre-subscription events. Fix is "register synchronously," not "add a buffer."

2. *"Dropping `Task { register }` alone fixes the flake."* — **Refuted.** Race B persists. The test rewrite is independently load-bearing.

3. *"The Task wrapper might be needed for Swift 6 strict concurrency."* — **Refuted.** `swiftc -typecheck -swift-version 6 -strict-concurrency=complete` accepts a bare `self.register(...)` call inside the AsyncStream builder closure when the enclosing getter is actor-isolated.

4. *"Could `[weak self]`, multiple `start()` calls, or shared test state be the bug?"* — **Refuted.** Each ruled out in `CHALLENGER.md` §5.2-5.4.

### Unresolved Concerns

None that block the fix.

One follow-up: production `attach(to:)` can still lose events if a CloudKit notification fires before any consumer has subscribed to `bridge.eventStream`. This is a wiring concern (the monitor must call `start()` before the bridge calls `attach`), not a bug in the proposed fix. The current Lillist composition root presumably orders `monitor.start() ; await persistence ; bridge.attach(to:)` correctly, but this is worth verifying when integrating.

## Architectural Pattern Match

- **Leaky abstraction.** The Sync subsystem's actors expose synchronous state reads (`currentStatus`) alongside async streams, without making it clear which is the canonical observation primitive. Tests reach for the synchronous read because it's simpler; the stream is the correct primitive. Documenting this in module-level comments would prevent the next instance of the anti-pattern.
- **Deferred initialization race.** Generic pattern: "expose API X that requires Y to be initialized, then initialize Y in a fire-and-forget Task." Tests have to guess when Y is ready. Solution is universally: complete Y synchronously inside whatever sets up X.

## Confidence Level: HIGH

- Race A and Race B both empirically reproduced with runnable experiments.
- Three independent fix legs each address a distinct, verified failure mode.
- No alternative explanation (parallel test runner, weak-self, buffer bug, AsyncStream bug, isolation inference) survives challenge.
- The remediation plan is well-scoped to the affected files (no widening required) and has been verified type-safe under Swift 6 strict concurrency.

## Alternative Explanations Eliminated

| Hypothesis | Why Eliminated |
|-----------|----------------|
| H2 (only Race B matters; Race A is theoretical) | Race A reproduces in `exp1_prebuffer.swift` test D — the latent hazard is structural, not theoretical, even if it hasn't bitten the *observed* test. |
| H3 (parallel test execution is the proximate cause; serialize the suite) | Symptom masking — the race exists in production where there is no test framework to serialize. `CHALLENGER.md` §8 explicitly rejects. |
| AsyncStream buffer bug | `exp1_prebuffer.swift` tests A/B/C all show the default `.unbounded` buffer works correctly. |
| `[weak self]` allowing nil-deref | Test holds strong reference to monitor for test lifetime. |
| Multiple `start()` calls | `start()` is idempotent; tests call once. |
| Shared mutable state across tests | Each test creates its own bridge + monitor; no shared state. |

## Corrections to Apply to Earlier Artifacts

Per `CHALLENGER.md` §8 corrections-to-incorporate:

1. `EVIDENCE.md` §1 lines 60-63 — "no buffering" framing is imprecise. AsyncStream buffers; the bridge's `recordEvent` doesn't put events into the buffer when `continuations` is empty (because `yield` is never called). The fix framing is "register synchronously," not "add a buffer." This RCA's remediation plan will use the corrected framing.

2. `HYPOTHESES.md` H1 falsification test — augment with a contrived Race A reproduction (bridge records event before any subscriber exists; verify pre-fix it drops, post-fix the late subscriber sees the event via buffer). This isn't strictly necessary for closing this investigation but would prevent regression.

These corrections are now baked into the remediation plan in `REMEDIATION.md` (to be written in Phase 5).
