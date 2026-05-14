# Hypothesis Challenger Report

Phase 4 of the RCA for `sync-status-monitor-event-drop`. This report attempts
to disprove H1 from `HYPOTHESES.md`, challenge the proposed remediation, and
surface any alternative root causes. All claims are backed by empirical
experiments that live in
`/Volumes/Code/mikeyward/Lillist/.rca/sync-status-monitor-event-drop/scratch/`.

Toolchain used for experiments: Swift 6.2.4 (`swift --version`).

---

## TL;DR

**H1 survives challenge.** Both Race A and Race B reproduce empirically.
However, the report needs three precision corrections that affect the
remediation:

1. **AsyncStream's default `.unbounded` buffer DOES hold pre-iterator yields.**
   Evidence in `EVIDENCE.md` §1 conflates "no buffering" with "the bridge
   never calls `yield` because `continuations` is empty." The bug is the
   latter, not the former. Adding "buffering to the bridge" is not the
   right framing — the right framing is "don't defer registration past
   the synchronous return of the getter."
2. **Dropping `Task { register }` is necessary but NOT sufficient.** Race B
   (apply-vs-read reordering on the monitor actor) persists after Race A is
   fixed. Rewriting tests to use `iterator.next()` is the load-bearing fix
   for the *observed* flake; the producer fix is the load-bearing fix for
   the *latent* hazard at production startup.
3. **The Task wrapper is genuinely unnecessary under Swift 6.** Swift 6 with
   `-strict-concurrency=complete` accepts a direct `self.register(...)` call
   inside the AsyncStream builder closure when the enclosing computed
   property is actor-isolated. No warnings. No errors. Confirmed below.

Below: each challenge, with experiment files cited.

---

## 1. Type-system constraints on dropping `Task { }`

**Claim under test:** `Task { self.register(...) }` can be replaced with a
bare `self.register(...)` call inside the `AsyncStream { continuation in ... }`
builder closure, even under Swift 6 strict concurrency.

### Experiment: `scratch/exp2_isolation.swift` and `scratch/exp3_synchronous_register.swift`

Compiled with `swiftc -typecheck exp2_isolation.swift -swift-version 6
-strict-concurrency=complete` — **no errors, no warnings.**

Running `scratch/exp3_synchronous_register.swift` produces:

```
register ran SYNCHRONOUSLY in getter
recordEvent(999) saw 1 continuation(s)
recordEvent(888) saw 1 continuation(s)
first event: 999
second event: 888
done
```

Both events are delivered. No `Task.yield()` polling required.

### Why this works under Swift 6

The `AsyncStream.init(_:_:)` builder closure has signature
`(@escaping (Continuation) -> Void)` (or the `Sendable` variant on newer SDKs).
When the closure is **literal** inside an actor-isolated computed property
(like `var eventStream` on `actor CloudKitEventBridge`), Swift 6's actor
isolation inference treats the closure as actor-isolated for the purposes
of the `self.register(...)` call. Conceptually: the synchronous body of the
getter runs on the actor's executor; calling another isolated method on the
same actor synchronously is permitted (it's the same isolation domain).

The `Task { }` wrapper exists because the author over-corrected. It's worth
noting that the original code was `Task { await self.register(...) }`
(`INVESTIGATOR.md` line 33–41) — the author *thought* the call needed an
`await`, then the four "fix" commits (`f310020`, `7049a3f`, `3b5f59f`,
`e2a3a5f`) removed the `await` after the compiler complained "no async
operations." Nobody questioned whether the `Task` wrapper itself was needed.

### Conclusion

Dropping the wrapper is type-safe under Swift 6 + strict-concurrency. The
remediation step #1 is sound. No surprise compiler complaints.

---

## 2. AsyncStream buffering semantics — am I wrong about pre-subscription drops?

**Claim under test (from `EVIDENCE.md` §1):** "There is no buffering. The
producer has no way to know whether any subscriber received the event."

### Experiment: `scratch/exp1_prebuffer.swift`

Output:

```
--- Test A: yield inside builder synchronously, then iterate ---
got v1: 1
got v2: 2
got v3: 3
--- Test B: yield from a Task spawned in builder, then iterate ---
got: 10
got: 20
--- Test C: capture continuation, yield after, iterate ---
got: 100
got: 200
--- Test D: BRIDGE SHAPE — defer register via Task, recordEvent runs before register ---
  recordEvent(999) saw 0 continuation(s)
  register ran
  recordEvent(888) saw 1 continuation(s)
first event: 888
```

### What this teaches us

`AsyncStream`'s default `.unbounded` buffer **does** hold pre-iterator yields.
The continuation captures the buffer the moment the stream is constructed;
calling `continuation.yield(...)` deposits into that buffer regardless of
whether an iterator exists. Tests A, B, and C all receive every yielded
value despite the iterator being created after the yield.

The bridge's bug, then, is NOT "AsyncStream loses pre-subscription yields."
It is "`bridge.recordEvent(...)` iterates `continuations.values` which is
empty before the deferred `register` Task runs, so `continuation.yield(...)`
is never called for that event. The continuation's buffer remains pristine —
nothing was put into it." Test D in `exp1_prebuffer.swift` demonstrates this
exactly: `recordEvent(999)` sees 0 continuations and the yield is never
invoked. 999 is dropped because `yield` was never called. The lone 888 (from
the second `recordEvent`, which DID see the registered continuation) arrives
fine via the buffer.

### Correction to `EVIDENCE.md`

`EVIDENCE.md` lines 60–63 say:

> No buffering. No `pending` array. No replay queue. The event is dropped
> on the floor with no diagnostic.
> ... `AsyncStream`'s default buffer (`.unbounded`) is only meaningful AFTER
> the continuation has been handed to the stream's runtime — which here only
> happens once `register` actually runs and stores the continuation in the
> dictionary keyed by `id`.

The second sentence is **wrong**. The continuation's buffer is alive the
moment the stream is constructed (i.e., the moment `AsyncStream.init` is
called inside the getter body). The buffer is keyed off the *continuation*,
not the dictionary lookup. The reason the event is dropped is purely that
the producer (`recordEvent`) gates its `yield` call on whether the
continuation is in `continuations`. If the bridge had instead stored the
continuation directly (synchronously inside the getter), the buffer would
hold any pre-iterator yield just fine.

This precision matters for remediation framing. The fix is "register
synchronously in the getter," not "add a pre-subscription buffer to the
bridge." AsyncStream already has the buffer.

### Implication for "replay-on-subscribe"

The `SyncStatusMonitor.statusStream` and `AccountStateMonitor.stateStream`
*do* invoke `continuation.yield(currentStatus)` (or `currentState`) in their
`register*` method. With the Task wrapper, that initial replay yield lands
in the continuation's buffer (because the buffer is alive from stream
construction) and the next `iterator.next()` call drains it. Fine.

The bridge's `register` does NOT yield. That's a separate design choice
(events are transient and don't have a "current value" to replay). Whether
to add an event replay/buffer to the bridge is a *separate* discussion from
the race fix. The race fix is "synchronous register"; that alone is enough
to prevent dropped events for any consumer that subscribes before recording
the event.

---

## 3. Race B counter-arguments — does the actor really not enforce ordering?

**Claim under test:** Two `await monitor.X()` calls from different tasks
have no guaranteed ordering on the monitor actor's executor.

### Experiment: `scratch/exp4_actor_fifo.swift`

Tries 1000 trials of: `Task { await m.a() }; Task { await m.b() }; await
results`. Counts how often the actor's `log` ends up `["b", "a"]` instead
of `["a", "b"]`.

Result: **26 reorders / 1000 trials.**

### What this teaches us

Two `Task` initializations on adjacent lines of code does NOT establish a
happens-before relationship between when each Task's partial-task is
enqueued on the actor's executor. The second Task can win the enqueue race
even though it was created later. This is consistent with Swift's
documented actor semantics: the actor processes partial-tasks in
arrival-on-executor order, but "arrival on executor" depends on scheduler
decisions, not on source-order of `Task { }` initializations.

Even *within* the same enqueueing task, the `await m.X()` syntax only
guarantees that the awaiter is suspended until the actor has time to
process the call. It does not impose any ordering constraint against
*other* tasks' calls to the same actor.

### Applied to the failing test

In `SyncStatusMonitorTests.exportFails`:

- The consumer Task (created at `SyncStatusMonitor.swift:28-32`) calls
  `await self?.apply(event2)` after receiving event 2 from the stream.
- The test's main task calls `await monitor.currentStatus` at
  `SyncStatusMonitorTests.swift:57`.

Both calls suspend, then enqueue partial-tasks on the monitor actor's
executor. The actor processes them in *some* order; nothing pins
`apply(event2)` to come first.

Even worse: until the consumer Task's `for await event in stream` wakes
from suspension and invokes `await self?.apply(event2)`, the apply isn't
even enqueued. The test's read can race ahead in two ways:
1. The for-await loop hasn't woken from the stream yet (the `yield` from
   `recordEvent` is in the buffer but the loop hasn't been scheduled yet).
2. The for-await loop has woken and called `await self?.apply(event2)`,
   but that hop hasn't been enqueued ahead of the test's read.

`Task.yield()` cannot fix either. It's a cooperative-scheduling hint, not
a barrier. **Race B is genuinely real.** H1's analysis stands.

### What about the consumer Task's isolation?

A subtlety worth noting: the consumer Task at `SyncStatusMonitor.swift:28`
is created **inside an actor-isolated method** (`start()`), so under Swift
6 isolation inference it *inherits the monitor's actor isolation*. That
means the body `for await event in stream { await self?.apply(event) }`
runs on the monitor's executor. The `await self?.apply(event)` is then
effectively a same-actor call, which Swift 6 will let proceed without a
real cross-actor hop... but the `for await` suspension *does* yield the
actor's executor (waiting on the stream). When the stream produces, the
task resumes; and when resuming on the actor, it goes through the same
enqueue queue as any other awaiter.

So the consumer Task and the test's `await monitor.currentStatus` are
effectively two awaiters of the monitor actor. The actor doesn't guarantee
they're served in source-order; under load (or any scheduler decision)
the test's read can be served first, returning pre-apply state.

Experiment 5 (`scratch/exp5_race_b.swift`) reproduces this even after the
Task wrapper is removed: 0–5 fails per 200 trials with synchronous
register but still using `Task.yield()` + direct `currentStatus` read.

---

## 4. Symptom-vs-root-cause heuristic check

Applying each heuristic from
`references/symptom-vs-root-cause.md`:

### 4.1 Is "drop the Task wrapper" structural or defensive?

**Structural.** It removes the deferral hop entirely. After the change, the
`AsyncStream` returned from the getter has the continuation registered
*before* the getter returns. The producer side of the race window is closed
permanently; the change doesn't conditionally guard against a symptom, it
eliminates the precondition.

### 4.2 Is "use iterator.next() in tests" symptom-masking?

This is the most challenge-worthy of the three remediation steps. Let's
think hard.

A test that uses `iterator.next()` to drain the stream IS using a real
sync primitive: the iterator blocks until the producer yields. So the test
is no longer racing the consumer's `apply` against its own read. Instead,
the test reads through the same path the consumer uses, and the iterator
returning *implies* the apply has updated `currentStatus` (because `apply`
yields to `statusContinuations` *after* writing `currentStatus`, lines
70–73).

This is **NOT symptom masking** because:
- The test's failure mode (stale read) was caused by the missing
  happens-before between recordEvent and the apply being visible in
  currentStatus.
- The iterator pattern *provides* that happens-before.
- The test is no longer "papering over latency"; it's actually waiting
  for the work to complete.

It IS arguable that the iterator pattern only patches the *test* without
fixing the underlying API ergonomics: production callers reading
`currentStatus` after recording an event have the same race. But that's a
different concern: production callers don't typically race read against
record in the same task; they observe state changes via the statusStream
(which uses iterator semantics naturally), or via SwiftUI binding (which
gets notified by stream subscription).

The right framing is: tests were using `currentStatus` because it's a
synchronous read of mutable state, exposed *for tests*. The proper test
pattern is to subscribe to the stream the same way production observers
do. That's not masking; it's matching the API's contract.

### 4.3 Is "add buffering to the bridge" a band-aid?

Largely moot per §2 above: AsyncStream already has buffering. The bridge
just needs to register synchronously so that `yield` is actually called
for events that arrive after the getter is created.

A separate question: should the bridge replay the most recent event for
late subscribers? Probably not — events are transient ("import started,"
"export ended"), not state. Replaying a stale event would be confusing.
The monitor's status stream and the account state stream already do their
own replay because they represent state. The bridge represents events.
This is a reasonable design.

### 4.4 Is fixing all three "whack-a-mole"?

No, because each fix addresses a distinct flaw:

| Fix | What it addresses | Without this fix |
|-----|-------------------|------------------|
| Drop `Task { register }` (bridge + monitor + account) | Producer-side race window where recordEvent runs before register | Production hazard at app startup; first event may be lost |
| Drop `Task { register }` from `AccountStateMonitor.stateStream` | Same race on the state stream | Late subscribers can miss state updates between getter and register |
| Use `iterator.next()` in tests | Test-side race window where read runs ahead of apply | Flaky tests; can't validate observed behavior |

These are three concrete code locations, three concrete fixes, each one
provably necessary to remove a specific failure mode. The investigator
recommendation also includes the `setObserverToken` Task drop, which fixes
the production observer-token race (a small but real production hazard).

This is NOT whack-a-mole. Whack-a-mole would be: "this test was flaky,
add another yield"; "that test was flaky, add another yield"; etc. The
current plan addresses the structural defect (deferred registration) and
the test pattern (yield-polling as sync primitive) together.

---

## 5. Alternative root causes I might have missed

### 5.1 Could `AsyncStream`'s `.unbounded` buffer policy have a bug?

Tested in `scratch/exp1_prebuffer.swift`. The buffer correctly holds
yields across iterator creation. Test A (pure sync yields) and Test C
(yield after iterator creation) both produce all values. No buffer bug.

### 5.2 Could `[weak self]` in the consumer Task allow `self?` to be nil?

In tests, the test holds a strong reference to `monitor` for the duration
of the test (the `let monitor = ...` local). The Task captures `[weak self]`
which holds a weak reference, but as long as the local exists, `self?`
deref succeeds. No nil-eats-the-event hazard inside the test scope.

In production, after the monitor deallocates, `self?` is nil and `apply`
is skipped — but the stream is also expected to finish at that point
(observer is detached, etc.). Not the bug we're chasing.

### 5.3 Could `monitor.start()` being called multiple times cause a problem?

`start()` is idempotent (`SyncStatusMonitor.swift:26` guards on
`consumeTask == nil`). Tests call it once. Not a contributor.

### 5.4 Could the parallel test runner share state across tests?

Each test in `SyncStatusMonitorTests` constructs its own `Bridge` and
`Monitor`. No shared mutable state. Parallel execution increases cooperative
pool contention, which widens the race window — but doesn't introduce a
new race.

### 5.5 What about the `recordEvent` actor hop itself?

`bridge.recordEvent(event)` is itself an actor-isolated method call that
suspends. The test does `await bridge.recordEvent(...)`, which means the
test's task is suspended on the bridge actor until the recordEvent runs.
Inside `recordEvent`, the for-loop is synchronous on the bridge actor —
the `continuation.yield(event)` deposits into AsyncStream's internal
buffer immediately. So the moment `await bridge.recordEvent(...)` returns,
the event is in the stream's buffer. The bug is downstream: the consumer
task hasn't yet drained the buffer and applied to monitor state.

### 5.6 Alternative root cause: is the `for await` loop the slow link?

Worth considering. The consumer Task's `for await event in stream` body
runs on the monitor actor's executor (per §3 above on Swift 6 isolation
inference). Between iterations, the for-await loop suspends on the
iterator (waiting for the next stream value). When the producer yields a
value into the buffer, the iterator resumes and the loop body runs. This
resume requires the actor to schedule the consumer Task's continuation.

If the monitor actor is busy (e.g., serving the test's `await
monitor.currentStatus`), the consumer's resume waits. So actually the
race goes:

1. `await bridge.recordEvent(event2)` returns; event2 is in stream buffer.
2. The consumer Task's iterator is signaled to resume.
3. Resume requires enqueuing a partial-task on the monitor actor.
4. The test's `await monitor.currentStatus` is also enqueuing a
   partial-task on the monitor actor.
5. Whichever wins, runs first.

That's the same Race B analysis, but it's worth being explicit: the race
is *strictly* on the monitor actor's executor, not anywhere else. So
"actor reentrancy" is the right framing. H1's analysis is correct.

### 5.7 Alternative root cause: AsyncStream iterator wakeup latency?

Could there be enough latency in the stream's "wake the iterator" path
that it consistently loses to the test's read? Tested in `exp9_under_load.swift`.
Even under 32 background tasks contending the pool, the failure rate is
0–1/500 — so wakeup latency isn't the dominant factor. The race is
genuinely scheduling order, not latency.

---

## 6. Production blast radius of the proposed fix

Examining `CloudKitEventBridge.attach(to:)` at
`CloudKitEventBridge.swift:73-85`:

```swift
public func attach(to container: NSPersistentCloudKitContainer) {
    let name = NSPersistentCloudKitContainer.eventChangedNotification
    let token = NotificationCenter.default.addObserver(forName: name, ...) { [weak self] notification in
        // observer body
        Task { await self.recordEvent(translated) }   // observer's Task
    }
    Task { self.setObserverToken(token) }              // setObserverToken Task
}
```

### Effects of dropping `Task { self.setObserverToken(token) }`

Proposed shape:

```swift
public func attach(to container: NSPersistentCloudKitContainer) {
    let name = NSPersistentCloudKitContainer.eventChangedNotification
    let token = NotificationCenter.default.addObserver(forName: name, ...) { ... }
    self.setObserverToken(token)
}
```

`attach(to:)` is actor-isolated (declared `public func` on `actor
CloudKitEventBridge`). Inside, `self.setObserverToken(...)` is a same-actor
call, callable synchronously. The compiler accepts this. The observer
token is written to actor state before `attach` returns.

**Blast radius:** Improved. The current shape has a race where
`observerToken` may be `nil` for a brief window after `attach` returns. If
a caller invokes `detach` immediately, it sees `observerToken == nil` and
does NOT call `removeObserver`, leaking the observer. The fix closes that
window.

### Effects of the NotificationCenter observer firing during attach

The `addObserver(...)` call at line 75 registers the observer
**synchronously**. The observer can fire as soon as `addObserver` returns,
even before `attach` continues. With `queue: nil` (line 75), the observer
runs synchronously on the posting thread.

Scenario:

1. Line 75 returns; observer is live.
2. CloudKit fires `eventChangedNotification` immediately.
3. Observer closure runs synchronously: `[weak self] notification in
   Task { await self.recordEvent(translated) }`. Note: this is NOT an
   actor-isolated context — the observer closure is `@Sendable` and not
   inside `attach`'s actor isolation. The `Task { ... }` here has NO
   inherited isolation, so it must `await self.recordEvent(...)` (which
   is what the code does at line 79).
4. That Task enqueues a partial-task to call `recordEvent` on the bridge.
5. `recordEvent` runs only after `attach` returns (since `attach` is
   currently holding the actor) — actor reentrancy guarantees serial
   processing.
6. Inside `recordEvent`, `continuations.values` is iterated. If no
   consumer has subscribed yet (`bridge.eventStream` not yet called), the
   event is dropped.

**The proposed fix (sync setObserverToken + sync register in eventStream)
does NOT address this scenario.** A production CloudKit event that fires
before any consumer subscribes will still be lost. To fix this, either:
- The bridge buffers events between `attach` and first subscriber.
- Callers ensure subscription happens before `attach`.

In practice, Lillist's wiring presumably does monitor `start()` →
internally creates a stream → bridge `attach(to:)` happens around the same
time. If `attach` is called after `start`, the stream is already
subscribed by the time `attach` adds the observer, so no events are lost
even at startup. This is a wiring/ordering concern, not a bug in the
proposed fix.

### Effects of dropping `Task { register }` in `eventStream`

Walk through the production scenario where `eventStream` is read by the
monitor's `start()`:

```swift
public func start() async {
    let stream = await bridge.eventStream    // hop to bridge actor
    consumeTask = Task { [weak self] in
        for await event in stream {
            await self?.apply(event)
        }
    }
}
```

With the proposed sync register:

1. `await bridge.eventStream` suspends `start`'s task, hops to bridge.
2. Inside bridge: getter constructs `AsyncStream`, builder closure runs
   synchronously, calls `self.register(id:continuation:)` — synchronous
   same-actor call. Continuation is stored in `continuations` dict.
3. Getter returns the stream. `start` resumes.
4. `consumeTask = Task { ... }` creates the consumer task.
5. Consumer task's body starts running; `for await event in stream`
   suspends waiting for the first yield.
6. If a recordEvent fires before step 5 completes, the event is in the
   stream's buffer (because the continuation IS registered). The
   for-await loop picks it up when it next runs.

Compared to current shape:
- Current shape can drop an event arriving between step 1 (suspend on
  bridge) and step 2 (deferred Task running register).
- Proposed shape eliminates that window.

**Blast radius:** Strictly improved, zero regression risk.

### What if a caller does `await bridge.eventStream` *twice* (concurrent)?

Each call constructs a fresh `AsyncStream`, each with a fresh continuation
and a fresh UUID. The bridge actor serializes both `register` calls. After
both return, `continuations` has two entries. `recordEvent` fans out to
both. No race.

In current shape, the two `Task { register }` calls also serialize on the
actor, but their order is non-deterministic. Same outcome though (both
end up in the dict eventually).

**Blast radius:** No change for the multi-subscriber case.

### What about `continuation.onTermination`?

The onTermination closure (lines 58–60) does `Task { await
self.unregister(id: id) }`. This closure is `@Sendable` and not
actor-isolated — the Task wrapper here genuinely IS needed, because the
closure can't directly call an actor-isolated method synchronously. The
fix proposal preserves this Task. Verified.

---

## 7. Runnable experiment summary

| Experiment | File | What it proves |
|-----------|------|----------------|
| 1: pre-buffer | `scratch/exp1_prebuffer.swift` | AsyncStream's `.unbounded` buffer DOES hold pre-iterator yields; the bridge bug is NOT a buffer bug |
| 2: type check | `scratch/exp2_isolation.swift` | Synchronous `self.register(...)` compiles under Swift 6 + strict-concurrency=complete |
| 3: sync register | `scratch/exp3_synchronous_register.swift` | With sync register, no events are dropped even without yields |
| 4: actor FIFO | `scratch/exp4_actor_fifo.swift` | Actors do NOT enforce source-order FIFO across competing tasks; 26 reorders / 1000 trials |
| 5: race B | `scratch/exp5_race_b.swift` | Even with sync register, Race B (apply-vs-read) persists; ~0.5–2% fail rate |
| 6: iterator pattern | `scratch/exp6_iterator_sync.swift` | iterator.next() pattern is deterministic; 0/1000 fails over 5 trials |
| 7: attach safety | `scratch/exp7_attach_race.swift` | Dropping `Task { setObserverToken }` is safe; direct call in actor method works |
| 8: current shape | `scratch/exp8_current_shape.swift` | Current bridge shape has 1/1000 fail rate at low load (matches observed rare-flake) |
| 9: under load | `scratch/exp9_under_load.swift` | Cooperative-pool contention doesn't reliably amplify in synthetic test, but doesn't refute observed CI flakiness either |

---

## 8. Verdict

### H1 survives

Both Race A (pre-subscription drop) and Race B (apply-vs-read reordering)
are empirically verifiable. The remediation as proposed —
1. Drop `Task { register }` from all three actor getters
2. Drop `Task { setObserverToken }` from `attach(to:)`
3. Rewrite tests to use `iterator.next()` against `monitor.statusStream`

— addresses both races and the production observer-token hazard. None of
the three steps is symptom-masking; each closes a distinct ordering hazard.

### Corrections to incorporate

1. **`EVIDENCE.md` §1, lines 60–63**: rephrase "no buffering" — AsyncStream
   buffers fine. The bug is that the bridge's producer side gates `yield`
   on a dict-population race. The fix is "register synchronously so
   `yield` is called for every event," not "add buffering."

2. **`HYPOTHESES.md` H1 falsification test**: include a stress
   reproduction post-fix that verifies BOTH Race A and Race B are gone.
   The minimum-viable verification is 50+ runs of the full Sync suite
   under load with zero failures. Even better: a contrived test where the
   bridge fires events before the consumer subscribes, exercising Race A
   directly (which would fail today, pass after the fix).

3. **Production fix priority**: the producer-side fix matters more than
   the test fix for production safety. Even if tests are rewritten to use
   `iterator.next()`, leaving `Task { register }` in place means
   `bridge.attach(to:)` followed by `monitor.start()` followed quickly by
   real CloudKit events can still drop the first event in production. The
   fix to the getter is the load-bearing production safety improvement;
   the test rewrite is the load-bearing test-stability improvement.

### Things NOT to do

- **Do NOT add `.serialized` to the suite as the primary fix.** That
  masks the symptom without removing the hazard (H3 in HYPOTHESES.md).
- **Do NOT add more yields.** Yields are not barriers (proven empirically
  in exp5 — even 5 yields don't get reliable ordering).
- **Do NOT add a pre-subscription buffer to the bridge as a primary fix.**
  AsyncStream's buffer already handles that; the bug is upstream.
  Replaying events for late subscribers may be desirable for *other*
  reasons but is not the race fix.

---

## Cited file:line index

- `CloudKitEventBridge.swift:52-62` — racy eventStream getter (proposed
  fix: drop `Task { }`).
- `CloudKitEventBridge.swift:73-85` — `attach(to:)` with two Task
  wrappers; only the inner (NotificationCenter observer's) Task is
  load-bearing.
- `CloudKitEventBridge.swift:84` — setObserverToken Task (drop).
- `CloudKitEventBridge.swift:91-93` — `register` body (no replay; that's
  fine).
- `SyncStatusMonitor.swift:25-33` — `start()` with detached consumer.
- `SyncStatusMonitor.swift:35-45` — statusStream getter (proposed fix:
  drop `Task { }`).
- `SyncStatusMonitor.swift:47-50` — registerStatus does initial replay
  (correct).
- `SyncStatusMonitor.swift:56-74` — apply writes state then yields.
- `AccountStateMonitor.swift:51-63` — stateStream getter (proposed fix:
  drop `Task { }`).
- `SyncStatusMonitorTests.swift:46-60` — observed-failing test (rewrite
  with `iterator.next()`).
- `SyncStatusMonitorTests.swift:62-73` — working iterator pattern (use as
  template).
- `SyncStackSmokeTests.swift:8-25` — also uses yield-polling (rewrite).
- `CloudKitEventBridgeTests.swift:7-37` — uses iterator pattern but with
  vestigial yields (clean up).
- `Package.swift:24` — `StrictConcurrency` enabled on source target only.
