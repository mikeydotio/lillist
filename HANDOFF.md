# HANDOFF — Data & Sync Hardening, Wave 2b → Wave 3a

**Worktree:** `/Volumes/Code/mikeyward/Lillist/.claude/worktrees/data-sync-hardening`
**Branch:** `hardening/data-sync-2026-07`
**State:** Wave 0, all of Wave 1 (`1a`-`1d`), and now **all of Wave 2**
(`2a` `migration-transitions`, `2b` `backup-restore-correctness`) are
**COMPLETE**. Wave 3 (`3a` `account-identity-and-status`, findings
`S3 S13 S21 S24`) is next; Waves 3-6 not started.

## What landed this wave (plan `2b`)

All 5 findings closed (`S2 S4 S7 S9b S23` / stories `LIL-12 LIL-14 LIL-28
LIL-31 LIL-61`). Full details, per-finding test/commit table, and the
new-type designs are in the ledger's *Wave 2b closing report*
(`docs/superpowers/plans/2026-07-28-data-sync-hardening-index.md`) and
the plan doc
(`docs/superpowers/plans/2026-07-28-plan-2b-backup-restore-correctness.md`).

- **`S2`**: `restoreFromBackup` now closes the store (`tearDownStore`)
  BEFORE any file-swap, then reopens via the new `attachStore(at:)`
  primitive (never `reconfigure`, which silently no-ops on a same-mode
  restore). `syncModeStore.setMode` moved to run only after the swap
  succeeds (S8-pattern, applied to this method for the first time).
- **`S7`**: `replaceICloudWithLocal`/`syncFirstThenDisable`/`disableNow`
  all switched from a direct `quarantine.copyStore(at:)` (live,
  possibly WAL-active store) to `tearDownStore(backupVia:)` +
  `attachStore(at:)` — the same closed-store mechanism
  `replaceLocalWithICloud` already used. Catch-block reattach is now
  unconditional across all four ops.
- **`S9b`**: new `ReseedJournal`/`ReseedJournalStore` (deliberately NOT
  a `MigrationJournal` case — see plan doc §2). `resetAndReseedFromThisDevice`
  stages its export bundle under `quarantine.rootDirectory/Reseed/<uuid>`
  (durable), journaled at every phase. New
  `DataStoreResetService.recoverInterruptedReseed()`, wired into both
  apps' `bootstrap()` first thing.
- **`S4`**: `.livePackage` restore now stages a COPY before any
  destructive step (mirrors `.snapshotZip`'s existing unzip-to-temp).
  `LocalBackupCoordinator` also gained an optional `destructiveOpGate` —
  `processRemoteChange` skips its prune step (not the upsert step)
  while any destructive op holds the gate.
- **`S23`**: `preflight` now derives compatibility from the MINIMUM
  `cloudKitSchemaVersion` across real task records, not the manifest
  (which always reflects the current build's constant, never the
  package's actual contents). New `TaskBackupStore.zipPackage(to:)`
  actor method — snapshots now genuinely serialize against concurrent
  writes. New `BackupPackageReconciling` protocol, injected into
  `DataStoreResetService`/`BackupRestoreService` so a destructive
  op's success always resyncs the live JSON backup package.

**New type: `PersistenceResetting.attachStore(at:)`** — attaches fresh at
an explicit mode, always updating `currentMode`, never a no-op (unlike
`reconfigure`'s same-mode guard or `reattachStore`'s attach-at-unchanged-
mode). All four `PersistenceResetting` conformers implement it.

**No council votes** — both the `S9b` journal-type decision and `S23`'s
schema-gate design resolved to one defensible answer once traced against
existing invariants (same pattern `2a` used).

Commit range `eed4e709..d43afe1f` (8 commits: 1 docs, 5 fix, 2
`chore(stories)`). Full `LillistCore` suite green **twice in a row**
(1235 tests, 228 suites, exit 0, no failure markers — up from `2a`'s
1217/228 baseline); both apps verified with unsigned `xcodebuild` builds
(BUILD SUCCEEDED) after every app-touching commit.

## What `3a` needs to know

Per the ledger's shared-file serial chains #2/#5, `2b` is the second
plan on chain #2 (`MigrationCoordinator.swift`) and landed unexpectedly
on chain #5 (`AppEnvironment.swift`) too — re-Read both before editing.

- `.replaceICloudWithLocal`/`.syncFirstThenDisable`/`.disableNow` no
  longer call `host.reconfigure(to:)` at all. `.replaceLocalWithICloud`
  is the only op still using it. If `3a`'s account-switch guard needs to
  intercept "the store is about to change," check `tearDownStore`/
  `attachStore`/`reconfigure` — not just `reconfigure`.
- `restoreFromBackup` has NO account-changed pre-flight (unlike
  `replaceICloudWithLocal`, which already probes before its irreversible
  erase). Consider whether `3a`'s account-identity guard needs to add
  one here too.
- Both `AppEnvironment.swift`s' backup-subsystem block
  (`backupSnapshotManager`/`localBackupCoordinator`) now constructs
  BEFORE `dataStoreReset` (moved up so it can be injected as
  `backupReconciler`) — don't move it back without re-threading that
  parameter. `bootstrap()` gained a `recoverInterruptedReseed()`
  best-effort call as its very first line.
- New types available if `3a` needs a similar shape: `ReseedJournal`/
  `ReseedJournalStore` (durable crash-recovery journal pattern) and
  `BackupPackageReconciling` (post-destructive-op resync hook).

**Discovered, out-of-scope residual** (flagged, not fixed — see the
ledger's Wave 2b closing report for the full note): `MigrationCoordinator
.restoreFromBackup` (the raw-SQLite migration-crash-recovery restore —
a different subsystem from `BackupRestoreService`'s JSON-package
restore) has the same "nothing resyncs the backup package" gap `S23`
fixed for the JSON-package subsystem. Not one of the 70 findings; worth
a future `6a`-style completeness-sweep entry.

## Standing worktree rules (unchanged)

No merge, no `/semver bump`, no `/deployit deploy` from this worktree.
One PR opens at the very end of Wave 6 — this session stops after
opening it, per policy.
