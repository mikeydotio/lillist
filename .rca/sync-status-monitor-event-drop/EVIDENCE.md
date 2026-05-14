# Evidence: SyncStatusMonitor "Failed export" Flake

Phase 2 evidence collection for the intermittent failure of
`SyncStatusMonitorTests."Failed export records the error and clears inProgress"`.
Scope: code patterns, concurrency primitives, test coverage, reproduction.

All file paths absolute. Read-only investigation — no source code modified.

---

## 1. AsyncStream Semantics — Pre-Subscription Events Are Silently Dropped

### `CloudKitEventBridge.eventStream` (the producer)

`/Volumes/Code/mikeyward/Lillist/Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift:52-62`:

```swift
public var eventStream: AsyncStream<CloudKitSyncEvent> {
    AsyncStream { continuation in
        let id = UUID()
        // Outer Task inherits this actor's isolation; the inner
        // onTermination closure does not and must keep its `await`.
        Task { self.register(id: id, continuation: continuation) }
        continuation.onTermination = { _ in
            Task { await self.unregister(id: id) }
        }
    }
}
```

`register` writes into the dictionary
(`/Volumes/Code/mikeyward/Lillist/Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift:91-93`):

```swift
private func register(id: UUID, continuation: AsyncStream<CloudKitSyncEvent>.Continuation) {
    continuations[id] = continuation
}
```

`recordEvent`
(`/Volumes/Code/mikeyward/Lillist/Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift:65-69`):

```swift
public func recordEvent(_ event: CloudKitSyncEvent) {
    for continuation in continuations.values {
        continuation.yield(event)
    }
}
```

### Trace: pre-subscription event

When `recordEvent` runs while `continuations` is empty:
1. `for continuation in continuations.values { ... }` — iterator over an empty
   collection → loop body never executes.
2. No buffering. No `pending` array. No replay queue.
3. The event is dropped on the floor with no diagnostic.

This is **silent data loss**: the producer has no way to know whether any
subscriber received the event, and `AsyncStream`'s default buffer
(`.unbounded`) is only meaningful AFTER the continuation has been handed
to the stream's runtime — which here only happens once `register` actually
runs and stores the continuation in the dictionary keyed by `id`.

Critically, the `AsyncStream` instance returned by the getter is constructed
synchronously — the closure body runs synchronously when the stream is built.
But the closure spawns `Task { self.register(...) }` (line 57), which suspends
to the actor's executor. The `AsyncStream` object is returned to the caller
**before** the registration Task has been scheduled or run.

### Same pattern on the consumer side: `SyncStatusMonitor.statusStream`

`/Volumes/Code/mikeyward/Lillist/Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift:35-54`:

```swift
public var statusStream: AsyncStream<SyncStatus> {
    AsyncStream { continuation in
        let id = UUID()
        Task { self.registerStatus(id: id, continuation: continuation) }
        continuation.onTermination = { _ in
            Task { await self.unregisterStatus(id: id) }
        }
    }
}

private func registerStatus(id: UUID, continuation: AsyncStream<SyncStatus>.Continuation) {
    statusContinuations[id] = continuation
    continuation.yield(currentStatus)   // <-- initial replay
}
```

Note: `registerStatus` does an "initial replay" yield (line 49). The bridge's
`register` does NOT (`CloudKitEventBridge.swift:91-93`). So the bridge is
strictly worse for late subscribers — there is no replay of the most-recent
event for sync-event consumers.

### Same pattern on `AccountStateMonitor`

`/Volumes/Code/mikeyward/Lillist/Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift:51-69`:

```swift
public var stateStream: AsyncStream<iCloudAccountState> {
    AsyncStream { continuation in
        let id = UUID()
        Task { self.register(id: id, continuation: continuation) }
        ...
    }
}

private func register(id: UUID, continuation: AsyncStream<iCloudAccountState>.Continuation) {
    continuations[id] = continuation
    continuation.yield(currentState)   // <-- initial replay
}
```

`AccountStateMonitor.register` also replays the latest state. The bridge is
the odd one out: it stores the continuation but does not replay, because
events are inherently transient.

---

## 2. Actor Reentrancy and FIFO Assumptions — Two Independent Race Hops

### The consumer pipeline (start → consume)

`SyncStatusMonitor.start()`
(`/Volumes/Code/mikeyward/Lillist/Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift:25-33`):

```swift
public func start() async {
    guard consumeTask == nil else { return }
    let stream = await bridge.eventStream   // (a) actor hop to bridge, get stream
    consumeTask = Task { [weak self] in     // (b) detached-isolation Task
        for await event in stream {
            await self?.apply(event)        // (c) actor hop to self
        }
    }
}
```

Step (a) suspends to the bridge actor, computes `eventStream`, and inside
that getter spawns `Task { self.register(...) }` (the registration Task).
That Task is enqueued on the bridge's executor but is NOT awaited. So when
`start` resumes from `await bridge.eventStream`, the continuation may still
be unregistered.

Step (b) creates a NEW `Task` with no isolation inheritance from `self`
(captures `[weak self]` and uses `await self?.apply`). The for-await loop
in the consumer Task runs on the cooperative pool, not on the monitor's
executor.

Step (c) hops back to the monitor actor to call `apply`. Each hop is an
enqueue + suspend that competes with other awaits on the same actor.

### Race window in the test `exportFails` (`SyncStatusMonitorTests.swift:46-60`)

```swift
@Test("Failed export records the error and clears inProgress")
func exportFails() async throws {
    let bridge = CloudKitEventBridge()
    let monitor = SyncStatusMonitor(bridge: bridge)
    await monitor.start()                                       // line 50
    for _ in 0..<5 { await Task.yield() }                        // line 51
    let err = LillistError.syncFailure(underlying: "network down")
    await bridge.recordEvent(.init(type: .export, started: true, endedAt: nil, error: nil))   // line 53
    for _ in 0..<5 { await Task.yield() }                        // line 54
    await bridge.recordEvent(.init(type: .export, started: false, endedAt: Date(), error: err))  // line 55
    for _ in 0..<5 { await Task.yield() }                        // line 56
    let status = await monitor.currentStatus                     // line 57
    #expect(status.inProgress == false)                          // line 58
    #expect(status.error == err)                                 // line 59
}
```

Competing tasks for the monitor actor's executor at the moment of line 57:
- The consumer Task's `await self?.apply(event)` (for both events).
- The test's `await monitor.currentStatus`.

Swift actors do NOT guarantee FIFO ordering of `await` calls; the runtime
is free to reorder enqueued partial-tasks. Even when ordering happens to
match enqueue order, the *enqueue* itself is racy: whether the consumer's
second `apply` has been enqueued yet depends on whether the for-await loop
in the consumer Task has woken from its iterator on the bridge stream.

### The "second event dropped" failure mode (observed in this investigation)

Per the test failure output, status reports `inProgress=true, error=nil` —
that is the state after applying ONLY the first event (started=true). The
SECOND event (started=false, error=err) was either:

a) Not yielded by `recordEvent` because `continuations` was empty at the
   moment of the call (the registration Task had not yet run); OR
b) Yielded but the consumer's iterator never picked it up before the test
   read `currentStatus`; OR
c) Yielded and applied, but the test's read enqueued ahead of the apply
   for the second event.

The pre-subscription drop hypothesis (a) is implausible for the *second*
event because by line 55 the 10 prior `Task.yield()` calls and one prior
successful event delivery (apparent from inProgress=true) imply the
continuation has been registered. So the prevailing failure mode for this
test is (b) or (c) — the second event's `apply` is enqueued AFTER the test's
`await monitor.currentStatus`.

For the *first* event in `setupStarted`/`importCompletes`/`exportFails`,
hypothesis (a) is plausible — pre-subscription drop is possible if the
registration Task hasn't run by line 53.

(`importCompletes` was observed failing in iter 18, 20, 22 of the 30-run
stress — same symptom: `inProgress=true, lastSyncedAt=nil`. That is
consistent with the SECOND event being missed, not the first.)

---

## 3. The Pattern That Works — `iterator.next()` as a Hard Sync Point

### `statusStream` test (`SyncStatusMonitorTests.swift:62-73`)

```swift
@Test("Status stream yields updates")
func statusStream() async throws {
    let bridge = CloudKitEventBridge()
    let monitor = SyncStatusMonitor(bridge: bridge)
    await monitor.start()
    for _ in 0..<5 { await Task.yield() }
    var iterator = await monitor.statusStream.makeAsyncIterator()
    _ = await iterator.next()                                          // line 69
    await bridge.recordEvent(.init(type: .setup, started: true, ...))  // line 70
    let next = await iterator.next()                                   // line 71
    #expect(next?.inProgress == true)
}
```

### Why `iterator.next()` is immune

`AsyncStream.Iterator.next()` is a true async function that returns
exactly when the next value is yielded into its continuation. It blocks
until either:
- the underlying `continuation.yield(value)` is called, OR
- the stream is finished.

Line 69 `await iterator.next()` waits for the initial replay yield (issued
by `registerStatus` on `SyncStatusMonitor.swift:49`). That replay only
fires AFTER `registerStatus` actually executes — so line 69 returning is
proof that the continuation is now in `statusContinuations`.

Line 71 `await iterator.next()` waits for `apply` to publish the next state
(`SyncStatusMonitor.swift:71-73`):

```swift
for continuation in statusContinuations.values {
    continuation.yield(next)
}
```

Critically, that yield is inside `apply`, after `currentStatus = next`
(line 70 of `SyncStatusMonitor.swift`). So when `iterator.next()` resumes
with a value, `apply` has already updated `currentStatus`. The state read
is no longer racing with the application; the iterator IS the sync point.

### Why the failing pattern is NOT immune

`Task.yield()` is documented as a cooperative-scheduling hint:
> Suspends the current task and allows other tasks to execute.

It does NOT guarantee:
- That a *specific* other task runs before resumption.
- That the scheduler will pick the registration/consumer Task over the
  current Task on resumption.
- Any "happens-before" relationship with any particular event.

Under load (other tasks competing for the cooperative pool), `Task.yield()`
may simply resume the same task without running the target task at all.
Five yields raise the probability the registration runs first but do not
guarantee it.

`await monitor.currentStatus` and `await self?.apply(event)` both enqueue
partial-tasks on the same actor's executor. The actor processes them in
*some* order, but there is no guarantee that the consumer's apply enqueues
before the test's read. The test reads stale state when the second apply
hasn't been enqueued yet.

---

## 4. Production Producer — Three Independent Task Wrappers

`CloudKitEventBridge.attach(to:)`
(`/Volumes/Code/mikeyward/Lillist/Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift:73-85`):

```swift
public func attach(to container: NSPersistentCloudKitContainer) {
    let name = NSPersistentCloudKitContainer.eventChangedNotification
    let token = NotificationCenter.default.addObserver(forName: name, object: container, queue: nil) { [weak self] notification in
        guard let self else { return }
        guard let ckEvent = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
        let translated = Self.translate(ckEvent)
        Task { await self.recordEvent(translated) }   // (i)
    }
    Task { self.setObserverToken(token) }              // (ii)
}
```

Three Task wrappers and their isolation:

1. `Task { self.setObserverToken(token) }` (line 84) — inherits the bridge
   actor's isolation (created inside `attach`, which is an actor-isolated
   method). Same-actor synchronous call wrapped in a Task. No `await`. The
   wrapper is gratuitous for correctness — `setObserverToken(token)` could
   be called directly. The Task wrapper merely defers it to the next
   scheduler turn.

2. `Task { await self.recordEvent(translated) }` (line 79) — created inside
   the NotificationCenter callback closure, which is `@Sendable` and runs
   on the notification queue (`queue: nil` means "post synchronously on
   the posting thread"). This Task has NO inherited isolation. It must
   `await` the actor hop to call `recordEvent`. This Task can be created
   at any time once the observer is registered.

3. `Task { self.register(...) }` (line 57, in `eventStream` getter) — same
   pattern as (1): inherits bridge's isolation, no `await` needed for the
   same-actor call, but the Task wrapper defers the call.

### Ordering races introduced by these wrappers

Imagine launch sequence: app starts, `bridge.attach(container)` is called,
then somewhere later `monitor.start()` is called. Race window:

- `attach` line 75: observer is registered with NotificationCenter
  IMMEDIATELY (synchronously). The observer is live before Task (ii) runs.
- `attach` line 84: Task (ii) is enqueued but `observerToken` may not be
  written to the actor's storage yet.
- Between line 75 and line 84 completing, a notification can fire,
  spawning Task (i) → `recordEvent(translated)`.
- If `monitor.start()` hasn't run yet (or its registration Task hasn't run),
  `recordEvent` sees an empty `continuations` dict and the event is dropped.

Specifically the race chain at app launch:
- Observer goes live (line 75): T0
- CloudKit fires `eventChangedNotification`: T0 + small δ
- Observer schedules Task (i): T0 + δ
- `attach` returns; caller may now schedule `monitor.start()`.
- `monitor.start()` line 27 (`SyncStatusMonitor.swift:27`):
  `await bridge.eventStream` runs the stream getter; the registration
  Task is scheduled but not run.
- Task (i) `recordEvent` runs — registration may not be in `continuations`
  yet → event dropped.

The bridge's design dropping the wrapping `Task` for `setObserverToken`
would close ONE race (token-write race), but the more important race is
the `register` race in `eventStream` getter — and that one is structural.

### Why `setObserverToken` was wrapped in a Task at all

The Task wrapper exists because the four commits in the history
(`f310020`, `7049a3f`, `3b5f59f`, `e2a3a5f`) all removed `await` from
inside `Task { … }` blocks but kept the Task wrapper. The likely original
shape was `Task { await self.register(...) }` (or similar) — written that
way because the AsyncStream builder closure is a non-isolated `@Sendable`
closure, and the author assumed the call had to hop. But Swift 6's
isolation inference for `Task { }` created inside an actor-isolated
context says: the Task inherits the enclosing isolation, so the call is
same-actor and synchronous.

The compiler then emitted "no async operations" warnings, prompting the
four "drop redundant await" commits. But **the Task wrapper itself was
never reconsidered**, because removing it requires changing the structure
(the AsyncStream builder closure is non-isolated; calling
`self.register(...)` directly from inside it would be a cross-isolation
call that DOES need `await`, and `AsyncStream.init` doesn't permit an
async body).

So the Task wrapper is load-bearing for the *types* (it's the only way
to get back onto the actor from the builder closure), but it's NOT
load-bearing for the *semantics* — the registration could equivalently
happen synchronously if there were a way to do it. The current shape
defers registration off the synchronous path, which is the entire bug.

---

## 5. Strict-Concurrency Settings

`/Volumes/Code/mikeyward/Lillist/Packages/LillistCore/Package.swift`:

```swift
.target(
    name: "LillistCore",
    resources: [
        .process("Model/LillistModel.xcdatamodeld")
    ],
    swiftSettings: [
        .enableExperimentalFeature("StrictConcurrency")    // line 24
    ],
    plugins: ["CompileCoreDataModel"]
),
.testTarget(
    name: "LillistCoreTests",
    dependencies: ["LillistCore"]
)
```

Findings:
- `StrictConcurrency` is enabled on the **production target** only.
- The **test target** has no `swiftSettings` block — no `StrictConcurrency`,
  no `existentialAny`, no warnings-as-errors.
- The toolchain is `swift-tools-version: 6.0` (Package.swift line 1), so
  the Swift 6 language mode applies regardless; but the experimental
  StrictConcurrency feature flag adds additional warnings.

### Why doesn't the compiler flag `Task { self.register(...) }` as a smell?

It doesn't, and CAN'T, because:
- The body `self.register(...)` is type-safe: same-actor synchronous call,
  no Sendable violations.
- The Task wrapper itself is well-formed: a Task initializer with a
  `@Sendable` (or isolated, depending on inference) closure body.
- The bug is **temporal**, not type-level: the Task runs "later" relative
  to other code paths. Type systems don't model "later".

The compiler emitted "no async operations" warnings on the *previous*
shape (`Task { await self.register(...) }`), which is what motivated the
four cleanup commits. Once the `await` was removed, the body became
synchronous and the warning vanished — leaving a now-pointless Task
wrapper that the compiler can't object to.

---

## 6. `Task.yield` Usage Inventory in Tests

`grep -n 'Task.yield' Packages/LillistCore/Tests/**/*.swift`:

### `/Volumes/Code/mikeyward/Lillist/Packages/LillistCore/Tests/LillistCoreTests/Sync/SyncStatusMonitorTests.swift`

| Line | Test | Purpose |
|------|------|---------|
| 21   | `setupStarted`       | wait for consumer task to subscribe to bridge (between `monitor.start()` and `recordEvent`) |
| 23   | `setupStarted`       | wait for consumer's `apply` to run (between `recordEvent` and read) |
| 34   | `importCompletes`    | wait for subscribe (post `start`) |
| 37   | `importCompletes`    | wait for first apply (post event #1) |
| 39   | `importCompletes`    | wait for second apply (post event #2) |
| 51   | `exportFails`        | wait for subscribe (post `start`) |
| 54   | `exportFails`        | wait for first apply (post event #1) |
| 56   | `exportFails`        | wait for second apply (post event #2) |
| 67   | `statusStream`       | wait for subscribe (post `start`) — but immediately followed by `iterator.next()` which is the actual sync point |

All nine sites use the same `for _ in 0..<5 { await Task.yield() }` idiom.

### `/Volumes/Code/mikeyward/Lillist/Packages/LillistCore/Tests/LillistCoreTests/Sync/SyncStackSmokeTests.swift`

| Line | Test | Purpose |
|------|------|---------|
| 13   | `endToEnd`           | wait for consumer to subscribe (post `monitor.start`) |
| 17   | `endToEnd`           | wait for first apply (post event #1) |
| 19   | `endToEnd`           | wait for second apply (post event #2) |

Same race pattern. This test is also vulnerable but wasn't in the
observed failure trace. Stress runs would likely reveal it too.

### `/Volumes/Code/mikeyward/Lillist/Packages/LillistCore/Tests/LillistCoreTests/Sync/CloudKitEventBridgeTests.swift`

| Line | Test | Purpose |
|------|------|---------|
| 12-13 | `eventsStream` | wait for the registration Task (post `makeAsyncIterator()`) |
| 31-32 | `fanOut`       | same — twice (two iterators) |

Note: these tests use the `iterator.next()` deterministic pattern AFTER
the yields. So the yields here only need to land the *initial* registration;
after that, every subsequent yield is sync'd by `iterator.next()`. Less
vulnerable but still racy on the first registration.

### Summary

- All 14 `Task.yield()` sites in the test suite serve the SAME purpose:
  papering over async-scheduling latency in lieu of a real sync barrier.
- 11 of them (in SyncStatusMonitorTests + SyncStackSmokeTests) use it as
  the only sync mechanism — these are vulnerable.
- 3 of them (in CloudKitEventBridgeTests) are paired with `iterator.next()`
  immediately after — these are less vulnerable.

---

## 7. Reproduction — Isolated Test, 20 Runs

Command (timing-stable build first, then loop):

```
cd Packages/LillistCore
for i in $(seq 1 20); do
  swift test --filter "exportFails" 2>&1 | tail -3
  echo "---"
done
```

Result: **20/20 PASS** in isolation.

The race window is too narrow to hit when only one test is in-flight at
a time. The `swift test --filter exportFails` invocation has minimal
contention for the cooperative thread pool.

---

## 8. Reproduction — Full SyncStatusMonitor Suite, 30 Runs

Command:

```
cd Packages/LillistCore
for i in $(seq 1 30); do swift test --filter SyncStatusMonitor 2>&1 ...; done
```

### Run 1 (during initial investigation):

**8 failures out of 30 runs** (~27% failure rate).

Failing tests across 30 iterations:
- iter 5: `Failed export records the error and clears inProgress`
- iter 8: `Failed export records the error and clears inProgress`
- iter 9: `Failed export records the error and clears inProgress`
- iter 13: `Failed export records the error and clears inProgress`
- iter 18: `Successful import completion clears inProgress and sets lastSyncedAt`
- iter 19: `Failed export records the error and clears inProgress`
- iter 20: `Successful import completion clears inProgress and sets lastSyncedAt`
- iter 22: `Successful import completion clears inProgress and sets lastSyncedAt`

### Run 2 (rerun later in investigation):

**1 failure out of 30** (~3% failure rate).

- iter 16: `Failed export records the error and clears inProgress`

### Observations

- Failure rate is highly load-dependent: 27% in run 1, 3% in run 2. The
  delta is likely background activity on the host between runs.
- The failure mode is consistent across all failures: the SECOND event in
  a two-event sequence is missed.
  - For `exportFails`: status = `inProgress=true, error=nil` → second
    event (the failure) never applied.
  - For `importCompletes`: status = `inProgress=true, lastSyncedAt=nil` →
    second event (the completion) never applied.
- The `setupStarted` test (one event) and `initial` test (no events) never
  fail. This is consistent with the race being timing-dependent on the
  consumer/apply path, not the registration path. (If registration were
  the bottleneck, `setupStarted` would also fail when the first event is
  dropped.)
- The `statusStream` test (using iterator.next pattern) never fails.

### Failing test diagnostic output (representative)

```
SyncStatusMonitorTests.swift:58:9: Expectation failed: (status.inProgress → true) == false
SyncStatusMonitorTests.swift:59:9: Expectation failed: (status.error → nil) == (err → .syncFailure(underlying: "network down"))
```

```
SyncStatusMonitorTests.swift:41:9: Expectation failed: (status.inProgress → true) == false
SyncStatusMonitorTests.swift:42:9: Expectation failed: (status.lastSyncedAt → nil) == (end → 1970-01-24 03:33:20 +0000)
```

All failures show the state stuck at "after the first event applied, before
the second event applied". No failure mode where the FIRST event is missed
was observed in these runs — only the SECOND.

---

## 9. Summary of Facts (No Hypotheses, No Fixes)

1. **`AsyncStream` has no buffering for pre-subscription yields in this
   design.** `recordEvent` iterates `continuations.values`; if the dict is
   empty, the event is dropped silently.
   (`CloudKitEventBridge.swift:65-69`)

2. **The `eventStream` getter returns before its `register` runs.** The
   `Task { self.register(...) }` wrapper defers registration off the
   synchronous return path. The `AsyncStream` object is returned (and the
   caller can begin awaiting events) before the bridge has stored the
   continuation.
   (`CloudKitEventBridge.swift:52-62`, lines 57)

3. **`Task.yield()` is a cooperative scheduling hint, not a barrier.** It
   does not guarantee that any specific other task will run before the
   yielder resumes.

4. **Actors do not provide FIFO ordering of awaits.** Two competing
   `await monitor.X` calls have no guaranteed order.

5. **`AsyncIterator.next()` IS a real sync barrier.** It blocks until the
   producer yields the next value. Tests that use this pattern
   (`statusStream` test, `CloudKitEventBridgeTests`) are not vulnerable to
   the late-subscriber drop in the way the polling tests are.

6. **`StrictConcurrency` is on for the source target but not the test
   target.** The compiler cannot flag the `Task { self.register(...) }`
   pattern because the body is type-correct; the bug is purely temporal.

7. **The bug reproduces under load** at 3-27% rate across 30-run suite
   stress runs. The race window is the time between
   `bridge.recordEvent(event_2)` being scheduled and the consumer task's
   `apply(event_2)` being enqueued on the monitor actor. If the test's
   `await monitor.currentStatus` enqueues first, the test reads stale state.

8. **All nine `Task.yield()` polling sites in `SyncStatusMonitorTests` and
   the three in `SyncStackSmokeTests` share the same anti-pattern.** They
   are structurally vulnerable, not just the one failing test.

9. **The fan-out structure** — bridge has continuations, monitor has its
   own continuations, observer registrations are deferred via `Task` —
   creates THREE independent task-scheduling races that must all resolve
   favourably for `recordEvent → apply → publish` to be visible to a
   timed read. Each `Task.yield()` increases the probability slightly;
   none guarantee it.

10. **The four "drop redundant await" commits** (f310020, 7049a3f, 3b5f59f,
    e2a3a5f) addressed compiler warnings about `await` on same-actor
    synchronous calls, but did not address the Task-wrapper deferral that
    actually causes the race. The wrapper is still present in
    `CloudKitEventBridge.swift:57,84` and `SyncStatusMonitor.swift:40` and
    `AccountStateMonitor.swift:58`.

### Cited file:line index

- `/Volumes/Code/mikeyward/Lillist/Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift:52-62` — racy eventStream getter
- `/Volumes/Code/mikeyward/Lillist/Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift:65-69` — recordEvent drops on empty continuations
- `/Volumes/Code/mikeyward/Lillist/Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift:73-85` — attach with three task wrappers
- `/Volumes/Code/mikeyward/Lillist/Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift:91-93` — register (no replay)
- `/Volumes/Code/mikeyward/Lillist/Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift:25-33` — start() with detached consumer
- `/Volumes/Code/mikeyward/Lillist/Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift:35-54` — statusStream getter (with replay)
- `/Volumes/Code/mikeyward/Lillist/Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift:56-74` — apply mutates state then yields
- `/Volumes/Code/mikeyward/Lillist/Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift:51-69` — same pattern, mirrored
- `/Volumes/Code/mikeyward/Lillist/Packages/LillistCore/Tests/LillistCoreTests/Sync/SyncStatusMonitorTests.swift:46-60` — failing test
- `/Volumes/Code/mikeyward/Lillist/Packages/LillistCore/Tests/LillistCoreTests/Sync/SyncStatusMonitorTests.swift:62-73` — working pattern
- `/Volumes/Code/mikeyward/Lillist/Packages/LillistCore/Tests/LillistCoreTests/Sync/SyncStackSmokeTests.swift:8-25` — vulnerable smoke test
- `/Volumes/Code/mikeyward/Lillist/Packages/LillistCore/Tests/LillistCoreTests/Sync/CloudKitEventBridgeTests.swift:7-37` — iterator.next pattern at bridge level
- `/Volumes/Code/mikeyward/Lillist/Packages/LillistCore/Package.swift:18-32` — StrictConcurrency on src target only
