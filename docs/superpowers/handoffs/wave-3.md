# Wave 3 handoff (P1)
From: Wave 3 executor   To: Wave 4 executor   Date: 2026-06-04 (backfilled)

## What landed
- **cloudkit-convergence**: commits `795290c`..`cc9e581`; 760 LillistCore tests
  green, iOS app builds clean. Closed persist-2, conc-3, notif-2, persist-5.
- **resolve-inert-features**: commits `a2e4ac1`..`aac4435`; 767 tests green, iOS
  + macOS apps build clean. Closed persist-6, ios-1/4, macos-2, logs-2, crumbs-3,
  cli-1.

## Shared files I moved (anchor by structure — line numbers as-of-landing)
- `Persistence/PersistenceController.swift`: added
  `localTransactionAuthor` (`"Lillist.app"`, static), stamped on
  `viewContext.transactionAuthor`/`.name`; documented `mergeByPropertyObjectTrump`.
- **Created**: `PersistentHistoryTokenStore`, `RemoteChangeReconciler`,
  `CloudKitErrorClassifier`. Well-known `AppPreferences.singletonID` +
  `normalizeSingletons`.
- `Notifications/NotificationSpecStore.swift`: **`add` now enforces one default
  spec per `(task, kind)`** (`.defaultStart`/`.defaultDeadline`) and self-heals
  duplicates (commit `893c359`, ~lines 34–65). Offset/nudge kinds stay multi-instance.
- iOS `AppEnvironment.bootstrap()`: wired the remote-change reconciler +
  singleton normalization (~line 300s); AutoPurgeJob run at launch (both
  platforms) + iOS `BGProcessingTask` (`BackgroundPurgeSchedule` constant).
- `PauseReasonClassifier` driven into the `pauseReason` mirror on both platforms.
- macOS `CommandNotifications.swift` / `LillistCommands.swift`: four unobserved
  menu commands removed; dead iOS `CommandMenu("Task")` block removed.
- CLI: `Config.resolvedCalendar()` added + threaded through date commands.

## Assumptions I invalidated for later waves
- **`NotificationSpecStore` at-most-one-default enforcement is LIVE** —
  `concurrency-stress-tests` Task 1 is therefore **GREEN by design** (it verifies
  this enforcement under concurrency), not RED.
- `localTransactionAuthor` exists — `background-context-seam`'s background
  contexts must match the production merge policy / author.
- AutoPurgeJob is wired in both `bootstrap()`s — don't re-add.
- **`HistoryPruner.sweep` is NOT wired** — it's `background-context-seam`'s job
  (Wave 4). (The earlier index claim that resolve-inert-features wired it was wrong.)
- `Config.resolvedCalendar()` is in `WatchCommand` — `cli-robustness` must not
  duplicate it.

## Residuals I opened / closed
- Closed: notif-2 (default-spec dedup), the inert-feature set.
- Documented (kept): #2 (`mergeByPropertyObjectTrump` last-writer-wins),
  #4 (`.noNetwork`/`.iCloudDriveDisabled` unreachable — no `NWPathMonitor`),
  #5 (macOS launch-purge only), #11 (intermittent parallel-test SIGSEGV/timing
  flakes — test-harness CPU contention, owned by ci-and-build-posture Wave 7).

## Pre-flight the next executor should run
- `git log --oneline main | head -20` — confirm `cloudkit-convergence` +
  `resolve-inert-features` commits present (through `56af5c5`).
- `swift test --package-path Packages/LillistCore` — expect ~767 green; a single
  SIGSEGV/timing flake is residual #11, re-run before treating as real.
- Re-Read `NotificationSpecStore.swift` (enforcement live), `PersistenceController.swift`
  (`localTransactionAuthor`), iOS `AppEnvironment.swift` before edits.
