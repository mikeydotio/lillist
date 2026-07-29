# HANDOFF — Data & Sync Hardening, Wave 3a → Wave 3b

**Worktree:** `/Volumes/Code/mikeyward/Lillist/.claude/worktrees/data-sync-hardening`
**Branch:** `hardening/data-sync-2026-07`
**State:** Wave 0, all of Wave 1 (`1a`-`1d`), all of Wave 2 (`2a`, `2b`), and
now Wave 3's first plan (`3a` `account-identity-and-status`, findings
`S3 S13 S21 S24`) are **COMPLETE**. Wave 3's second plan, `3b`
`reset-propagation-safety` (findings `S9c S10 S18 S19 S20 S22 X11`), is
next; Waves 4-6 not started.

## What landed this wave (plan `3a`)

All 4 findings closed (`S3 S13 S21 S24` / stories `LIL-13 LIL-36 LIL-59
LIL-62`). Full details, per-finding test/commit table, the S3
mismatch-response council decision, and the identity-source rationale are
in the ledger's *Wave 3a closing report*
(`docs/superpowers/plans/2026-07-28-data-sync-hardening-index.md`) and the
plan doc
(`docs/superpowers/plans/2026-07-28-plan-3a-account-identity-and-status.md`).

- **`S3`**: new `AccountIdentityStore` (`Sync/AccountIdentityStore.swift`)
  persists/compares a `FileManager.ubiquityIdentityToken`-derived identity.
  Both `AppEnvironment.make()`s consult it before constructing
  `PersistenceController`, suppressing `armsCloudKitMirroring` on a
  mismatch (fail closed on a storage-read throw too). `AccountStateMonitor
  .refresh()` overrides to `.accountChanged` on a real mismatch — the
  mechanism finally makes that state reachable in production. New narrow
  `DataStoreResetService.resolveAccountMismatchByRedownloading()` lets a
  confirmed user resolution bypass the ambient `accountStateProvider`
  throw without weakening it for `ResetSignalMonitor`'s automatic path.
  `MigrationCoordinator` was discovered to have NEVER received an
  `accountStateProvider` in production on either platform (only
  `DataStoreResetService` had) — now fixed, and `.replaceLocalWithICloud`
  gained the account-changed preflight `.replaceICloudWithLocal` already
  had. Fixed two corroborated `PersistenceHost` leaks (council-surfaced):
  `configuration(for:)` now preserves `armsCloudKitMirroring` across every
  structural swap instead of defaulting it back to `true`.
- **`S13`**: real `CKAccountChanged` `NotificationCenter` observer on
  `AccountStateMonitor` + a foreground-reactivation re-probe on both
  platforms + a dedicated mid-session watcher that auto-severs a live
  mirroring connection (non-destructive containment, no confirmation) the
  instant a mismatch is detected after cold-launch priming.
- **`S21`**: `SyncStatusMonitor.resetStallState()` (clears both the
  existing export-axis AND a new mirrored import-axis stall
  counter/forensics — `applyImportOutcome` closes the "import-side never
  escalates" half of the finding), wired into `MigrationCoordinator`/
  `DataStoreResetService`'s successful-completion paths only.
- **`S24`**: new `LiveNetworkReachability` (`NWPathMonitor`-backed actor,
  placed in `LillistCore`, not per-app) replaces
  `ConstantNetworkReachability(reachable: true)` in both apps.
  `PauseReasonClassifier`'s dead `setICloudDriveDisabled(_:)` push API is
  replaced with a pull-based check against the same `AccountIdentityProbing`
  seam `AccountIdentityStore` uses.

**Council vote**: S3's mismatch-response policy — non-blocking cold
launch, automatic silent mid-session containment, two resolution choices
via existing hardened primitives, adopt-identity-only-after-success. Full
audit trail `.council/s3-account-mismatch-response-policy/DECISION.md`.

Commit range `b180d4de..593c6ed4` (14 commits: 1 docs, 10 fix/feat, 3
`chore(stories)`). Full `LillistCore` suite green **twice in a row** (1277
tests, 231 suites, exit 0, no failure markers — up from `2b`'s 1235/228
baseline); LillistUI non-snapshot suite green (83/17); both apps verified
with unsigned `xcodebuild` builds (BUILD SUCCEEDED) after every
app-touching commit.

## What `3b` needs to know

Per the ledger's shared-file serial chains #2/#5, `3a` is the third (and
final) plan on chain #2 (`MigrationCoordinator.swift`) and the third plan
on chain #5 (`AppEnvironment.swift`) — re-Read both before editing; `3b`
also opens chain #6 (`HistoryPruner.swift` — co-depends with `5c`, read
both plans before starting either).

- `AccountIdentityStore` is the synchronous, already-injectable seam if
  `3b`'s reset-propagation work ever needs to reason about account
  identity (e.g. should a propagated reset event be trusted differently
  post-account-switch) — `environment.accountIdentityStore` on both apps.
- `MigrationCoordinator`/`DataStoreResetService` now share one
  `accountStateProbe` closure per `AppEnvironment.swift` — wire any new
  destructive-op type the same way, don't duplicate the closure.
- `SyncStatusMonitor` is now `environment.syncStatusMonitor` (a stored
  property, no longer inline-constructed inside `CloudKitSyncStatusAdapter`).
- `resolveAccountMismatchByRedownloading()` established the "narrow,
  re-validating bypass method; ambient method stays unmodified" pattern —
  likely reusable for `3b`'s own `S10` "confirmed choice bypasses an
  ambient guard" shape (remote reset events never auto-apply, but the
  receiving device's own confirmed apply still needs to proceed).

**Discovered, out-of-scope residual — filed as `LIL-81`, not fixed**:
`MigrationCoordinator.restoreFromBackup` still has no `accountStateProvider`
check before `attachStore(at: prev)` (flagged by `2b`'s closing report for
`3a`'s consideration; traced and deliberately deferred — see the story for
the fix shape). `LIL-77` (the pre-existing `1d`-discovered
`crashPromptsEnabled` persistence gap) is also still open.

## Standing worktree rules (unchanged)

No merge, no `/semver bump`, no `/deployit deploy` from this worktree.
One PR opens at the very end of Wave 6 — this session stops after
opening it, per policy.
