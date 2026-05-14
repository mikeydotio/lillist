# Symptom Report

## Observed Behavior

`SyncStatusMonitorTests."Failed export records the error and clears inProgress"` (file: `Packages/LillistCore/Tests/LillistCoreTests/Sync/SyncStatusMonitorTests.swift:46-60`) intermittently fails with:

```
SyncStatusMonitorTests.swift:58:9: Expectation failed: (status.inProgress → true) == false
SyncStatusMonitorTests.swift:59:9: Expectation failed: (status.error → nil) == (err → .syncFailure(underlying: "network down"))
```

The status snapshot read at end of test reports `inProgress=true, error=nil`, which is exactly the state the monitor would be in after applying ONLY the first event (`started=true`) and not yet the second (`started=false, error=err`).

## Expected Behavior

After applying both events in order, `currentStatus` should be `inProgress=false, error=err`. Both events were recorded via `await bridge.recordEvent(...)` before the assertion, separated by `Task.yield()` polling loops intended to let the consumer task drain the events.

## Classification

**Intermittent** — flaky concurrency test. Failed once during a recent full-suite run, then re-passed on rerun without changes. Pre-existing relative to Plan 4 (the work that surfaced the flake was unrelated to Sync/).

## Timeline

- First noticed: 2026-05-13, mid-afternoon, during Plan 4 implementation full-suite run.
- Suspected trigger: not Plan 4 — the failing file lives in `Sync/`, untouched by Plan 4. Likely pre-existing.
- Frequency: at least one observed failure; many subsequent passes. Suggests load- or scheduler-dependent.

Notable recent commits on the involved files:
```
3b5f59f fix: drop redundant await on same-actor statusStream registration
7049a3f fix: drop redundant await on same-actor setObserverToken call
f310020 fix: drop redundant await on same-actor eventStream registration
e2a3a5f fix: drop redundant await on same-actor stateStream registration
7507a03 feat: add CloudKitEventBridge and SyncStatusMonitor for sync status tracking
```

The four fix commits all removed `await` from inside `Task { ... }` blocks that wrap actor-method calls in computed-property bodies (because the `Task` inherits the enclosing actor's isolation, the call is same-actor and `await` is redundant). The `Task { }` wrapper itself was kept in every case.

## Reproduction

Not reliably reproducible — flaky. Approximate steps:

1. Run the full LillistCore test suite under load: `cd Packages/LillistCore && swift test`
2. Observe the `SyncStatusMonitor` suite for the "Failed export…" test failure.
3. Rerun usually passes.

Likely accelerators: parallel test execution, slow/contended CI runner, scheduler quantum.

## Scope

Affects `Sync/` tests that use `Task.yield()` polling between `bridge.recordEvent(...)` calls. Three of the five `SyncStatusMonitorTests` use this pattern:
- `setupStarted` (one event)
- `importCompletes` (two events)
- `exportFails` (two events) — the observed failure

The fifth test, `statusStream`, uses a deterministic `iterator.next()` pattern and is not vulnerable.

Production impact: lower than test impact. Same race exists in production via `CloudKitEventBridge.attach(to:)`, where `NSPersistentCloudKitContainer` events that fire before the bridge's continuation Task completes would be dropped. In practice, real CloudKit events arrive milliseconds-to-seconds after `attach()`, while the registration Task runs in microseconds, so production has never hit this window. But the race is real and could theoretically cause a dropped sync-state event at app launch.

## Prior Investigation

User flagged it during the Plan 4 implementation summary as "pre-existing flake noted, not addressed." Hypothesis offered: `Task.yield()` polling as sync primitive. User explicitly asked for full RCA: "it seems like a possible race condition? I want to dive deeper and resolve it. … find the true race condition and fix it, not paper over with more yields."

Implementer confirmed via `git log` that the involved code is recent (Plans 1-2 timeframe, mid-May 2026) and has been touched four times to reduce `await` noise — but the underlying `Task { }` wrapper that defers the registration was never removed.

## Key Observations

1. **`Task { self.register(...) }` is fire-and-forget.** The enclosing `eventStream` (and `statusStream`) getter returns BEFORE the spawned Task runs. Any `recordEvent` that arrives before the Task is scheduled finds an empty `continuations` dictionary — and `recordEvent` simply iterates `continuations.values` and yields. Empty dictionary → event silently dropped.

2. **`Task.yield()` is not a happens-before barrier.** It gives the cooperative scheduler an opportunity to run other tasks, but does not guarantee that a specific other task runs before yield's caller resumes. Under load, `bridge.recordEvent` can race ahead of the registration Task even with 5 yields in between.

3. **Two distinct racy hops chain together:**
   - Hop A: `bridge.eventStream` getter returns; the inner `Task { self.register(...) }` is enqueued but hasn't run.
   - Hop B: Consumer task `for await event in stream` receives event; `await self?.apply(event)` enqueues an actor hop to the monitor; until that hop runs, `currentStatus` is stale. Test's `await monitor.currentStatus` may enqueue ahead of the consumer's apply.

4. **A working pattern exists in the same file.** The `statusStream` test (lines 62-73) uses `var iterator = await monitor.statusStream.makeAsyncIterator(); _ = await iterator.next()` — a deterministic await on the monitor's published-state stream. This pattern is immune to both races.

5. **The four "drop redundant await" commits indicate the author has already been wrestling with this region.** Each commit removed an `await` from inside a `Task { … }` after the compiler emitted "no async operations" warnings — confirming the same-actor isolation inference. But none of those commits dropped the `Task { }` wrapper itself, even though same-actor synchronous calls don't need to be wrapped at all.

## Relevant Code Areas

- `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift:52-62` — racy continuation registration in `eventStream` getter.
- `Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift:35-54` — same pattern in `statusStream` getter.
- `Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift` (per commit `e2a3a5f`, likely same `stateStream` shape).
- `Packages/LillistCore/Tests/LillistCoreTests/Sync/SyncStatusMonitorTests.swift:46-60` — observed failing test.
- `Packages/LillistCore/Tests/LillistCoreTests/Sync/SyncStatusMonitorTests.swift:62-73` — the working pattern (statusStream iterator).
