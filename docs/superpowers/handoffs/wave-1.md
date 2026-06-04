# Wave 1 handoff (P0 foundation)
From: Wave 1 executor   To: Wave 2 executor   Date: 2026-05-29 (backfilled 2026-06-04)

## What landed
- **store-swap-safety**: commits `bfd8635`..`6f008f7`; 663 LillistCore tests green.
  Closed persist-3, sync-1/3/4/7, conc-4, test-1/2, Roadmap #1. The keystone:
  transactional crash-safe store swap + the executing migration test harness.
  ⚠️ Its `liveSwapAllowed`-gated *live-container* swap tests execute only on a
  **code-signed** simulator host (CI or a developer Mac).
- **recurrence-input-hardening**: commits `758a14b`..`b6b80dd`; 687-test suite
  green, warning-free. Closed rec-1, rec-2, stores-7. A post-merge adversarial
  audit also closed a huge-positive-`interval` trap/hang via
  `CalendarRule.maxInterval` (1000) + a two-sided `clampedInterval` at the
  boundary and every expander site.

## Shared files I moved (anchor by structure — line numbers as-of-landing)
- `Sync/MigrationCoordinator.swift`: `runMigration` rewritten — phase order is
  now precondition → `host.reconfigure(to:)` → `copyStore` (copy, not move) →
  erase → settle → finalize; added a `localStoreRowCount` precondition; `host:
  any PersistenceReconfiguring`.
- `Persistence/PersistenceHost.swift`: `flushAndSwap` is now transactional with
  a CloudKit-options-preserving rollback (`lastRollbackDescription` recorded);
  starts ~line 139.
- `Persistence/QuarantineManager.swift`: `copyStore(at:)` (copy-not-move),
  `QuarantinedBackup`, `quarantinedStore(folderName:)`, `restore(...)`.
- `Sync/MigrationJournal.swift`: `quarantineBackupID` → `quarantineFolderName`
  (backward-compatible codable).
- `Persistence/PersistenceController.swift`: added `localTaskRowCount()`.
- iOS + macOS `AppEnvironment.swift`: `localStoreRowCount` wired LIVE in
  production (fail-closed).
- **Created**: `PersistenceReconfiguring` + `FakePersistenceReconfigurer`,
  the executing migration tests (`MigrationRunnerExecutingTests`,
  `MigrationRecoveryTests`), and the `Lillist-iOSAppHostedTests` target.

## Assumptions I invalidated for later waves
- `localStoreRowCount` is wired in production — **no later plan re-adds it.**
- **`test-2` is CLOSED**: `MigrationRecoveryTests.swift` exists with
  restoreFromBackup happy-path + no-backup + recorded-folder + legacy-fallback +
  secondary-failure tests. recovery-hardening must NOT re-add these.
- `restoreFromBackup` already honors the journal's recorded folder.
- `runMigration` reordered (reconfigure runs **before** `copyStore`) — a disk
  pre-flight that aborts at copy time leaves the mode already flipped.
- `PersistenceReconfiguring`/`FakePersistenceReconfigurer`/app-hosted target
  exist — reuse, don't recreate.

## Residuals I opened / closed
- Opened: #8 (non-positive recurrence `count` semantics — product call),
  #9 (out-of-range recurrence field values — non-crashing).
- Deferred to `recovery-hardening`: `wal_checkpoint(TRUNCATE)` around `copyStore`
  (engineering-notes follow-up).

## Pre-flight the next executor should run
- `git log --oneline main | head -20` — confirm `store-swap-safety` +
  `recurrence-input-hardening` commits present.
- Re-Read `MigrationCoordinator`, `PersistenceHost`, `QuarantineManager`,
  `MigrationJournal`, both `AppEnvironment`s, `PersistenceController` before any edit.
