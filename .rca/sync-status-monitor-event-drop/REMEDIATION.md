# Remediation Plan

## Root Cause (Summary)

`Task { self.register(...) }` in three actor getters defers continuation registration past the getter's synchronous return, creating Race A (events recorded before the deferred Task completes are never yielded by `recordEvent` because the dictionary lookup misses). Meanwhile, the consumer's `await self?.apply(event)` and the test's `await monitor.currentStatus` compete on the monitor actor's executor without FIFO guarantee, creating Race B. Tests cope by polling with `Task.yield()`, which is not a happens-before barrier.

## Recommended Fix

### Approach

Three structural legs, all confined to the Sync subsystem:

1. **Synchronous registration** in `CloudKitEventBridge.eventStream`, `SyncStatusMonitor.statusStream`, and `AccountStateMonitor.stateStream` — drop the `Task { ... }` wrapper around the `self.register(...)` call. Verified type-safe under Swift 6 strict-concurrency by `scratch/exp2_isolation.swift`.

2. **Synchronous observer-token write** in `CloudKitEventBridge.attach(to:)` — drop the `Task { self.setObserverToken(token) }` wrapper. Closes a small production observer-token leak window where `detach()` could race ahead of the deferred write.

3. **Iterator-based test sync** — rewrite `SyncStatusMonitorTests` and `SyncStackSmokeTests` to use `var iterator = await monitor.statusStream.makeAsyncIterator(); _ = await iterator.next()` as the sync primitive. Pattern is already correct in the existing `statusStream` test and in `AccountStateMonitorTests`. Drop the vestigial `Task.yield()` calls from `CloudKitEventBridgeTests` (they're harmless but misleading and no longer needed once registration is synchronous).

### Anti-Pattern Check

| Check | Pass/Fail | Notes |
|-------|-----------|-------|
| Not symptom masking | PASS | Each leg removes a precondition, not a manifestation. No try/catch, no retry, no defaults. |
| Not a band-aid | PASS | The fix changes the structural API (sync register, iterator sync) rather than guarding against the symptom. |
| Not whack-a-mole | PASS | Each leg closes a distinct, verified hazard. No more legs become necessary once these three land. |
| Removes flawed assumption | PASS | Removes "Task wrapper is needed to call same-actor methods" (it isn't) and "Task.yield() is a barrier" (it isn't). |
| Strengthens invariants | PASS | After fix: "AsyncStream subscription completes before the getter returns" is an invariant; "currentStatus is consistent with the latest event observed via iterator" is an invariant. |
| Simplifies rather than adds complexity | PASS | Net code count drops. Three Task wrappers + 11 yield-polling loops removed; nothing structural added. |

### Implementation Steps

1. **`Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift`**
   - Line 57: replace `Task { self.register(id: id, continuation: continuation) }` with `self.register(id: id, continuation: continuation)`.
   - Line 84: replace `Task { self.setObserverToken(token) }` with `self.setObserverToken(token)`.
   - Update the inline comment at lines 54-56 to reflect the new shape ("Builder closure runs synchronously on the actor's executor; the same-actor `register` call is a direct synchronous call. The Task inside `onTermination` is genuinely cross-isolation and must keep its `await`.").

2. **`Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift`**
   - Line 40: replace `Task { self.registerStatus(id: id, continuation: continuation) }` with `self.registerStatus(id: id, continuation: continuation)`.
   - Update the inline comment at lines 38-39 to match.

3. **`Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift`**
   - Line 58: replace `Task { self.register(id: id, continuation: continuation) }` with `self.register(id: id, continuation: continuation)`.
   - Update the inline comment at lines 54-57 to match.

4. **`Packages/LillistCore/Tests/LillistCoreTests/Sync/SyncStatusMonitorTests.swift`**
   - `setupStarted` (test #2): drop all `Task.yield()` polling; use `statusStream.makeAsyncIterator()` to wait deterministically for the post-event state.
   - `importCompletes` (test #3): same conversion.
   - `exportFails` (test #4): same conversion — this is the observed-failing test.
   - `setupStarted` and the others should still verify `currentStatus` for backwards compatibility with the synchronous-read API, but the wait point becomes the iterator.

5. **`Packages/LillistCore/Tests/LillistCoreTests/Sync/SyncStackSmokeTests.swift`**
   - `endToEnd` test: convert from yield-polling to iterator-based wait.

6. **`Packages/LillistCore/Tests/LillistCoreTests/Sync/CloudKitEventBridgeTests.swift`**
   - Drop the now-unnecessary `await Task.yield()` lines at 12-13 and 31-32. With synchronous registration, the iterator is alive from the moment it's constructed.

7. **Add a Race-A regression test** in `CloudKitEventBridgeTests.swift`:
   - Construct a bridge.
   - Create an iterator. (Pre-fix: this kicks off the deferred registration Task. Post-fix: registration is complete.)
   - Immediately call `bridge.recordEvent(...)` without yielding.
   - Verify `iterator.next()` returns the recorded event.

### Regression Prevention

- [ ] Test: Race-A regression test (new) — proves pre-subscription drop is impossible.
- [ ] Test: stress repetition — 30 runs of the full SyncStatusMonitor suite with zero failures.
- [ ] Documentation: a one-line module-doc comment on each `eventStream`/`statusStream`/`stateStream` getter pointing future readers at iterator-based observation as the canonical primitive (currentStatus/currentState are debug/snapshot reads only).

## Impact Assessment

### Files Modified

- `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift`
- `Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift`
- `Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift`
- `Packages/LillistCore/Tests/LillistCoreTests/Sync/SyncStatusMonitorTests.swift`
- `Packages/LillistCore/Tests/LillistCoreTests/Sync/SyncStackSmokeTests.swift`
- `Packages/LillistCore/Tests/LillistCoreTests/Sync/CloudKitEventBridgeTests.swift`

### Blast Radius

Confined to `Sync/`. No callers in other parts of `LillistCore` rely on the deferred-registration timing (they either call `await bridge.eventStream` once at startup, or they subscribe via iterator and only then expect events). The public API surface is unchanged — same method signatures, same return types. Only the internal timing semantics tighten (which is universally what callers wanted in the first place).

No downstream plans (5–10) reference the deferred-registration timing — they describe `SyncStatusMonitor` and the bridge only at the public-API level.

### Risk Level: LOW

- Type-safe under Swift 6 strict-concurrency.
- No public API change.
- Production blast radius strictly improved (closes Race A latent hazard at startup, closes setObserverToken leak window).
- Tests are converted to use a primitive that's already proven correct in the same files (the `statusStream` test, `AccountStateMonitorTests.streamEmitsValues`).

## Alternative Fixes Considered

| Alternative | Why Not Chosen |
|-------------|----------------|
| Add `.serialized` to `SyncStatusMonitor` suite | Symptom masking. The race exists in production where there's no test framework to serialize. |
| Add more `Task.yield()` calls to the polling loops | Yields are not barriers; adding more doesn't change the asymptotic risk, only the constant factor. Empirically reproduced even with 5 yields per gap. |
| Add a pre-subscription buffer to `CloudKitEventBridge` | Misframes the bug. AsyncStream already has a buffer. The real fix is to call `yield` for every event (which requires synchronous registration). |
| Use `Mutex` or `Semaphore` for test synchronization | Defeats the purpose of structured concurrency. The iterator pattern is the structured-concurrency-native sync primitive. |
| Mark the actor methods `nonisolated` to bypass FIFO | Wrong direction — breaks the actor invariants without fixing the underlying race. |

## Lessons Learned

1. **`Task { same-actor-method-call }` is almost always wrong.** Same-actor calls inside an actor-isolated context should be direct. The `Task { }` wrapper defers the call to a later executor tick for no benefit, and creates an ordering hazard between the actor-isolated function returning and the deferred call running.

2. **`Task.yield()` is not a synchronization primitive.** It's a cooperative-scheduling *hint*. Tests that need to wait for downstream work must use a real happens-before primitive (an async iterator, a continuation, a result task) — not yields.

3. **When a value-type API exposes both a synchronous snapshot read and an async stream, the stream is the canonical observation primitive.** Snapshot reads are for debugging or for callers that have already synchronized via the stream. Tests should use the stream, not the snapshot.

4. **The compiler can silence the symptom (warning) without fixing the disease.** The four "drop redundant await on same-actor X registration" commits removed `await` keywords inside `Task { }` blocks because the compiler complained "no async operations." Nobody asked whether the `Task { }` itself was needed. **A "no async operations" warning is a smell — it usually means the surrounding scaffolding is unnecessary, not that the keyword was misplaced.**

5. **AsyncStream's `.unbounded` buffer is robust.** Pre-iterator yields land in the buffer correctly. The "events get dropped" bug in this codebase was upstream of the buffer (`recordEvent` never called `yield` because the continuations dict was empty), not in the buffer itself. Knowing this distinction matters for diagnosis.
