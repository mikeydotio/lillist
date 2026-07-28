# HANDOFF — Data & Sync Hardening, Wave 2a → Wave 2b

**Worktree:** `/Volumes/Code/mikeyward/Lillist/.claude/worktrees/data-sync-hardening`
**Branch:** `hardening/data-sync-2026-07`
**State:** Wave 0 (docs + stories), all of Wave 1 (`1a`-`1d`), and now
**Wave 2 plan `2a` (`migration-transitions`) are COMPLETE**. Plan `2b`
(`backup-restore-correctness`) is next; Waves 3-6 not started.

## What landed this wave (plan `2a`)

All 10 findings closed (`S1 S5 S6 S8 S11 S12 S14 S15 S16 S17` / stories
`LIL-11 LIL-26 LIL-27 LIL-29 LIL-34 LIL-35 LIL-52 LIL-53 LIL-54 LIL-55`).
`MigrationCoordinator.runMigration` was redesigned per-op around one
connected fix — see the plan doc's full state-machine table
(`docs/superpowers/plans/2026-07-28-plan-2a-migration-transitions.md`,
section 3) before touching this function again.

- **`S1`**: `replaceLocalWithICloud` now tears down → quarantines the
  pre-wipe store → destroys+rebuilds empty → THEN reconfigures, so
  mirroring only ever downloads into a genuinely empty store instead of
  merging local rows into iCloud. Class-killed with a real store
  (`RealWipingReconfigurer` fake) proving rows are actually gone, not
  merely reconfigured in place.
- **`S6`**: `replaceICloudWithLocal` now erases the iCloud zone BEFORE
  reconfigure re-attaches mirroring (was: erase after attach). No teardown
  needed for this direction — it always starts `.localOnly`, so there's no
  live mirroring delegate to race the erase; see the plan doc for why this
  didn't need a council vote despite the brief flagging it as a possible
  2-sided call.
- **`S5`**: `syncFirstThenDisable` now waits for quiesce BEFORE detaching
  mirroring (was identical to `disableNow`). A timeout here FAILS the step
  closed (pre-destructive — nothing to revert yet).
- **`S8`**: `syncModeStore` advances ONLY in the finalize step, after every
  destructive step already succeeded. No explicit "revert on failure" is
  needed — mode structurally never advances before success, so a failure
  always leaves it at `previousMode`.
- **`S11`**: new public type `DestructiveOpGate` (`Sync/DestructiveOpGate.swift`)
  — `@MainActor final class`, synchronous `acquire(for:)`/`release()`,
  replaces `MigrationCoordinator.isMigrating` and
  `DataStoreResetService.isResetting`. **Both apps' `AppEnvironment`
  construct ONE shared instance and inject it into both types** — without
  that wiring the fix is inert (each type defaults to a private instance).
  `ResetSignalMonitor` needed no code change — its existing
  apply/acknowledge ordering already retries a failed-to-apply event on
  the next tick, verified end-to-end with a real gated
  `DataStoreResetService`.
- **`S12`**: `rebuildEmptyStore` failures now get the same
  reattach-then-rethrow handling the zone-erase step already had, in both
  `DataStoreResetService.performReset` and the new `replaceLocalWithICloud`
  path. `PersistenceHost.flushAndSwap` throws instead of silently
  "succeeding" with zero attached stores.
- **`S14`**: every `waitForQuiesce` call site now branches on the result.
  Pre-destructive callers (`syncFirstThenDisable`) fail on timeout;
  post-destructive callers (both enable ops, `DataStoreResetService`) log
  and proceed — matches `QuiesceResult.timedOut`'s own pre-existing "still
  syncing in background" doc comment. `SyncQuiesceMonitor` itself: every
  event type (including `.setup`, previously ignored) now counts as
  activity, and concurrent waiters no longer share one clock (per-waiter
  `[UUID: Date]`, not a single `Date`). Quiesce timing
  (`quiesceMinQuietWindow`/`quiesceHardTimeout`) is now injectable on both
  `MigrationCoordinator` and `DataStoreResetService` — default unchanged
  (5s/300s), but tests can now exercise the timeout branch in milliseconds.
- **`S15`**: `MigrationGate.evaluate()` and `runMigration`'s reentrancy
  check both now distinguish "journal file absent" (idle, unaffected —
  `FileMigrationJournalStore.read()` already handled this correctly) from
  "file present but undecodable" (fails closed) — previously conflated via
  `try?`.
- **`S16`**: the recovery sheet now appears immediately for ANY in-flight
  journal at launch, not just a stale (>600s) one. Only the main app ever
  runs `MigrationCoordinator` (verified: zero call sites in `Extensions/`),
  so a non-idle journal at launch can never belong to a migration
  genuinely still completing elsewhere — the staleness gate was solving a
  race that doesn't exist in this codebase.
- **`S17`**: the iCloud-unavailable launch screen's mode swap now routes
  through `migrationCoordinator.beginDisable(strategy: .now, storeURL:)`
  instead of a raw `setMode`-then-`reconfigure` pair run in reversed
  order. On failure, surfaces the coordinator's own `.failed` journal via
  the same recovery sheet.

**Two finding-driven test rewrites** (inverting assertions that codified
the bugs being fixed — cannot land the fix and keep the old assertion):
`MigrationCoordinatorTests.runMigrationRejectsLowDiskSpace` asserted mode
had already flipped post-failure (the `S8` bug); the `S6` ordering test
asserted reconfigure-then-erase under its old name.
`MigrationRecoveryTests.secondaryWriteFailureDoesNotMask`'s `throwOnWrite`
index was retimed to the new (longer) write sequence.

**No council votes needed** — see the plan doc section 9 for why every
design question in this plan resolved to one defensible answer once
traced against the existing code's own invariants.

Commit range: `dce3b354..568f7807` (7 commits: 1 docs, 5 fix/feat, 1
`chore(stories)`). Full `LillistCore` suite green **twice in a row** (1217
tests, 228 suites, exit 0, no failure markers either run — up from `1d`'s
1195/225 baseline); both apps verified with unsigned `xcodebuild` builds
(BUILD SUCCEEDED).

## What `2b` needs to know

Per the ledger's shared-file serial chains #2/#3, `2a` was the first plan
to touch `MigrationCoordinator.swift`/`PersistenceHost.swift` — re-Read
both before editing; line numbers have moved.

- `MigrationCoordinator.host` is now typed `any PersistenceReconfiguring &
  PersistenceResetting` (was just `PersistenceReconfiguring`) — any new
  conformer needs both. `restoreFromBackup` (S2/S4/S7's territory) now
  acquires `destructiveOpGate` too (`Owner.restore`) — keep that wrapping
  when reordering its internals.
- The quarantine-copy mechanism itself (`quarantine.copyStore(at:)` on a
  live, possibly-just-reopened store) is UNCHANGED — `S7`'s "WAL-active
  re-opened store" concern is real and untouched, left for `2b` exactly as
  scoped. `2a` only changed *when* the copy runs relative to erase/reconfigure
  for `replaceICloudWithLocal`, never *how* it's taken.
- `replaceLocalWithICloud` now quarantines via `host.tearDownStore(backupVia:)`
  instead of `quarantine.copyStore(at:)` directly — a different (and safer:
  connection already closed) mechanism than the other three ops still use.
  If `2b` unifies quarantine timing/mechanism across all four ops, this
  asymmetry is the one to reconcile.
- `MigrationJournal.State` did NOT gain a new case for the S1
  teardown/rebuild sub-steps (reuses `.reconfiguringStore`) — see the plan
  doc section 3.2 for why finer granularity wasn't needed. If `2b`'s work
  reveals a real behavior difference recovery should make based on which
  sub-step crashed, revisit that decision then, not preemptively.
- New quiesce-timing injection points (`quiesceMinQuietWindow`/
  `quiesceHardTimeout`) on both `MigrationCoordinator` and
  `DataStoreResetService` — reuse this pattern rather than hardcoding new
  literals if `2b` adds another `waitForQuiesce` call site.
- `DestructiveOpGate` is a new class-killer type (Adopt verdict) — `3a`'s
  account-identity guard is the next plan expected to touch it (per the
  ledger's *Class-killer verdicts* table); read `DestructiveOpGate.swift`'s
  doc comments before adding a third `Owner` case shape.

## Standing worktree rules (unchanged)

No merge, no `/semver bump`, no `/deployit deploy` from this worktree.
One PR opens at the very end of Wave 6 — this session stops after opening
it, per policy.
