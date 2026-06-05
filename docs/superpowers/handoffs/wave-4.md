# Wave 4 handoff (P1/P2)
From: Wave 4 executor   To: Wave 5 executor   Date: 2026-06-04

## What landed
- **concurrency-stress-tests** (test-only): commits `f093884`..`805291f`; closed
  conc-2, conc-3, stores-4, notif-3, notif-9, test-3. Four stress suites +
  engineering-notes. Two beyond-plan findings handled honestly (see below).
- **migration-adjacent-correctness**: commits `af7c29f`..`3a676d8`; closed notif-1,
  sync-2, sync-5, sync-6, sync-8. iOS + macOS apps build clean.
- **background-context-seam**: commits `5caef1e`..`45b7d7d`; closed threading-1,
  persist-4, conc-5, notif-7, persist-1. iOS + macOS apps build clean.
- Final state: **805 LillistCore tests in 173 suites green, warning-free**; both
  apps build unsigned; iOS app-hosted target compiles (`build-for-testing`).

## Shared files I moved (anchor by STRUCTURE — line numbers are as-of-landing)
- `Sync/MigrationCoordinator.swift`: now has a **reentrancy guard** as the first
  statement of `runMigration` (synchronous `journal.read().isInFlight` → throws);
  an optional `preferencesStore: PreferencesStore?` member/param (after
  `notificationScheduler`); an optional `accountStateProvider: AccountStateProviding?`
  member/param (after `localStoreRowCount`) + a pre-erase account guard inside the
  `// 6. cloudkit-side mutation` block; and a `restoreSteadyState(...)` call in the
  `// 8. finalize.` block between `emit(.finalizing)` and `journal.clear()`. The
  catch block (sets `.failed`, breadcrumb success:false) is unchanged.
- `Notifications/NotificationScheduler.swift`: `cancelAllPending` now preserves
  `MorningSummary.requestID`; added `private func tasksWithSpecs()` (after
  `tasksWithAllDayDefaults`) and `public func restoreSteadyState(...)` (after
  `uninstallMorningSummary`, in the Layer-4 section).
- `Sync/MigrationJournal.swift`: added `static let staleThreshold: TimeInterval = 600`
  and `func isStale(now:threshold:)` after `isInFlight`; fixed the stale "30s"
  heartbeat docstring.
- `Stores/TaskStore.swift`: `purgeAll` rewritten to a background-context batch delete
  via `batchPurge(predicateFormat:arguments:)` (NOT `predicate:` — NSPredicate is
  non-Sendable); `countDescendants` **deleted**; `context.rollback()` added as the
  first line of the catch in all 8 mutators (create/update/archive/unarchive/
  hardDelete/reparent/softDelete/restore) — `transition` and `purgeAll` intentionally
  excluded.
- `Persistence/PersistenceController.swift`: added `makeBackgroundContext()` after
  `localTaskRowCount()`.
- `Export/Exporter.swift` (`buildDocument`) + `Export/Importer.swift` (`apply`):
  both now use `makeBackgroundContext()`; Exporter writes asset files OUTSIDE
  `perform`; Importer rolls back on save failure.
- `Persistence/AutoPurgeJob.swift` (`run`): background-context batch delete via
  `CascadeReaper`.
- **Created**: `Persistence/CascadeReaper.swift` (+`batchDelete(objectIDs:in:)`),
  `Persistence/HistoryPruner.swift`.
- iOS + macOS `AppEnvironment.swift`: `MigrationCoordinator(...)` call gained
  `preferencesStore: preferencesStore`; `bootstrap()` now fires
  `HistoryPruner(...).sweep()` (fire-and-forget) right after the launch
  `autoPurgeJob.run()`.
- iOS + macOS `LillistApp.swift`: recovery-sheet `evaluate()` now gates
  `recoveryJournal = journal` behind `journal.isStale()`.
- `Apps/Lillist-iOS/project.yml` + pbxproj: `Lillist-iOSAppHostedTests` gained
  `StoreReconfigureConcurrencyTests.swift`, `MigrationCoordinatorRestoreTests.swift`,
  and `Helpers/FakeUserNotificationCenter.swift` (one coordinated `xcodegen generate`).
- `docs/engineering-notes.md`: two new sections (concurrency invariants; single-context
  design + background seam).

## Assumptions I invalidated / established for later waves
- **`CascadeReaper` exists** (`objectIDs(forDeleting:)` + `batchDelete(objectIDs:in:)`,
  per-entity leaf-first). `export-import-robustness` / any future batch-delete work
  should reuse it, not re-derive the cascade walk.
- **`makeBackgroundContext()` exists** and is the sanctioned seam for bulk Core Data
  work. `performance-budgets-and-paging` / `export-import-robustness` should route
  bulk reads/writes through it, never fan interactive mutations onto private contexts.
- **`MigrationCoordinator` init signature grew** two optional params (`preferencesStore`,
  `accountStateProvider`), both defaulted `nil` — source-compatible. `recovery-hardening`
  (Wave 7) adds its disk-check to store-swap-safety's precondition, NOT a new param-less
  pre-flight; it can inject via the existing pattern if needed.
- **`runMigration` now has ONE reentrancy guard** at its first statement. Do not add a
  second; `recovery-hardening`/`observability-logging` must reconcile onto it.
- **`HistoryPruner.sweep` is wired** into both `bootstrap()`s — do NOT re-wire it.
- **`MigrationJournal.isStale` is consumed ONLY by the main-app recovery sheets.**
  `MigrationGate` still aborts headless callers on any non-idle journal — keep it that way.
- **`FakeUserNotificationCenter.add` is now upsert-faithful** (replaces a pending request
  with a matching identifier) — matches the real `UNUserNotificationCenter`. Any future
  notification test relies on this; do not revert it to append.
- **Live-swap-gated tests skip under `swift test`** and only execute via
  `Lillist-iOSAppHostedTests` on a code-signed host. `StoreReconfigureConcurrencyTests`,
  `MigrationCoordinatorRestoreTests` are wired there but their executing proof is
  deferred to CI / a dev Mac (per the index's executor-confirm callout). `ci-and-build-posture`
  (Wave 7) runs the app-hosted target — it will be the first to actually execute them.

## Residuals I opened / closed
- **Closed**: conc-2/3, stores-4, notif-1/3/7/9, sync-2/5/6/8, threading-1, persist-1/4, conc-5, test-3.
- **#3** (un-cancelled OS-level pending `UNNotificationRequest`s on purge): **documented**
  as an acknowledged limitation in engineering-notes (the purge reaps `NotificationSpec`
  rows but not the OS-scheduled banners). Still a named follow-up.
- **#11** (parallel-test flakes): **third manifestation observed** —
  `TaskStoreRecurrenceSpawnTests."After-completion series spawns at completedAt + interval"`
  rarely trips its `< 2.0s` wall-clock tolerance under heavy load (passes in isolation /
  on re-run). Same root cause + Wave-7 remedy. Recorded in the index residual #11 entry.
- **Plan defect found & fixed (not silently)**: `background-context-seam`'s
  `NSBatchDeleteRequest(objectIDs:)` over the mixed-entity cascade closure crashes at
  runtime (`mismatched objectIDs`); resolved with per-entity `CascadeReaper.batchDelete`.
- **Plan premise disproven (not papered over)**: `concurrency-stress-tests` Task 2's
  "revert-check bites" — the AsyncStream suite does NOT detect a deferred-`Task { register }`
  regression (actor scheduling masks Race A in the `recordEvent` seam). Suite kept for the
  fan-out/no-starvation/churn properties it genuinely guards; docs corrected.

## Pre-flight the next executor should run
- `git log --oneline main | head -25` — confirm Wave-4 commits present (`f093884`..`45b7d7d`).
- `swift test --package-path Packages/LillistCore` — expect ~805 green; a single
  `TaskStoreRecurrenceSpawnTests`/`SyncQuiesceMonitorTests`/`ParitySuiteTests`
  SIGSEGV-or-timing flake is residual #11 — re-run before treating as real.
- Re-Read before edits: `Stores/TaskStore.swift` (8 mutators now have rollback;
  `purgeAll` is batch-based; `countDescendants` gone), `Persistence/PersistenceController.swift`
  (`makeBackgroundContext`), `Sync/MigrationCoordinator.swift` (reentrancy + 2 new params).
- Wave 5 = `crash-reporter-privacy` (fully isolated) + `app-layer-test-rehab` (introduces
  `GatedPersistenceResolver`; **must precede** `extension-persistence-unification`; starts
  the iOS `project.yml` chain — note Wave 4 already added 3 test files to
  `Lillist-iOSAppHostedTests`, so re-Read `project.yml` before editing it).
