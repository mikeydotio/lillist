# Plan 2 Follow-up — Strict-Concurrency Warning Cleanup

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the four `no 'async' operations occur within 'await' expression` warnings emitted by Plan 2's Sync code so `swift build -Xswiftc -warnings-as-errors` returns clean. These warnings were uncovered by Plan 3 Task 23's strict-warning sweep but are pre-existing in Plan 2 — this plan addresses them in isolation.

**Architecture:** Each of the four warning sites is a `Task { await self.somePrivateMethod(...) }` invocation inside an actor's actor-isolated context (either a computed-property body or a regular actor method). Under Swift 6, `Task { ... }` created in an actor-isolated context inherits the actor's isolation, so calling `self.somePrivateMethod(...)` is a same-actor synchronous call — the `await` is redundant and Swift flags it. The fix is to drop the `await` on those specific sites only; the `await` calls that cross actor boundaries (e.g. inside `continuation.onTermination` closures, inside NotificationCenter observer callbacks) MUST stay because they truly do hop actors. Verified empirically: dropping `await` from the outer `Task { ... }` compiles clean; dropping it from `onTermination`'s inner `Task { ... }` produces `actor-isolated instance method ... cannot be called from outside of the actor`.

**Tech Stack:** Swift 6, Swift Package Manager, Swift Testing. No third-party dependencies.

**Depends on:** Plan 2 (CloudKit Sync). The four affected files are `AccountStateMonitor.swift`, `CloudKitEventBridge.swift`, `SyncStatusMonitor.swift`. Plan 3 has already merged ahead of this work; the strict-warning bar from Plan 3 Task 23 must remain green for the new Rules code.

---

## Affected files

```
Packages/LillistCore/Sources/LillistCore/Sync/
├── AccountStateMonitor.swift       (1 site)
├── CloudKitEventBridge.swift       (2 sites)
└── SyncStatusMonitor.swift         (1 site)
```

Behavior is unchanged in every case — these are pure compiler-hint adjustments, no semantic shift in actor isolation or task lifecycle.

---

## Notes for the implementer

**Why not "just" mark the helper methods `async`?** It would silence the warning by giving the `await` something to await, but it would also break the inner `onTermination`/`NotificationCenter` `Task { await self.foo(...) }` calls (those genuinely do hop actors and rely on the implicit-async-from-isolation contract). Dropping the redundant `await` is the smaller, more targeted change.

**Why not `Task.detached { ... }`?** Detached tasks would still need an explicit `await self.foo(...)` and would change the lifecycle (no cancellation propagation from the surrounding actor's task tree). Out of scope.

**Verification cadence:** Run `swift build` after each task to watch the warning count decrease. Run `swift build -Xswiftc -warnings-as-errors` at the end to confirm clean. Run the full `swift test` suite to confirm no behavior changed.

---

## Task 1: AccountStateMonitor — drop redundant `await` in `stateStream`

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift`

The warning site:

```swift
public var stateStream: AsyncStream<iCloudAccountState> {
    AsyncStream { continuation in
        let id = UUID()
        Task { await self.register(id: id, continuation: continuation) }   // ← warning
        continuation.onTermination = { _ in
            Task { await self.unregister(id: id) }                          // KEEP await
        }
    }
}
```

The outer `Task { ... }` is created from inside `stateStream`'s computed-property body. That body is actor-isolated; the `Task` inherits the actor isolation; `self.register` is a same-actor call. The `await` is redundant.

The `onTermination` closure is `@Sendable` and runs disconnected from the actor's context — the `Task { await self.unregister(...) }` inside it MUST keep `await`.

- [ ] **Step 1: Confirm baseline warning exists**

Run: `cd Packages/LillistCore && swift build 2>&1 | grep AccountStateMonitor`
Expected: a `warning: no 'async' operations occur within 'await' expression` line pointing at `AccountStateMonitor.swift:54`.

- [ ] **Step 2: Edit the source**

Edit `Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift`. In the `stateStream` computed property, change exactly one line:

```diff
-            Task { await self.register(id: id, continuation: continuation) }
+            Task { self.register(id: id, continuation: continuation) }
```

Leave the `Task { await self.unregister(id: id) }` line inside `onTermination` untouched.

- [ ] **Step 3: Rebuild and confirm warning is gone**

Run: `cd Packages/LillistCore && swift build 2>&1 | grep AccountStateMonitor`
Expected: no output (no warnings on this file).

- [ ] **Step 4: Run AccountStateMonitor tests**

Run: `cd Packages/LillistCore && swift test --filter AccountStateMonitorTests`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift
git commit -m "fix: drop redundant await on same-actor stateStream registration

The Task { ... } inside stateStream's body inherits the actor's
isolation under Swift 6, so calling self.register(...) is a same-actor
call — the await was redundant and produced a 'no async operations'
warning. The Task inside continuation.onTermination must keep its
await because that closure is @Sendable and crosses actor isolation."
```

---

## Task 2: CloudKitEventBridge — drop redundant `await` in `eventStream`

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift`

Same pattern as Task 1, in the `eventStream` computed property:

```swift
public var eventStream: AsyncStream<CloudKitSyncEvent> {
    AsyncStream { continuation in
        let id = UUID()
        Task { await self.register(id: id, continuation: continuation) }   // ← warning at line 55
        continuation.onTermination = { _ in
            Task { await self.unregister(id: id) }                          // KEEP await
        }
    }
}
```

- [ ] **Step 1: Confirm baseline warning**

Run: `cd Packages/LillistCore && swift build 2>&1 | grep "CloudKitEventBridge.swift:55"`
Expected: one warning line.

- [ ] **Step 2: Edit the source**

In `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift`, change exactly one line in the `eventStream` body:

```diff
-            Task { await self.register(id: id, continuation: continuation) }
+            Task { self.register(id: id, continuation: continuation) }
```

Leave the `Task { await self.unregister(id: id) }` inside `onTermination` untouched.

- [ ] **Step 3: Rebuild and confirm only the other expected warning remains for this file**

Run: `cd Packages/LillistCore && swift build 2>&1 | grep "CloudKitEventBridge.swift"`
Expected: zero references to line 55. (The other CloudKitEventBridge warning at line 79 is addressed in Task 3.)

- [ ] **Step 4: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift
git commit -m "fix: drop redundant await on same-actor eventStream registration"
```

---

## Task 3: CloudKitEventBridge — drop redundant `await` in `attach(to:)`

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift`

The remaining warning is on line 79 inside `attach(to:)`:

```swift
public func attach(to container: NSPersistentCloudKitContainer) {
    let name = NSPersistentCloudKitContainer.eventChangedNotification
    let token = NotificationCenter.default.addObserver(forName: name, object: container, queue: nil) { [weak self] notification in
        guard let self else { return }
        guard let ckEvent = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
        let translated = Self.translate(ckEvent)
        Task { await self.recordEvent(translated) }    // KEEP await — observer closure is @Sendable, not actor-isolated
    }
    Task { await self.setObserverToken(token) }        // ← warning at line 79
}
```

`attach(to:)` is a regular actor method — actor-isolated. The `Task { ... }` on line 79 inherits that isolation; calling `self.setObserverToken(...)` is a same-actor call. Drop the `await` on this one site only.

The `Task { await self.recordEvent(translated) }` on line 77 lives inside the NotificationCenter observer's `[weak self]` closure, which is `@Sendable` and runs disconnected from the actor's task tree. Its `await` MUST stay.

- [ ] **Step 1: Confirm baseline warning**

Run: `cd Packages/LillistCore && swift build 2>&1 | grep "CloudKitEventBridge.swift:79"`
Expected: one warning line.

- [ ] **Step 2: Edit the source**

In `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift`, change exactly one line at the bottom of `attach(to:)`:

```diff
-        Task { await self.setObserverToken(token) }
+        Task { self.setObserverToken(token) }
```

Leave line 77's `Task { await self.recordEvent(translated) }` exactly as-is.

- [ ] **Step 3: Rebuild and confirm CloudKitEventBridge is now warning-free**

Run: `cd Packages/LillistCore && swift build 2>&1 | grep CloudKitEventBridge`
Expected: no output.

- [ ] **Step 4: Run CloudKitEventBridge tests**

Run: `cd Packages/LillistCore && swift test --filter CloudKitEventBridgeTests`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift
git commit -m "fix: drop redundant await on same-actor setObserverToken call

The Task { ... } at the bottom of attach(to:) inherits the actor
isolation from its enclosing method, making self.setObserverToken(...)
a same-actor call. The Task { await self.recordEvent(...) } inside
the NotificationCenter observer's @Sendable closure correctly keeps
its await because that closure does not inherit isolation."
```

---

## Task 4: SyncStatusMonitor — drop redundant `await` in `statusStream`

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift`

Same pattern as Task 1, in `statusStream`:

```swift
public var statusStream: AsyncStream<SyncStatus> {
    AsyncStream { continuation in
        let id = UUID()
        Task { await self.registerStatus(id: id, continuation: continuation) }   // ← warning at line 38
        continuation.onTermination = { _ in
            Task { await self.unregisterStatus(id: id) }                          // KEEP await
        }
    }
}
```

- [ ] **Step 1: Confirm baseline warning**

Run: `cd Packages/LillistCore && swift build 2>&1 | grep SyncStatusMonitor`
Expected: one warning line pointing at line 38.

- [ ] **Step 2: Edit the source**

In `Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift`, change exactly one line:

```diff
-            Task { await self.registerStatus(id: id, continuation: continuation) }
+            Task { self.registerStatus(id: id, continuation: continuation) }
```

Leave `Task { await self.unregisterStatus(id: id) }` in `onTermination` untouched.

- [ ] **Step 3: Rebuild and confirm warning is gone**

Run: `cd Packages/LillistCore && swift build 2>&1 | grep -E "warning|error"`
Expected: no output (the four warnings should all be gone now).

- [ ] **Step 4: Run SyncStatusMonitor tests**

Run: `cd Packages/LillistCore && swift test --filter SyncStatusMonitorTests`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift
git commit -m "fix: drop redundant await on same-actor statusStream registration"
```

---

## Task 5: Final verification

**Files:**
- (no new files)

- [ ] **Step 1: Strict-warning build**

Run: `cd Packages/LillistCore && swift build -Xswiftc -warnings-as-errors`
Expected: `Build complete!`, no warnings escalated to errors.

- [ ] **Step 2: Full test suite**

Run: `cd Packages/LillistCore && swift test`
Expected: all 224+ tests pass. Sync-related suites (`AccountStateMonitorTests`, `CloudKitEventBridgeTests`, `SyncStatusMonitorTests`, `SyncStackSmokeTests`, `iCloudAccountStateTests`) should be unchanged in count and all green.

- [ ] **Step 3: Tag**

```bash
git tag -a plan-2-strict-warnings -m "Plan 2 follow-up: strict-concurrency warning cleanup complete"
```

Done. The Plan 3 strict-warning expectation (`swift build -Xswiftc -warnings-as-errors` clean) is now satisfied across the whole package.

---

## Self-Review Checklist

- [ ] All four warning sites resolved (`AccountStateMonitor.swift:54`, `CloudKitEventBridge.swift:55`, `CloudKitEventBridge.swift:79`, `SyncStatusMonitor.swift:38`).
- [ ] `await` was removed only from `Task { ... }` blocks that live in actor-isolated context. The three `Task { await self.unregister(...) }` calls inside `continuation.onTermination` and the one `Task { await self.recordEvent(...) }` inside the NotificationCenter observer closure still have their `await` keywords.
- [ ] No changes to public API surface.
- [ ] No new tests required: the change is a pure compiler-hint adjustment with no runtime-observable behavior change. Existing Sync tests provide the regression net.
- [ ] `swift build -Xswiftc -warnings-as-errors` passes clean.
- [ ] `swift test` passes the full 224-test suite.
