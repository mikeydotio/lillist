# Investigator Report — sync-status-monitor-event-drop

Scope: git history and architecture of the Sync subsystem (`CloudKitEventBridge`, `SyncStatusMonitor`, `AccountStateMonitor`) and its tests. No fixes proposed; facts only.

---

## Git History Findings

### Commits touching Sync/ (chronological, oldest first)

| SHA | Date (2026-05-13) | Subject |
|---|---|---|
| `72ec008` | — | feat: add iCloudAccountState public enum mapping from CKAccountStatus |
| `296facb` | 10:51 PDT | feat: add AccountStateMonitor actor with mockable status provider |
| `4ea7b48` | — | feat: add SyncStatus value type for CloudKit sync state snapshots |
| `7507a03` | 10:53 PDT | feat: add CloudKitEventBridge and SyncStatusMonitor for sync status tracking |
| `e02c9f4` | 10:57 PDT | test: add sync stack smoke test wiring bridge to monitors |
| `e2a3a5f` | 14:02 PDT | fix: drop redundant await on same-actor stateStream registration |
| `f310020` | 14:02 PDT | fix: drop redundant await on same-actor eventStream registration |
| `7049a3f` | 14:03 PDT | fix: drop redundant await on same-actor setObserverToken call |
| `3b5f59f` | 14:03 PDT | fix: drop redundant await on same-actor statusStream registration |

All sync code is recent — a single workday on 2026-05-13. The four "redundant await" fixes landed roughly three hours after the initial implementation, in a tight cluster (`14:02–14:03`).

### Has the `Task { ... }` wrapper ever been absent in these getters?

**No. The wrapper has been present since the FIRST commit for every getter in question.**

Evidence — initial introductions (showing the original lines verbatim):

- `CloudKitEventBridge.eventStream` introduced in `7507a03`:
  ```swift
  public var eventStream: AsyncStream<CloudKitSyncEvent> {
      AsyncStream { continuation in
          let id = UUID()
          Task { await self.register(id: id, continuation: continuation) }
          continuation.onTermination = { _ in
              Task { await self.unregister(id: id) }
          }
      }
  }
  ```
- `CloudKitEventBridge.attach(to:)` introduced in `7507a03` — uses the same `Task { ... }` pattern for `setObserverToken`.
- `SyncStatusMonitor.statusStream` introduced in `7507a03` — same pattern.
- `AccountStateMonitor.stateStream` introduced in `296facb` — same pattern (predates the bridge by ~2 minutes).

So at no point in the file history was the call ever direct/synchronous; it was wrapped in `Task { ... }` from the moment the getter was authored.

### Why was the wrapper added in the first place? (commit messages + comments)

Neither `7507a03` nor `296facb` contains any commit-message rationale for using `Task { ... }`. The original code has no inline comment explaining it either. The pattern is uniform across all three getters in the same author's same-day work, suggesting it was a "house style" choice rather than a reasoned decision documented in the diff.

The clearest evidence of intent appears later, in the four "fix" commits:

- `e2a3a5f` commit message (the first of the four):
  > "The Task { ... } inside stateStream's body inherits the actor's isolation under Swift 6, so calling self.register(...) is a same-actor call — the await was redundant and produced a 'no async operations' warning. The Task inside continuation.onTermination must keep its await because that closure is @Sendable and crosses actor isolation."

  This explains why the *inner* `await` was redundant, but it explicitly accepts the *outer* `Task { ... }` wrapper as load-bearing — the rationale given is "the outer Task inherits the actor's isolation," which is treated as the reason the `await` could be dropped, **not** as evidence the Task is unneeded.

- `7049a3f` commit message (about `setObserverToken`):
  > "The Task { ... } at the bottom of attach(to:) inherits the actor isolation from its enclosing method, making self.setObserverToken(...) a same-actor call. The Task { await self.recordEvent(...) } inside the NotificationCenter observer's @Sendable closure correctly keeps its await because that closure does not inherit isolation."

- `f310020` and `3b5f59f` commit messages are terse one-liners with no rationale.

The inline comments added by the fix commits (e.g. `CloudKitEventBridge.swift:55-56`, `SyncStatusMonitor.swift:38-39`, `AccountStateMonitor.swift:54-57`) all justify the *Task isolation inheritance*, never the *existence* of the Task wrapper.

**Conclusion on intent:** The `Task { ... }` wrapper appears to be defensive scaffolding the author put in place when first writing the `AsyncStream { ... }` closures — likely because `AsyncStream`'s producer closure is `@Sendable` and the author was uncertain whether it could call an actor-isolated method synchronously. Under Swift 6 / strict concurrency, a `Task { }` spawned inside an actor-isolated computed-property getter inherits the actor's isolation, which is what the four fix commits leveraged to remove the inner `await`. The author refactored to remove the redundant `await`s but never reconsidered whether the `Task { }` itself was needed. No commit explicitly states "this Task must remain to satisfy `@Sendable` closure isolation rules" — that's an inference the comments hint at but never prove.

### Other relevant facts from history

- The original `7507a03` already shipped the test files (`CloudKitEventBridgeTests.swift`, `SyncStatusMonitorTests.swift`) with the `for _ in 0..<5 { await Task.yield() }` polling pattern. The polling was contemporaneous with the producer code, not added later in response to a race.
- The smoke test (`e02c9f4`, four minutes after the feature commit) repeats the same polling pattern (`SyncStackSmokeTests.swift:13`, `:17`, `:19`). Same author, same day.
- `CloudKitEventBridgeTests.swift` (introduced in `7507a03`) uses `await Task.yield()` once or twice between registration and the first `recordEvent` (lines 12–13, 31–32) — confirming the author *was* aware they needed to give the registration task a chance to run, but chose yield-polling rather than a deterministic await.
- No commit in the file history modifies the `recordEvent` / `apply` event-flow semantics. The race shape established in `7507a03` is the race shape that exists today.

---

## Architecture Findings

### File inventory

- `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift` (112 lines)
- `Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift` (76 lines)
- `Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift` (82 lines)
- `Packages/LillistCore/Sources/LillistCore/Sync/SyncStatus.swift` and `iCloudAccountState.swift` (value types, not in race path)
- `Packages/LillistCore/Tests/LillistCoreTests/Sync/SyncStatusMonitorTests.swift` (75 lines)
- `Packages/LillistCore/Tests/LillistCoreTests/Sync/CloudKitEventBridgeTests.swift` (39 lines)
- `Packages/LillistCore/Tests/LillistCoreTests/Sync/SyncStackSmokeTests.swift` (40 lines)
- `Packages/LillistCore/Tests/LillistCoreTests/Sync/AccountStateMonitorTests.swift` (76 lines)

### Actor topology

Two independent actors in the sync flow path:

1. **`CloudKitEventBridge`** (`CloudKitEventBridge.swift:35`)
   - State: `continuations: [UUID: AsyncStream<CloudKitSyncEvent>.Continuation]` (line 36), `observerToken: NSObjectProtocol?` (line 37).
   - Producers feeding it events: production via `attach(to:)` → NotificationCenter observer (line 75–80, fires `Task { await self.recordEvent(...) }`); tests via direct `await bridge.recordEvent(...)`.
   - Consumers: anyone holding the result of `await bridge.eventStream`.

2. **`SyncStatusMonitor`** (`SyncStatusMonitor.swift:5`)
   - State: `currentStatus: SyncStatus` (line 6), `consumeTask: Task<Void, Never>?` (line 9), `statusContinuations: [UUID: AsyncStream<SyncStatus>.Continuation]` (line 10).
   - Holds a `bridge: CloudKitEventBridge` reference.
   - `start()` (line 25) reads `await bridge.eventStream` once, then spawns `consumeTask` which loops `for await event in stream { await self?.apply(event) }`.
   - Republishes via its own `statusStream`.

3. **`AccountStateMonitor`** (`AccountStateMonitor.swift:23`) — parallel structure, NOT wired to the bridge. Driven by `refresh()` and `simulateAccountChange()` calls instead.

### Call/data flow for the failing test path

```
Test exportFails()                                Bridge actor                 Monitor actor
─────────────────────────────────────────────────────────────────────────────────────────────
let bridge = CloudKitEventBridge()
let monitor = SyncStatusMonitor(bridge: bridge)
await monitor.start()  ─────────────────────────► reads eventStream (NEW)
                                                  AsyncStream init:
                                                    spawns Task#A {
                                                      register(id, cont)
                                                    } ─── pending ───┐
                                                  returns stream     │
                                                  ◄─────────────     │
                                                  consumeTask = Task#C ──► for await … (suspended on stream)
for _ in 0..<5 { await Task.yield() }              ◄─ (Task#A *might* run here)
await bridge.recordEvent(.started)  ────────────► iterates continuations.values
                                                  IF Task#A hasn't run yet → dict empty → DROP
                                                  IF Task#A has run → cont.yield(event)
                                                                                          ◄─── stream produces event
                                                                                          Task#C body:
                                                                                          await self.apply(event) ── pending hop ──┐
for _ in 0..<5 { await Task.yield() }                                                                                              │
                                                                                                                  apply runs ◄────┘
                                                                                                                  currentStatus = inProgress
await bridge.recordEvent(.ended,err) ────────────► (continuations now populated) cont.yield(event)
                                                                                          Task#C: await apply(event) — hop pending
for _ in 0..<5 { await Task.yield() }                                                     apply runs → status = error
let status = await monitor.currentStatus  ───────────────────────────────────────────────► reads currentStatus
#expect(...)
```

#### Drop sites — where events can be lost

1. **`CloudKitEventBridge.eventStream` registration race** (`CloudKitEventBridge.swift:52–62`).
   - `Task { self.register(id: id, continuation: continuation) }` is fire-and-forget. The getter returns before the Task body runs (the Task is enqueued, not executed inline).
   - If `recordEvent` (called via `await bridge.recordEvent(...)`) is scheduled onto the bridge actor's serial queue *before* the registration Task runs, it sees an empty `continuations` dict and silently drops the event (line 66: `for continuation in continuations.values { continuation.yield(event) }`).
   - The "before/after" question is decided by the actor's reentrancy/scheduling, which is non-deterministic under cooperative scheduling load.

2. **`SyncStatusMonitor.statusStream` registration race** (`SyncStatusMonitor.swift:35–45`).
   - Identical shape. Same drop semantics if a test calls `await monitor.statusStream` (creating a fresh stream) and then enqueues an event before the inner Task registers.
   - Not the failing test's path — the failing test reads `currentStatus` directly, not the stream — but the same race exists.

3. **`SyncStatusMonitor.apply` hop latency** (`SyncStatusMonitor.swift:28–32`).
   - `consumeTask`'s body is `await self?.apply(event)`. Each event triggers an actor hop onto the monitor. The test's final `await monitor.currentStatus` is itself an actor hop. Nothing guarantees `apply` runs before `currentStatus` is read — the monitor actor's serial queue could process `currentStatus` first if it was enqueued earlier.
   - This is the SECOND drop site the symptom report names ("Hop B") — but it's not a "drop," it's a "stale read." The event still gets applied, just after the assertion fires.

4. **`CloudKitEventBridge.attach(to:)` observer-token race** (`CloudKitEventBridge.swift:73–85`).
   - `Task { self.setObserverToken(token) }` defers writing `observerToken`. If `detach()` is called before the Task runs, `observerToken` is still `nil` and the NotificationCenter observer is leaked (no `removeObserver` runs).
   - Not in the failing-test path, but a real production hazard.

5. **`CloudKitEventBridge.attach(to:)` notification observer race** (`CloudKitEventBridge.swift:75–80`).
   - The observer closure does `Task { await self.recordEvent(translated) }`. If a real CloudKit event fires before *any* consumer has registered its continuation via `await bridge.eventStream`, the event is broadcast to an empty `continuations` dict and dropped. This is the production-impact case the symptom report mentions.

#### Buffering between producer and consumer

**There is no buffering of any kind.**

- `AsyncStream { ... }` is constructed with the default buffering policy, which is `.unbounded`. **However**, the stream's continuation only exists after `Task#A` runs `register()`. Until then, calling `recordEvent` does NOT enqueue into any buffer — it iterates over `continuations.values`, finds nothing, and the event is irretrievably gone.
- `recordEvent` (line 65) does not store the event anywhere. If no continuation is registered at the moment it runs, the event is dropped.
- No replay buffer, no "last event," no queue. Each `recordEvent` is a one-shot fan-out to whatever continuations exist *at that instant*.
- `registerStatus` in `SyncStatusMonitor` (line 47–50) DOES replay the current status on registration (`continuation.yield(currentStatus)`) — but `register` in `CloudKitEventBridge` (line 91–93) does NOT. The bridge has no concept of "current event."

### Same race in `AccountStateMonitor`?

Yes, confirmed structurally. The race exists but with different blast radius.

- `AccountStateMonitor.stateStream` getter (`AccountStateMonitor.swift:51–63`) has the identical `Task { self.register(...) }` shape as the bridge.
- If a caller does `await monitor.stateStream` and then immediately `try await monitor.refresh()`, and the `refresh` actor hop is processed by the actor's serial queue before the registration Task runs, then `publish` (line 75–80) iterates an empty `continuations` dict and the state update is dropped FROM THE STREAM (the actor's `currentState` field is still updated correctly on line 76; only the stream notification is lost).
- `register` DOES replay `currentState` on registration (line 68: `continuation.yield(currentState)`), so a consumer that subscribes after a `publish` will see the latest value as the stream's first element. This is a meaningful difference from the bridge: a late subscriber to `stateStream` gets the current value; a late subscriber to `eventStream` gets nothing about the missed event.
- The four `AccountStateMonitorTests` that exercise the stream all use `var iterator = await monitor.stateStream.makeAsyncIterator()` followed by `_ = await iterator.next()` to consume the initial replay (`AccountStateMonitorTests.swift:54–55`). That deterministic pattern sidesteps the race for the test, but the underlying register-deferral race still exists in production.

### Test runner configuration — parallel-by-default?

**Yes. Tests run in parallel by default.**

- `Packages/LillistCore/Package.swift` declares the test target on lines 28–31 with no test-level configuration:
  ```swift
  .testTarget(
      name: "LillistCoreTests",
      dependencies: ["LillistCore"]
  )
  ```
- No `.serialized` trait is applied to any `@Suite` or `@Test` in the Sync tests (verified by grep). Swift Testing's default mode runs tests in parallel across the suite.
- No `.serialized` attribute is set on `SyncStatusMonitorTests` or any sibling suite.
- `swift-tools-version: 6.0` (line 1) and `.enableExperimentalFeature("StrictConcurrency")` (line 24) confirm Swift 6 strict concurrency for the source target. Tests inherit Swift 6 semantics.
- Each of the five tests in `SyncStatusMonitorTests` constructs its own `CloudKitEventBridge()` and `SyncStatusMonitor(bridge:)` — they don't share state, so parallel execution is safe from a correctness standpoint. But parallel execution **does** increase scheduler contention, which makes the registration-Task starvation window wider and is the most plausible "load" trigger for the observed flake.

### Other tests using `for _ in 0..<N { await Task.yield() }`?

**Only the Sync tests.** Full repo search results:

- `Packages/LillistCore/Tests/LillistCoreTests/Sync/SyncStatusMonitorTests.swift` — 9 occurrences across 4 test methods (lines 21, 23, 34, 37, 39, 51, 54, 56, 67).
- `Packages/LillistCore/Tests/LillistCoreTests/Sync/SyncStackSmokeTests.swift` — 3 occurrences (lines 13, 17, 19), one test method.
- `Packages/LillistCore/Tests/LillistCoreTests/Sync/CloudKitEventBridgeTests.swift` — 4 single `await Task.yield()` calls (lines 12, 13, 31, 32), NOT in a `for _ in 0..<N` loop but morally the same pattern.

No other test file in the repository uses this pattern. The single non-test hit (`Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceExpander.swift:214`) is an unrelated `for _ in 0..<40` loop iterating a generation algorithm — not a yield-polling loop.

This means a fix that changes the test pattern only needs to touch the four Sync test files. There is no broader test-infrastructure dependency on yield-polling to consider.

### Inventory of polling sites that depend on registration race

| File | Lines | Purpose |
|---|---|---|
| `SyncStatusMonitorTests.swift:21,23` | `setupStarted` — wait for consumer subscribe, then wait for apply |
| `SyncStatusMonitorTests.swift:34,37,39` | `importCompletes` — wait for subscribe, wait for first apply, wait for second apply |
| `SyncStatusMonitorTests.swift:51,54,56` | `exportFails` — same as importCompletes; **this is the observed-flaky test** |
| `SyncStatusMonitorTests.swift:67` | `statusStream` — wait for consumer subscribe (BUT the test then uses deterministic `iterator.next()`, so the yield is essentially decorative) |
| `SyncStackSmokeTests.swift:13,17,19` | `endToEnd` — same shape as `importCompletes` |
| `CloudKitEventBridgeTests.swift:12,13` | `eventsStream` — single yields trying to win the registration race |
| `CloudKitEventBridgeTests.swift:31,32` | `fanOut` — same |

All of these are vulnerable to the bridge-registration race. The two `CloudKitEventBridgeTests` cases are particularly thin (only 2 yields each) and would be expected to flake under heavy parallel load too.

### Key code references (file:line)

- Bridge continuations dict: `CloudKitEventBridge.swift:36`
- Bridge eventStream getter (race site): `CloudKitEventBridge.swift:52–62`
- Bridge recordEvent (drop site — empty dict iteration): `CloudKitEventBridge.swift:65–69`
- Bridge attach → setObserverToken Task (secondary race): `CloudKitEventBridge.swift:84`
- Bridge attach → notification observer's recordEvent Task: `CloudKitEventBridge.swift:79`
- Monitor consumeTask creation: `SyncStatusMonitor.swift:28–32`
- Monitor statusStream getter (race site, status side): `SyncStatusMonitor.swift:35–45`
- Monitor registerStatus *does* replay current value: `SyncStatusMonitor.swift:49`
- Monitor apply: `SyncStatusMonitor.swift:56–74`
- AccountStateMonitor stateStream getter (race site, parallel structure): `AccountStateMonitor.swift:51–63`
- AccountStateMonitor register *does* replay current value: `AccountStateMonitor.swift:68`
- Failing test body: `SyncStatusMonitorTests.swift:46–60`
- Working deterministic pattern in same file: `SyncStatusMonitorTests.swift:62–73`
- Package test target config (no serialization, parallel by default): `Package.swift:28–31`
