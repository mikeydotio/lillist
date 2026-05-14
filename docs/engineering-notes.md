# Engineering Notes

Append-only log of cross-cutting engineering lessons learned while building
Lillist. Each entry captures a non-obvious gotcha — usually one that took real
investigation to find — so future work doesn't re-learn it the hard way.

Scope:
- **Belongs here:** framework shape, concurrency invariants, build-system
  surprises, type-system gotchas — anything where the "right answer" isn't
  obvious from reading docs or skimming related code.
- **Doesn't belong here:** specific bug fixes (the commit explains those),
  domain decisions (the design doc owns those), or per-feature mechanics
  (the implementation plan covers them).

Entries are dated and ordered newest-first. Each entry is short — a paragraph
of context, a paragraph of rule, and a pointer to evidence (commit, RCA
artifact, test).

---

## 2026-05-14 — `Task { same-actor-method() }` is almost always wrong; `Task.yield()` is not a barrier

**Context.** While running Plan 4 implementation, the test
`SyncStatusMonitorTests."Failed export records the error and clears
inProgress"` flaked once. Root-cause investigation (`.rca/sync-status-monitor-event-drop/`)
revealed two distinct ordering hazards in
`Packages/LillistCore/Sources/LillistCore/Sync/`:

1. **Deferred registration via Task wrapper.** `CloudKitEventBridge.eventStream`,
   `SyncStatusMonitor.statusStream`, and `AccountStateMonitor.stateStream`
   each wrapped their `self.register(id:continuation:)` call in
   `Task { ... }`. The getter returned before the registration ran, so any
   `recordEvent` that arrived in that window iterated an empty `continuations`
   dictionary and silently dropped the event. AsyncStream's `.unbounded`
   buffer was fine — the bug was upstream: `continuation.yield(...)` was
   never called, so nothing landed in the buffer.

2. **Yield-polling as a synchronization primitive.** Tests used
   `for _ in 0..<5 { await Task.yield() }` between `recordEvent` and the
   subsequent `currentStatus` read, expecting that to "let the consumer
   catch up." Empirically: 26 reorders / 1000 trials of two `await
   monitor.X()` calls on the same actor. Under cooperative-pool contention
   (parallel test execution), the test's read can win the race against the
   consumer's `apply()` and return pre-apply state.

**Rule.**

- **Same-actor synchronous calls do not need `Task { }` wrappers.** Inside
  an actor-isolated context (including the builder closure of
  `AsyncStream { continuation in ... }` when the enclosing computed property
  is on an actor), call same-actor methods directly. Swift 6 strict
  concurrency permits it; the compiler will not warn or error. Wrapping the
  call in `Task { }` defers it to a later executor tick for no benefit, and
  creates an ordering hazard between the actor-isolated function returning
  and the deferred call running.
- **`Task.yield()` is a cooperative-scheduling hint, not a synchronization
  primitive.** It raises the probability that other tasks run before
  resumption; it does not establish happens-before with any specific task.
  Adding more yields raises probability but never reaches certainty.
- **When the compiler emits "no async operations" inside `Task { method() }`,
  the surrounding scaffolding is usually unnecessary — drop the `Task`, not
  just the `await`.** The four "drop redundant await on same-actor X
  registration" commits in `Sync/` (`e2a3a5f`, `f310020`, `7049a3f`,
  `3b5f59f`) silenced the warning by removing the `await` but kept the
  `Task` — which left the race intact. The warning was pointing at the
  whole scaffold, not the keyword inside.
- **For async-event pipelines, the canonical observation primitive is the
  stream's iterator, not a synchronous snapshot read.** Tests that need to
  observe downstream effects should use `var iterator = await source.stream.makeAsyncIterator(); _ = await iterator.next()` as the wait
  point. `iterator.next()` only returns when a value has been yielded —
  that yield is downstream of the work it depends on, so it's a real
  happens-before barrier. Synchronous reads (`actor.currentStatus`,
  `actor.currentState`) are for snapshot/debug use, after the observer has
  synchronized via the stream.

**Evidence.**
- RCA artifacts: `.rca/sync-status-monitor-event-drop/` (SYMPTOM, EVIDENCE,
  HYPOTHESES, CHALLENGER, VERIFICATION, REMEDIATION).
- Runnable verification: `.rca/sync-status-monitor-event-drop/scratch/exp1-9.swift`
  (AsyncStream pre-iterator buffering, Swift 6 isolation inference, actor
  non-FIFO, iterator pattern as barrier, etc.).
- Fix commit: `2db9a69` (fix(sync): register AsyncStream continuations
  synchronously…).
- Production blast radius improvement: the fix also closed a small leak
  window in `CloudKitEventBridge.attach(to:)` where `detach()` could race
  ahead of a deferred `setObserverToken` write.

**Generalize when.** Any new use of `AsyncStream { ... }` inside an actor,
any test that observes downstream effects across actor boundaries, any
`Task { }` you're about to write inside an already-actor-isolated function.
