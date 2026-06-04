# Migration-Adjacent Correctness Implementation Plan

> **📍 STATUS — ⬜ PENDING — Wave 4.**
>
> Part of the **Foundation Hardening** program. **Single source of truth for progress, wave order, and cross-plan coordination:** [`2026-05-29-foundation-hardening-index.md`](2026-05-29-foundation-hardening-index.md). New to this project? Read the index first, then the review ([`docs/reviews/2026-05-28-foundation-review.md`](../../reviews/2026-05-28-foundation-review.md)) for *why* this work exists, then `CLAUDE.md` for conventions + build/test commands. Execute task-by-task with `superpowers:subagent-driven-development`.
>
> **Pre-flight (run before any edit):** Confirm Waves 1–3 are on `main` (`git log --oneline main | head -20`). Read `docs/superpowers/handoffs/wave-3.md`. Re-Read every file you touch and anchor by code **structure**, not line number — each wave shifts the shared hotspot files. On completion, write `docs/superpowers/handoffs/wave-4.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore correct notification + sync steady-state after a sync-mode migration, make the migration journal report staleness so only the main-app recovery sheet acts on a crashed migration, tell the truth in `PauseReason`'s docstring (with an optional pre-erase account-identity guard), and prevent re-entrant `runMigration` calls from corrupting the journal.

**Architecture:** Five small, independently-testable changes on the LillistCore Sync + Notifications seams. The notification re-install logic lives entirely on `NotificationScheduler` (it owns the notification center and the spec store); `MigrationCoordinator` only orchestrates by calling a single `restoreSteadyState(...)` method in its `finalize` phase, reading persisted morning-summary settings through an optionally-injected `PreferencesStore`. The journal staleness check is a pure value-type function on `MigrationJournal` consumed only by the iOS/macOS recovery sheets — `MigrationGate` keeps aborting headless callers on **any** non-idle journal. The reentrancy guard is a single read of `journal.isInFlight` at the top of `runMigration`.

**Tech Stack:** Swift 6.2, strict concurrency on the LillistCore source target, Core Data via `NSPersistentCloudKitContainer`, `UserNotifications`, Swift Testing (`import Testing`, `@Test`/`#expect`).

**Source findings:** `notif-1`, `sync-2`, `sync-5`, `sync-6`, `sync-8` (Roadmap P2 item #11).

---

## File Structure

| Path | Create/Modify | Single responsibility |
|------|---------------|-----------------------|
| `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift` | Modify | Add `restoreSteadyState(morningSummaryEnabled:hour:minute:)`; sweep every task that still owns a `NotificationSpec` row through `reconcile(taskID:)`, then (re)install or uninstall the morning summary. Make `cancelAllPending()` preserve the repeating morning-summary request. |
| `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift` | Modify | Add optional `preferencesStore` injection; call `notificationScheduler.restoreSteadyState(...)` in the `.finalizing` phase; add the `runMigration` reentrancy guard reading `journal.isInFlight`; add an optional pre-erase account-identity guard before `replaceICloudWithLocal`. |
| `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournal.swift` | Modify | Add `isStale(now:threshold:)` pure function; fix the stale "30s" docstring to reflect the real 300s quiesce timeout and the new threshold. |
| `Packages/LillistCore/Sources/LillistCore/Sync/PauseReason.swift` | Modify | Correct the `.accountChanged` docstring so it describes the *actual* behavior (status surface + optional pre-erase guard), not a non-existent abort flow. |
| `Apps/Lillist-iOS/Sources/App/LillistApp.swift` | Modify | Recovery sheet decision: only surface the sheet for a *stale* in-flight journal; keep gating fresh in-flight journals out (no behavior change for headless gate callers). |
| `Apps/Lillist-macOS/Sources/LillistApp.swift` | Modify | Same recovery-sheet staleness gating as iOS, kept verbatim. |
| `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerRestoreSteadyStateTests.swift` | Create | Tests for `restoreSteadyState` + `cancelAllPending` morning-summary preservation (notif-1). |
| `Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationCoordinatorRestoreTests.swift` | Create | Tests that `finalize` re-installs notifications + morning summary (sync-2), the reentrancy guard (sync-8), and the pre-erase account guard (sync-6). |
| `Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationJournalTests.swift` | Modify | Add `isStale` cases (sync-5). |

---

## Task 1: `NotificationScheduler.restoreSteadyState` + morning-summary-preserving `cancelAllPending` (notif-1)

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift` (add `tasksWithSpecs()` private helper near `tasksWithAllDayDefaults()` ~line 335; add `restoreSteadyState` near the Layer 4 API ~line 377; edit `cancelAllPending()` ~line 312).
- Create `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerRestoreSteadyStateTests.swift`.

- [ ] **Step 1: Write the failing test** — create `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerRestoreSteadyStateTests.swift` with the COMPLETE code below. It matches the neighbouring `NotificationSchedulerLayer4MorningSummaryTests.swift` framework (Swift Testing) and helpers (`TestStore.make()`, `NotificationSpecStore`, `FakeUserNotificationCenter`, `SnoozeRegistry`, `TaskStore`).

```swift
import Testing
import Foundation
import UserNotifications
@testable import LillistCore

@Suite("NotificationScheduler — restoreSteadyState (post-migration)")
struct NotificationSchedulerRestoreSteadyStateTests {

    /// Build a scheduler + the stores it sweeps, sharing one persistence stack.
    private func makeStack() async throws -> (PersistenceController, TaskStore, NotificationSpecStore, FakeUserNotificationCenter, NotificationScheduler) {
        let p = try await TestStore.make()
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )
        let taskStore = TaskStore(persistence: p)
        taskStore.notificationScheduler = scheduler
        return (p, taskStore, specs, fake, scheduler)
    }

    @Test("restoreSteadyState re-installs a per-task deadline notification from a surviving spec")
    func reinstallsPerTaskNotification() async throws {
        let (_, taskStore, _, fake, scheduler) = try await makeStack()
        // Create a task with a future time-bearing deadline; update() reconciles
        // and materializes a defaultDeadline spec + pending request.
        let id = try await taskStore.create(title: "Pay rent")
        let deadline = Date().addingTimeInterval(3600)
        try await taskStore.update(id: id) { d in
            d.deadline = deadline
            d.deadlineHasTime = true
        }
        // Simulate the pre-migration OS-level cancel: clear all pending.
        await scheduler.cancelAllPending()
        #expect(await fake.addedCount() == 0)

        // Post-migration steady-state restore (morning summary disabled here).
        await scheduler.restoreSteadyState(morningSummaryEnabled: false, hour: 9, minute: 0)

        let pending = await fake.pendingNotificationRequests()
        // Exactly the one per-task deadline request, no morning summary.
        #expect(pending.count == 1)
        #expect(pending[0].identifier.hasSuffix("#devA"))
        #expect(pending[0].content.userInfo["taskID"] as? String == id.uuidString)
        #expect(pending.contains { $0.identifier == MorningSummary.requestID } == false)
    }

    @Test("restoreSteadyState installs the morning summary when enabled")
    func installsMorningSummaryWhenEnabled() async throws {
        let (_, _, _, fake, scheduler) = try await makeStack()
        await scheduler.restoreSteadyState(morningSummaryEnabled: true, hour: 7, minute: 30)
        let pending = await fake.pendingNotificationRequests()
        let summary = pending.first { $0.identifier == MorningSummary.requestID }
        #expect(summary != nil)
        let trigger = summary?.trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.repeats == true)
        #expect(trigger?.dateComponents.hour == 7)
        #expect(trigger?.dateComponents.minute == 30)
    }

    @Test("restoreSteadyState uninstalls the morning summary when disabled")
    func uninstallsMorningSummaryWhenDisabled() async throws {
        let (_, _, _, fake, scheduler) = try await makeStack()
        await scheduler.installMorningSummary(hour: 9, minute: 0)
        #expect(await fake.pendingNotificationRequests().contains { $0.identifier == MorningSummary.requestID })
        await scheduler.restoreSteadyState(morningSummaryEnabled: false, hour: 9, minute: 0)
        #expect(await fake.pendingNotificationRequests().contains { $0.identifier == MorningSummary.requestID } == false)
    }

    @Test("cancelAllPending preserves the repeating morning-summary request")
    func cancelAllPendingPreservesMorningSummary() async throws {
        let (_, taskStore, _, fake, scheduler) = try await makeStack()
        await scheduler.installMorningSummary(hour: 9, minute: 0)
        let id = try await taskStore.create(title: "Call dentist")
        try await taskStore.update(id: id) { d in
            d.deadline = Date().addingTimeInterval(3600)
            d.deadlineHasTime = true
        }
        // Pre-condition: a per-task request and the morning summary both pending.
        #expect(await fake.pendingNotificationRequests().contains { $0.identifier == MorningSummary.requestID })
        #expect(await fake.pendingNotificationRequests().contains { $0.identifier.hasSuffix("#devA") })

        await scheduler.cancelAllPending()

        let pending = await fake.pendingNotificationRequests()
        // The repeating morning summary survives; the per-task one is gone.
        #expect(pending.count == 1)
        #expect(pending[0].identifier == MorningSummary.requestID)
    }
}
```

- [ ] **Step 2: Run the test, expect failure** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter NotificationSchedulerRestoreSteadyStateTests
  ```
  Expect a **compile failure**: `value of type 'NotificationScheduler' has no member 'restoreSteadyState'`. (The `cancelAllPending` test would also fail at runtime once it compiles, because the current implementation removes the morning summary too.)

- [ ] **Step 3: Implement the minimal change** — in `NotificationScheduler.swift`:

  3a. Replace the current `cancelAllPending()` (lines ~304–318) with this version that preserves the repeating morning summary (the morning summary is re-derived from preferences in `restoreSteadyState`, so dropping it here would leave it silently uninstalled across every migration):
  ```swift
    /// Plan 21: cancel every pending *per-task* Lillist notification at
    /// the OS level. The migration coordinator calls this before
    /// destructive sync-mode operations so a fire-time pointing at a
    /// since-deleted row doesn't leak past the wipe.
    ///
    /// The repeating morning-summary request is intentionally preserved:
    /// it is device-local, content-extension-filled at delivery, and not
    /// tied to any task row, so a migration never invalidates it.
    /// `restoreSteadyState(...)` re-derives it from preferences anyway.
    ///
    /// The full reconciliation path (`reconcile(taskID:)` per
    /// `NotificationSpec`) re-installs the per-task notifications after the
    /// store reaches its post-migration steady state.
    public func cancelAllPending() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending
            .map(\.identifier)
            .filter { $0 != MorningSummary.requestID }
        if !ids.isEmpty {
            await center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
  ```

  3b. Add a `tasksWithSpecs()` helper directly after the existing `tasksWithAllDayDefaults()` (after line ~345), mirroring its shape (own `viewContext.perform`, returns Sendable `[UUID]`):
  ```swift
    /// Every distinct task ID that still owns at least one
    /// `NotificationSpec` row. Used by `restoreSteadyState` to re-install
    /// per-task notifications after a migration cleared the OS-level
    /// pending set. Built like `tasksWithAllDayDefaults` — a single
    /// `viewContext.perform` returning a Sendable `[UUID]` snapshot.
    private func tasksWithSpecs() async -> [UUID] {
        let ctx = persistence.container.viewContext
        return await ctx.perform {
            let req = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
            req.predicate = NSPredicate(format: "task != nil")
            let specs = (try? ctx.fetch(req)) ?? []
            var seen = Set<UUID>()
            var out: [UUID] = []
            for spec in specs {
                guard let taskID = spec.task?.id else { continue }
                if seen.insert(taskID).inserted { out.append(taskID) }
            }
            return out
        }
    }
  ```

  3c. Add `restoreSteadyState` directly after `uninstallMorningSummary()` (after line ~401), in the Layer 4 API section:
  ```swift
    /// Post-migration steady-state restore. After a sync-mode migration
    /// the coordinator has OS-cancelled every per-task pending request
    /// (`cancelAllPending`). Once the store has reconfigured, the
    /// surviving `NotificationSpec` rows are the source of truth: sweep
    /// every task that still owns a spec back through `reconcile(taskID:)`
    /// to re-install its pending requests, then (re)install or uninstall
    /// the daily morning summary from the persisted preference.
    ///
    /// Idempotent: `reconcile` is a desired-vs-pending diff, so calling
    /// this twice yields the same pending set.
    public func restoreSteadyState(morningSummaryEnabled: Bool, hour: Int, minute: Int) async {
        for taskID in await tasksWithSpecs() {
            await reconcile(taskID: taskID)
        }
        if morningSummaryEnabled {
            await installMorningSummary(hour: hour, minute: minute)
        } else {
            await uninstallMorningSummary()
        }
    }
  ```

- [ ] **Step 4: Run the test, expect pass** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter NotificationSchedulerRestoreSteadyStateTests
  ```
  Expect: `Test Suite 'NotificationScheduler — restoreSteadyState (post-migration)' passed` with 4 tests passing, 0 failures.

- [ ] **Step 5: Commit** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSchedulerRestoreSteadyStateTests.swift && git commit -m "feat(notifications): add restoreSteadyState + preserve morning summary in cancelAllPending

Sweeps surviving NotificationSpec rows back through reconcile(taskID:)
and re-derives the morning summary from preferences so a sync-mode
migration restores the notification steady state instead of silently
dropping every reminder. cancelAllPending now leaves the device-local
repeating morning-summary request intact.

Closes notif-1 (partial; coordinator wiring in follow-up commit)."
  ```

---

## Task 2: Wire post-migration restore into `MigrationCoordinator.finalize` (notif-1, sync-2)

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift` (add the `preferencesStore` stored property right after the `notificationScheduler` member, before `syncModeStore`; add the matching init param after `notificationScheduler:` and before `syncModeStore:`; call `restoreSteadyState` in the **finalize** phase — the `// 8. finalize.` block, ~lines 249–257, between `emit(.finalizing)` and `try journal.clear()`).
- Create `Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationCoordinatorRestoreTests.swift`.

> **Anchor by structure, not line number.** `runMigration` is the shared hotspot file; each wave shifts it. The finalize block is the `// 8. finalize.` comment between `emit(.finalizing)` and `try journal.clear()`. Anchor on the `entry.state = .finalizing` / `emit(.finalizing)` statements rather than absolute line numbers, and keep the existing `// 8. finalize.` comment — do not paste a `// 7. finalize.` comment.

- [ ] **Step 1: Write the failing test** — create `Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationCoordinatorRestoreTests.swift` with the COMPLETE code below. It matches `MigrationCoordinatorTests.swift` (Swift Testing, `.serialized`, `liveSwapAllowed` gate, `PersistenceHost.make`, `QuarantineManager`, `FakeCloudKitZoneEraser`, `SyncModeStore`) and uses the notification helpers from Task 1.

```swift
import Testing
import Foundation
import CloudKit
import UserNotifications
@testable import LillistCore

@Suite("MigrationCoordinator — post-migration restore", .serialized)
struct MigrationCoordinatorRestoreTests {
    private static var liveSwapAllowed: Bool {
        Bundle.main.bundleIdentifier?.isEmpty == false
    }

    private static func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MigrationCoordinatorRestoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Disable Now restores per-task notifications and morning summary in finalize", .enabled(if: liveSwapAllowed))
    @MainActor
    func finalizeRestoresNotifications() async throws {
        let dir = Self.tempDir()
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        let host = try await PersistenceHost.make(initialMode: .iCloudSync, storeURL: storeURL)

        // Shared persistence so the scheduler/specs/prefs see the swapped
        // store. `PersistenceHost` is an actor, so `controller` is awaited
        // (see PersistenceHostTests.swift:44 for the same access pattern).
        let persistence = await host.controller
        let specs = NotificationSpecStore(persistence: persistence)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let scheduler = NotificationScheduler(
            persistence: persistence, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )
        let taskStore = TaskStore(persistence: persistence)
        taskStore.notificationScheduler = scheduler
        let prefs = PreferencesStore(persistence: persistence)
        try await prefs.update { p in
            p.morningSummaryEnabled = true
            p.morningSummaryHour = 8
            p.morningSummaryMinute = 0
        }

        // Seed a task with a per-task notification.
        let id = try await taskStore.create(title: "Submit report")
        try await taskStore.update(id: id) { d in
            d.deadline = Date().addingTimeInterval(7200)
            d.deadlineHasTime = true
        }
        #expect(await fake.addedCount() >= 1)

        let journal = InMemoryMigrationJournalStore()
        let quarantine = QuarantineManager(rootDirectory: dir)
        let bridge = CloudKitEventBridge()
        let quiesce = SyncQuiesceMonitor(bridge: bridge)
        let suite = "MigrationCoordinatorRestoreTests-\(UUID().uuidString)"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        let modeStore = SyncModeStore(suiteName: suite)
        await modeStore.setMode(.iCloudSync)

        let coordinator = MigrationCoordinator(
            host: host,
            journal: journal,
            quarantine: quarantine,
            zoneEraser: FakeCloudKitZoneEraser(),
            quiesceMonitor: quiesce,
            notificationScheduler: scheduler,
            syncModeStore: modeStore,
            preferencesStore: prefs
        )

        try await coordinator.beginDisable(strategy: .now, storeURL: storeURL)

        // cancelAllPending ran (pre-flight), then restoreSteadyState rebuilt it.
        let pending = await fake.pendingNotificationRequests()
        #expect(pending.contains { $0.identifier.hasSuffix("#devA") })
        let summary = pending.first { $0.identifier == MorningSummary.requestID }
        #expect(summary != nil)
        #expect((summary?.trigger as? UNCalendarNotificationTrigger)?.dateComponents.hour == 8)
        #expect(try journal.read() == .idle)
    }
}
```

- [ ] **Step 2: Run the test, expect failure** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter MigrationCoordinatorRestoreTests
  ```
  Expect a **compile failure**: `extra argument 'preferencesStore' in call` (the init has no such parameter yet). Also note: if `liveSwapAllowed` is false under `swift test`, the test is `.enabled(if:)`-skipped — the meta-coverage for the live swap path is owned by `store-swap-safety` (P0) per the review's `test-1`. This task's compile-time wiring is still verified by Step 4's full-package build.

- [ ] **Step 3: Implement the minimal change** — in `MigrationCoordinator.swift`:

  3a. Add the stored property after `notificationScheduler` (after line 37):
  ```swift
    private let notificationScheduler: NotificationScheduler?
    /// Optional source of the persisted morning-summary preference, read
    /// during `.finalizing` so the post-migration restore re-derives the
    /// morning summary from durable state rather than guessing.
    private let preferencesStore: PreferencesStore?
    private let syncModeStore: SyncModeStore
  ```

  3b. Add the init parameter (insert after the `notificationScheduler:` param, before `syncModeStore:`, lines ~53–54) and assign it:
  ```swift
        notificationScheduler: NotificationScheduler?,
        preferencesStore: PreferencesStore? = nil,
        syncModeStore: SyncModeStore,
  ```
  and in the body (after `self.notificationScheduler = notificationScheduler`):
  ```swift
        self.notificationScheduler = notificationScheduler
        self.preferencesStore = preferencesStore
        self.syncModeStore = syncModeStore
  ```

  3c. In the finalize phase of `runMigration` (the `// 8. finalize.` block, ~lines 249–257), insert the restore call between `emit(.finalizing)` and `journal.clear()`. Keep the existing `// 8. finalize.` comment and the already-awaited `await breadcrumb(...)` call — `breadcrumb(_:success:)` is `async` and awaited inline; do **not** change it:
  ```swift
            // 8. finalize.
            entry.state = .finalizing
            entry.lastHeartbeatAt = Date()
            try journal.write(entry)
            emit(.finalizing)

            // Re-install the post-migration notification steady state:
            // surviving per-task specs are reconciled and the morning
            // summary is re-derived from the persisted preference. The OS
            // pending set was cleared in step 1; this rebuilds it against
            // the now-reconfigured store.
            if let scheduler = notificationScheduler {
                let summary = try? await preferencesStore?.read()
                await scheduler.restoreSteadyState(
                    morningSummaryEnabled: summary?.morningSummaryEnabled ?? false,
                    hour: Int(summary?.morningSummaryHour ?? 9),
                    minute: Int(summary?.morningSummaryMinute ?? 0)
                )
            }

            try journal.clear()
            emit(.completed)
            await breadcrumb("sync mode change completed \(op.rawValue)")
  ```

  3d. Wire the new parameter at both app composition roots so production passes the real store. Both calls already end with `localStoreRowCount: localStoreRowCount` — KEEP that line; only insert `preferencesStore: preferencesStore,` after `notificationScheduler: scheduler,`. In `Apps/Lillist-iOS/Sources/App/AppEnvironment.swift` (the `MigrationCoordinator(` call at ~line 222):
  ```swift
        self.migrationCoordinator = MigrationCoordinator(
            host: persistenceHost,
            journal: migrationJournalStore,
            quarantine: quarantine,
            zoneEraser: LiveCloudKitZoneEraser(),
            quiesceMonitor: quiesceMonitor,
            notificationScheduler: scheduler,
            preferencesStore: preferencesStore,
            syncModeStore: syncModeStore,
            breadcrumbs: breadcrumbs,
            cloudKitContainerIdentifier: ckContainerID,
            localStoreRowCount: localStoreRowCount
        )
  ```
  And in `Apps/Lillist-macOS/Sources/AppEnvironment.swift` (the `MigrationCoordinator(` call at ~line 188) make the verbatim-equivalent edit:
  ```swift
        self.migrationCoordinator = MigrationCoordinator(
            host: persistenceHost,
            journal: migrationJournalStore,
            quarantine: quarantine,
            zoneEraser: LiveCloudKitZoneEraser(),
            quiesceMonitor: quiesceMonitor,
            notificationScheduler: scheduler,
            preferencesStore: preferencesStore,
            syncModeStore: syncModeStore,
            breadcrumbs: breadcrumbs,
            cloudKitContainerIdentifier: ckContainerID,
            localStoreRowCount: localStoreRowCount
        )
  ```
  > Both AppEnvironments name their `PreferencesStore` local `preferencesStore` (assigned to `self.preferencesStore`); pass that existing local — do not construct a second instance.

- [ ] **Step 4: Run the test, expect pass** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter MigrationCoordinatorRestoreTests
  ```
  Expect: the suite passes (1 test passing under an app-hosted runner, or skipped via `.enabled(if:)` under bare `swift test` — either is green). Then confirm the whole core suite still builds + passes:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore
  ```
  Expect: `Test Suite 'All tests' passed`, 0 failures, 0 unexpected warnings (warnings-as-errors).

- [ ] **Step 5: Verify the app targets still compile (init signature change)** — run (unsigned builds; the apps are the new init's callers):
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
  ```
  Expect: `** BUILD SUCCEEDED **` for both.

- [ ] **Step 6: Commit** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift Apps/Lillist-iOS/Sources/App/AppEnvironment.swift Apps/Lillist-macOS/Sources/AppEnvironment.swift Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationCoordinatorRestoreTests.swift && git commit -m "feat(sync): restore notification + morning-summary steady state in migration finalize

MigrationCoordinator now reads the persisted morning-summary preference
and calls NotificationScheduler.restoreSteadyState during the .finalizing
phase, so a completed sync-mode migration rebuilds per-task notifications
from surviving specs and re-derives the morning summary instead of leaving
the OS pending set empty.

Closes notif-1, sync-2."
  ```

---

## Task 3: `MigrationJournal.isStale(now:threshold:)` + docstring fix; recovery-sheet-only consumption (sync-5)

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournal.swift` (fix the doc-comment "30s" bullet in the struct header, ~lines 33–36; add `isStale` directly after the `isInFlight` computed property, ~line 124). Anchor the `isStale` insert on the verbatim `public var isInFlight: Bool { state != .idle }` line.
- Modify `Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationJournalTests.swift` (append `isStale` cases).
- Modify `Apps/Lillist-iOS/Sources/App/LillistApp.swift` and `Apps/Lillist-macOS/Sources/LillistApp.swift` (recovery `evaluate()` consumes `isStale`).

> **Design constraint (from the review):** Only the main-app recovery sheet acts on staleness. `MigrationGate.evaluate()` (the headless extension/CLI gate) must keep aborting on **any** `isInFlight` journal — do NOT touch `MigrationGate.swift`. The threshold must sit **above** the 300s `hardTimeout` of the quiesce wait (`MigrationCoordinator.runMigration` step 6: `waitForQuiesce(minQuietWindow: 5, hardTimeout: 300)`), so an in-progress (not crashed) migration is never misclassified as stale.

- [ ] **Step 1: Write the failing test** — append these `@Test` cases inside the existing `MigrationJournalTests` struct in `Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationJournalTests.swift` (Swift Testing; insert just before the closing `}` of the struct, after the `inMemoryRoundTrip` test):

```swift
    @Test("Idle journal is never stale")
    func idleNeverStale() {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(MigrationJournal.idle.isStale(now: now, threshold: 600) == false)
    }

    @Test("In-flight journal with a recent heartbeat is not stale")
    func freshInFlightNotStale() {
        let now = Date(timeIntervalSince1970: 10_000)
        let j = MigrationJournal(
            state: .awaitingSync,
            operation: .replaceLocalWithICloud,
            startedAt: now.addingTimeInterval(-120),
            lastHeartbeatAt: now.addingTimeInterval(-120)
        )
        // 120s < 600s threshold → still considered live.
        #expect(j.isStale(now: now, threshold: 600) == false)
    }

    @Test("In-flight journal whose heartbeat predates the threshold is stale")
    func crashedInFlightIsStale() {
        let now = Date(timeIntervalSince1970: 10_000)
        let j = MigrationJournal(
            state: .reconfiguringStore,
            operation: .disableNow,
            startedAt: now.addingTimeInterval(-1_000),
            lastHeartbeatAt: now.addingTimeInterval(-1_000)
        )
        // 1000s > 600s threshold → crashed/abandoned, recoverable.
        #expect(j.isStale(now: now, threshold: 600) == true)
    }

    @Test("In-flight journal with no heartbeat falls back to startedAt for staleness")
    func missingHeartbeatUsesStartedAt() {
        let now = Date(timeIntervalSince1970: 10_000)
        let j = MigrationJournal(
            state: .preparing,
            operation: .syncFirstThenDisable,
            startedAt: now.addingTimeInterval(-1_000),
            lastHeartbeatAt: nil
        )
        #expect(j.isStale(now: now, threshold: 600) == true)
    }

    @Test("In-flight journal with neither heartbeat nor startedAt is treated as stale")
    func missingBothTimestampsIsStale() {
        let now = Date(timeIntervalSince1970: 10_000)
        let j = MigrationJournal(state: .failed)
        #expect(j.isStale(now: now, threshold: 600) == true)
    }

    @Test("Default threshold sits above the 300s quiesce hard timeout")
    func defaultThresholdAboveQuiesceTimeout() {
        let now = Date(timeIntervalSince1970: 10_000)
        // A migration that has been running just over the 300s quiesce
        // timeout but under the default threshold is NOT yet stale.
        let j = MigrationJournal(
            state: .awaitingSync,
            operation: .replaceLocalWithICloud,
            startedAt: now.addingTimeInterval(-310),
            lastHeartbeatAt: now.addingTimeInterval(-310)
        )
        #expect(j.isStale(now: now) == false)
        #expect(MigrationJournal.staleThreshold > 300)
    }
```

- [ ] **Step 2: Run the test, expect failure** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter MigrationJournalTests
  ```
  Expect a **compile failure**: `value of type 'MigrationJournal' has no member 'isStale'` and `type 'MigrationJournal' has no member 'staleThreshold'`.

- [ ] **Step 3: Implement the minimal change** — in `MigrationJournal.swift`:

  3a. Fix the misleading heartbeat doc-comment. Replace the bullet at lines ~33–36:
  ```swift
    /// 3. **Heartbeat semantics.** A crashed process leaves the journal
    ///    non-idle. Recovery uses `lastHeartbeatAt` against
    ///    `staleThreshold` (well above the 300s sync-quiesce hard
    ///    timeout) to classify the state as "stale and recoverable"
    ///    instead of "another in-flight migration; back off." Only the
    ///    main-app recovery sheet acts on staleness — `MigrationGate`
    ///    still aborts headless callers on any non-idle journal.
  ```

  3b. Add `staleThreshold` and `isStale(now:threshold:)` directly after the `isInFlight` computed property (~line 124):
  ```swift
    /// Whether the journal represents an in-flight (or crashed)
    /// migration that the app should not start a new one on top of.
    public var isInFlight: Bool { state != .idle }

    /// Default staleness window. Deliberately above the 300s
    /// `waitForQuiesce` hard timeout in `MigrationCoordinator` so a
    /// genuinely-running migration (which can legitimately sit in
    /// `.awaitingSync` for up to 5 minutes) is never misclassified as
    /// crashed. 600s = 2× the quiesce ceiling, leaving slack for the
    /// surrounding phases.
    public static let staleThreshold: TimeInterval = 600

    /// Whether an in-flight journal is *stale* — i.e. its owning process
    /// almost certainly crashed rather than still running. An idle
    /// journal is never stale. Staleness is measured from
    /// `lastHeartbeatAt` when present, falling back to `startedAt`, and
    /// finally treating a timestamp-less in-flight journal as stale
    /// (it can't be a live heartbeat-emitting migration).
    ///
    /// Consumed **only** by the main-app recovery sheet to decide whether
    /// to offer restore-from-backup. `MigrationGate` ignores staleness and
    /// aborts headless callers on any non-idle journal.
    public func isStale(now: Date = Date(), threshold: TimeInterval = MigrationJournal.staleThreshold) -> Bool {
        guard isInFlight else { return false }
        guard let reference = lastHeartbeatAt ?? startedAt else { return true }
        return now.timeIntervalSince(reference) > threshold
    }
  ```

- [ ] **Step 4: Run the test, expect pass** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter MigrationJournalTests
  ```
  Expect: `Test Suite 'MigrationJournal + MigrationJournalStore' passed` with all original tests plus the 6 new `isStale` tests passing, 0 failures.

- [ ] **Step 5: Consume `isStale` in the recovery sheets (main app only).** In `Apps/Lillist-iOS/Sources/App/LillistApp.swift`, the `evaluate()` method currently surfaces the sheet for any in-flight journal (the `if let journal, journal.isInFlight { recoveryJournal = journal; return }` block, ~lines 248–252). Tighten it so a *fresh* (non-stale) in-flight journal is left to finish — the gate already blocks new work — while a *stale* (crashed) journal triggers recovery:
  ```swift
        let journal = try? environment.migrationJournalStore.read()
        if let journal, journal.isInFlight {
            // Only offer recovery for a *stale* (crashed) migration. A
            // fresh in-flight journal belongs to a migration that may still
            // be completing in another process/launch; surfacing recovery
            // would race it. The MigrationGate keeps blocking new work
            // either way.
            if journal.isStale() {
                recoveryJournal = journal
            }
            return
        }
  ```
  Then make the verbatim-equivalent edit in `Apps/Lillist-macOS/Sources/LillistApp.swift` (the macOS `evaluate()` has the same `if let journal, journal.isInFlight { recoveryJournal = journal; return }` shape near line ~181 — confirm by grepping `journal.isInFlight` in that file first, then apply the identical block).

- [ ] **Step 6: Verify both apps still compile** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
  ```
  Expect: `** BUILD SUCCEEDED **` for both.

- [ ] **Step 7: Commit** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournal.swift Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationJournalTests.swift Apps/Lillist-iOS/Sources/App/LillistApp.swift Apps/Lillist-macOS/Sources/LillistApp.swift && git commit -m "feat(sync): add MigrationJournal.isStale and gate recovery sheet on it

isStale(now:threshold:) classifies a crashed migration (heartbeat older
than the 600s threshold, well above the 300s quiesce timeout) as
recoverable. Only the main-app recovery sheet acts on it; MigrationGate
still aborts headless callers on any non-idle journal. Fixes the stale
'30s' heartbeat docstring.

Closes sync-5."
  ```

---

## Task 4: `PauseReason` docstring correction + optional pre-erase account-identity guard (sync-6)

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/Sync/PauseReason.swift` (correct the `.accountChanged` doc-comment, ~lines 13–15).
- Modify `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift` (add optional `accountStateProvider` injection — the stored property goes after `localStoreRowCount` and the init param after `localStoreRowCount:`; add the pre-erase guard as the first statement inside the `// 6. cloudkit-side mutation` `if op == .replaceICloudWithLocal {` block, before `zoneEraser.eraseManagedZones`).
- Add tests to `Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationCoordinatorRestoreTests.swift` (created in Task 2).

> **Why:** The current `.accountChanged` docstring claims "`MigrationCoordinator` aborts any active op and surfaces a dedicated recovery flow." No such code exists — the coordinator never reads account identity. This is a truthfulness defect (the review's `sync-6`). The fix is (a) correct the docstring to describe real behavior, and (b) add the *optional* guard the docstring used to lie about: refuse the irreversible CloudKit zone erase when the account has changed out from under us.

- [ ] **Step 1: Write the failing test** — append this `@Test` to `MigrationCoordinatorRestoreTests.swift` (inside the same `@Suite` struct, before its closing `}`):

```swift
    @Test("Replace iCloud with Local aborts before erase when the account changed", .enabled(if: liveSwapAllowed))
    @MainActor
    func abortsEraseOnAccountChange() async throws {
        let dir = Self.tempDir()
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        let host = try await PersistenceHost.make(initialMode: .localOnly, storeURL: storeURL)
        let journal = InMemoryMigrationJournalStore()
        let quarantine = QuarantineManager(rootDirectory: dir)
        let fakeEraser = FakeCloudKitZoneEraser()
        let bridge = CloudKitEventBridge()
        let quiesce = SyncQuiesceMonitor(bridge: bridge)
        let suite = "MigrationCoordinatorRestoreTests-\(UUID().uuidString)"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        let modeStore = SyncModeStore(suiteName: suite)
        await modeStore.setMode(.localOnly)

        let coordinator = MigrationCoordinator(
            host: host,
            journal: journal,
            quarantine: quarantine,
            zoneEraser: fakeEraser,
            quiesceMonitor: quiesce,
            notificationScheduler: nil,
            syncModeStore: modeStore,
            accountStateProvider: { .accountChanged }
        )

        await #expect(throws: LillistError.self) {
            try await coordinator.beginEnable(direction: .replaceICloud, storeURL: storeURL)
        }
        // The irreversible erase must NOT have run.
        #expect(await fakeEraser.callCount == 0)
        // The journal records the failure for the recovery sheet.
        #expect(try journal.read().state == .failed)
    }

    @Test("Replace iCloud with Local proceeds to erase when the account is available", .enabled(if: liveSwapAllowed))
    @MainActor
    func proceedsWhenAccountAvailable() async throws {
        let dir = Self.tempDir()
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        let host = try await PersistenceHost.make(initialMode: .localOnly, storeURL: storeURL)
        let journal = InMemoryMigrationJournalStore()
        let quarantine = QuarantineManager(rootDirectory: dir)
        let fakeEraser = FakeCloudKitZoneEraser()
        let bridge = CloudKitEventBridge()
        let quiesce = SyncQuiesceMonitor(bridge: bridge)
        let suite = "MigrationCoordinatorRestoreTests-\(UUID().uuidString)"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        let modeStore = SyncModeStore(suiteName: suite)
        await modeStore.setMode(.localOnly)

        let coordinator = MigrationCoordinator(
            host: host,
            journal: journal,
            quarantine: quarantine,
            zoneEraser: fakeEraser,
            quiesceMonitor: quiesce,
            notificationScheduler: nil,
            syncModeStore: modeStore,
            accountStateProvider: { .available }
        )

        try await coordinator.beginEnable(direction: .replaceICloud, storeURL: storeURL)
        #expect(await fakeEraser.callCount == 1)
        #expect(try journal.read() == .idle)
    }
```

- [ ] **Step 2: Run the test, expect failure** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter MigrationCoordinatorRestoreTests
  ```
  Expect a **compile failure**: `extra argument 'accountStateProvider' in call`.

- [ ] **Step 3: Implement the minimal change.**

  3a. In `PauseReason.swift`, replace the `.accountChanged` doc-comment (~lines 13–15) with truthful text:
  ```swift
    /// The signed-in iCloud account changed since the last sync. The
    /// status badge surfaces this and `PauseExplainerDialog` explains it;
    /// when an account change is detected, `MigrationCoordinator` refuses
    /// the irreversible iCloud zone erase (the `replaceICloudWithLocal`
    /// path) and leaves the journal `.failed` for the recovery sheet,
    /// rather than wiping the wrong account's data.
    case accountChanged
  ```

  3b. In `MigrationCoordinator.swift`, add a `Sendable` provider closure type alias and stored property + init param. Add the type alias just above the `@MainActor public final class MigrationCoordinator {` declaration (~line 30):
  ```swift
/// Closure that reports the current iCloud account state. Injected so
/// `MigrationCoordinator` can refuse a destructive erase when the
/// account changed out from under us without depending on `CloudKit`
/// directly (keeps the type unit-testable). Returns `nil` to mean
/// "unknown — proceed" (the conservative default keeps current behavior).
public typealias AccountStateProviding = @Sendable () async -> iCloudAccountState?
  ```
  Add the stored property after the existing `localStoreRowCount` property (~lines 44–48), so it sits last in the member list:
  ```swift
    /// Returns the current count of user-visible task rows in the live
    /// store. Used to precondition a non-empty local store before the
    /// irreversible `replaceICloudWithLocal` erase. Injected so the
    /// executing tests can drive empty/non-empty without a live store.
    private let localStoreRowCount: @Sendable () async -> Int
    /// Optional account-identity probe consulted before the irreversible
    /// CloudKit zone erase. `nil` → no pre-flight (legacy behavior).
    private let accountStateProvider: AccountStateProviding?
  ```
  Add the init param after `localStoreRowCount:` (~line 62) and assign it:
  ```swift
        cloudKitContainerIdentifier: String = StoreConfiguration.defaultCloudKitContainerIdentifier,
        localStoreRowCount: @escaping @Sendable () async -> Int = { 1 },
        accountStateProvider: AccountStateProviding? = nil
    ) {
  ```
  and in the init body (after `self.localStoreRowCount = localStoreRowCount`):
  ```swift
        self.localStoreRowCount = localStoreRowCount
        self.accountStateProvider = accountStateProvider
    }
  ```

  3c. Add the pre-erase guard inside the `if op == .replaceICloudWithLocal {` block in `runMigration` (the `// 6. cloudkit-side mutation` step, ~lines 225–237), as the first thing inside that block — *before* setting `entry.state = .mutatingCloudKit`. Keep the existing `// 6. cloudkit-side mutation` comment:
  ```swift
            // 6. cloudkit-side mutation (only for replaceICloudWithLocal).
            if op == .replaceICloudWithLocal {
                // Pre-flight: never erase if the signed-in account changed
                // out from under us — that would wipe the wrong account's
                // zone. This throws into the catch below, which records
                // `.failed` for the recovery sheet (PauseReason.accountChanged).
                if let provider = accountStateProvider,
                   await provider() == .accountChanged {
                    throw LillistError.storeUnavailable(
                        reason: "iCloud account changed; aborting before erase."
                    )
                }
                entry.state = .mutatingCloudKit
                entry.lastHeartbeatAt = Date()
                try journal.write(entry)
                emit(.erasingICloud(progress: 0))
                _ = try await zoneEraser.eraseManagedZones(
                    in: cloudKitContainerIdentifier,
                    progress: { [weak self] fraction in
                        await MainActor.run { self?.emit(.erasingICloud(progress: fraction)) }
                    }
                )
            }
  ```

- [ ] **Step 4: Run the test, expect pass** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter MigrationCoordinatorRestoreTests
  ```
  Expect: the suite passes (account-guard tests pass under an app-hosted runner, or `.enabled(if:)`-skip under bare `swift test`). Then run the full core suite to confirm no regression:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore
  ```
  Expect: `Test Suite 'All tests' passed`, 0 failures.

- [ ] **Step 5: Commit** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/LillistCore/Sync/PauseReason.swift Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationCoordinatorRestoreTests.swift && git commit -m "feat(sync): correct PauseReason docstring and guard erase on account change

The .accountChanged docstring claimed MigrationCoordinator aborts on
account change, which was untrue. Corrected the docstring and made it
true: an optional injected account-state provider lets the coordinator
refuse the irreversible replaceICloudWithLocal zone erase when the
signed-in account changed, recording .failed for the recovery sheet.

Closes sync-6."
  ```

---

## Task 5: `runMigration` reentrancy guard reading `journal.isInFlight` (sync-8)

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift` (guard at the very top of `runMigration`, before the first `breadcrumb`/`emit`).
- Add a test to `Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationCoordinatorRestoreTests.swift`.

> **Why:** Although the coordinator is `@MainActor`, `runMigration` has multiple `await` suspension points. A second `beginEnable`/`beginDisable` call (e.g. a double-tap, or a programmatic retry while one is mid-flight) can interleave at a suspension and clobber the journal `entry` written by the first run, corrupting recovery state. A cheap synchronous-read guard at the top — *before* any suspension — rejects a re-entrant call when the journal is already non-idle.

> **One guard only.** `runMigration` currently has **no** explicit reentrancy guard — it relies on `journal.isInFlight` being checked by callers. Add exactly one synchronous guard as the function's first statement. Re-Read `runMigration` first: if a re-Read shows an entry guard already present (e.g. added by an earlier wave), reconcile to a single guard rather than duplicating it. Do **not** touch `MigrationGate` — headless callers still abort on any in-flight journal.

- [ ] **Step 1: Write the failing test** — append this `@Test` to `MigrationCoordinatorRestoreTests.swift` (inside the same `@Suite` struct). It seeds an already-in-flight journal and asserts a fresh migration attempt is rejected without mutating that journal or running the eraser.

```swift
    @Test("runMigration refuses to start when the journal is already in flight", .enabled(if: liveSwapAllowed))
    @MainActor
    func rejectsReentrantMigration() async throws {
        let dir = Self.tempDir()
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        let host = try await PersistenceHost.make(initialMode: .localOnly, storeURL: storeURL)
        // Journal seeded as already mid-migration by another caller.
        let preexisting = MigrationJournal(
            state: .reconfiguringStore,
            operation: .replaceLocalWithICloud,
            startedAt: Date(),
            lastHeartbeatAt: Date(),
            previousMode: .localOnly
        )
        let journal = InMemoryMigrationJournalStore(initial: preexisting)
        let quarantine = QuarantineManager(rootDirectory: dir)
        let fakeEraser = FakeCloudKitZoneEraser()
        let bridge = CloudKitEventBridge()
        let quiesce = SyncQuiesceMonitor(bridge: bridge)
        let suite = "MigrationCoordinatorRestoreTests-\(UUID().uuidString)"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        let modeStore = SyncModeStore(suiteName: suite)
        await modeStore.setMode(.localOnly)

        let coordinator = MigrationCoordinator(
            host: host,
            journal: journal,
            quarantine: quarantine,
            zoneEraser: fakeEraser,
            quiesceMonitor: quiesce,
            notificationScheduler: nil,
            syncModeStore: modeStore
        )

        await #expect(throws: LillistError.self) {
            try await coordinator.beginEnable(direction: .replaceICloud, storeURL: storeURL)
        }
        // The pre-existing journal is untouched (not clobbered to .preparing/.failed).
        #expect(try journal.read() == preexisting)
        // No destructive work ran.
        #expect(await fakeEraser.callCount == 0)
        #expect(await host.currentMode == .localOnly)
    }
```

- [ ] **Step 2: Run the test, expect failure** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter MigrationCoordinatorRestoreTests
  ```
  Expect failure: without the guard, `beginEnable` proceeds, overwrites the journal to `.preparing` and beyond, so `throws` is not satisfied and `journal.read() == preexisting` fails (the journal was clobbered). The expectation `await #expect(throws:)` reports the missing error.

- [ ] **Step 3: Implement the minimal change** — add the guard as the first statement of `runMigration`, before the existing `await breadcrumb(...)` call (~line 165). `breadcrumb(_:success:)` is `async` and awaited inline — keep the `await`:
  ```swift
    private func runMigration(op: ModeTransitionOp, targetMode: SyncMode, storeURL: URL) async throws {
        // Reentrancy guard: although @MainActor serializes execution,
        // runMigration suspends at every `await`, so a second begin* call
        // can interleave and clobber the in-flight journal entry. Reject
        // any new migration while one is already recorded as in flight.
        // Read synchronously *before* the first suspension so the check
        // can't race itself. Leaves the existing journal untouched.
        if let current = try? journal.read(), current.isInFlight {
            throw LillistError.storeUnavailable(
                reason: "A sync-mode migration is already in progress."
            )
        }
        await breadcrumb("sync mode change start \(op.rawValue)")
  ```

- [ ] **Step 4: Run the test, expect pass** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter MigrationCoordinatorRestoreTests
  ```
  Expect: all `MigrationCoordinatorRestoreTests` (restore, account-guard, reentrancy) pass under an app-hosted runner, or `.enabled(if:)`-skip cleanly under bare `swift test`. Then run the full suite:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore
  ```
  Expect: `Test Suite 'All tests' passed`, 0 failures. The original `MigrationCoordinatorTests` (`disableNow`, `replaceICloudWithLocal`, `resumeReadsJournal`) must still pass — they start from an idle journal so the guard never trips.

- [ ] **Step 5: Commit** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationCoordinatorRestoreTests.swift && git commit -m "fix(sync): reject re-entrant runMigration when a journal is already in flight

runMigration suspends at every await, so a double begin* call could
interleave and clobber the in-flight journal entry, corrupting recovery
state. Added a synchronous isInFlight read at the top (before any
suspension) that throws storeUnavailable and leaves the existing journal
untouched.

Closes sync-8."
  ```

---

## Self-review checklist

Each finding from the review's P2 item #11 is covered by a named task above:

- [ ] **`notif-1`** (post-migration per-task notification re-install) — **Task 1** (`NotificationScheduler.restoreSteadyState` sweeps surviving `NotificationSpec` rows through `reconcile(taskID:)`, plus `cancelAllPending` preserves the morning summary) **and Task 2** (coordinator invokes it in `.finalizing`).
- [ ] **`sync-2`** (post-migration morning-summary restore from persisted preferences) — **Task 2** (coordinator reads `PreferencesStore.read()` and passes `morningSummaryEnabled/hour/minute` into `restoreSteadyState`).
- [ ] **`sync-5`** (`MigrationJournal.isStale`, threshold above the 300s quiesce timeout, recovery-sheet-only consumption, `MigrationGate` unchanged) — **Task 3** (`isStale(now:threshold:)` + `staleThreshold = 600`; consumed only in iOS/macOS `evaluate()`; `MigrationGate.swift` untouched).
- [ ] **`sync-6`** (correct `PauseReason` docstring + optional pre-erase account-identity check) — **Task 4** (truthful `.accountChanged` docstring + optional `accountStateProvider` guard before `replaceICloudWithLocal`'s erase).
- [ ] **`sync-8`** (coordinator reentrancy guard reading `journal.isInFlight` at the top of `runMigration`) — **Task 5** (synchronous `isInFlight` guard before the first suspension point).

**Strengths preserved (not refactored away):**
- Synchronous same-actor AsyncStream continuation registration on the Sync monitors is untouched (no changes to `AccountStateMonitor`/`CloudKitEventBridge`/`SyncStatusMonitor`).
- Calendar-based date math: `isStale` uses `Date.timeIntervalSince` only for a duration comparison (a true absolute-time elapsed measure, not calendar arithmetic), consistent with the existing heartbeat semantics.
- DTO boundary: every new public API (`restoreSteadyState`, `isStale`, `AccountStateProviding`) traffics in value types (`Bool`, `Int`, `Date`, `iCloudAccountState`); no `NSManagedObject` escapes `LillistCore`.
- `MigrationGate` headless-abort behavior is explicitly preserved (staleness lives only in the main-app recovery path).
- New optional init parameters default to `nil`, so existing constructions and the `store-swap-safety` plan's coordinator edits remain source-compatible.
