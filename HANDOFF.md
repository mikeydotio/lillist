# HANDOFF — Data & Sync Hardening, Wave 5 complete → Wave 6 (closeout)

**Worktree:** `/Volumes/Code/mikeyward/Lillist/.claude/worktrees/data-sync-hardening`
**Branch:** `hardening/data-sync-2026-07`
**State:** Wave 0, all of Wave 1 (`1a`-`1d`), all of Wave 2 (`2a`, `2b`), all
of Wave 3 (`3a`, `3b`), all of Wave 4 (`4a`, `4b`, `4c`), and now **all of
Wave 5** (`5a` `mutation-scope-discipline`, `5b`
`widget-snapshot-correctness`, `5c` `watermark-registry-pruning`) are
**COMPLETE**. **Wave 6 (`6a` `completeness-and-lows` + program closeout) is
next — the program's last wave.**

## What landed this wave (plan `5c`)

Both findings closed (`X12 L7` / stories `LIL-43 LIL-76`). Full details, the
per-finding test/commit table, the two class-kill demonstration transcripts,
and the contended-machine verification log are in the ledger's *Wave 5c
closing report*
(`docs/superpowers/plans/2026-07-28-data-sync-hardening-index.md`) and the
plan doc
(`docs/superpowers/plans/2026-07-28-plan-5c-watermark-registry-pruning.md`).

- **`X12`/`L7`**: `HistoryPruner.sweep()` used to delete everything before
  the coordinator's *current* token, correct only because both apps'
  `bootstrap()` happens to run every history consumer's catch-up before the
  sweep call — a property no compiler or test enforced. A Share Extension
  write landing while the main app was closed could be pruned before
  `DiagnosticHistoryObserver` (or any consumer) ever saw it. New
  `WatermarkRegistry` (`Persistence/WatermarkRegistry.swift`) replaces `3b`'s
  deliberately narrow `HistoryWatermarks` seam: `HistoryConsumerID` is a
  closed enum a `PersistentHistoryTokenStore` can only be constructed with
  (never an arbitrary key string), and `pruneBoundary(in:)` computes the
  earliest of every registered consumer's own watermark by scanning the
  store's full retained history (`NSPersistentHistoryToken` has no public
  ordering API). `HistoryPruner.sweep()` now returns a `SweepOutcome`
  (`.pruned`/`.skippedICloudSync`/`.skippedNoHistory`/`.skippedNoSafeBoundary`)
  instead of a bare `Bool`, and is fail-safe when any registered consumer
  has no watermark yet — never guesses a substitute boundary. `L7`'s dead
  bookkeeping-key write is removed outright (kept only as
  `HistoryPruner.legacyBookkeepingKey`, `internal`, so
  `WatermarkRegistry.clearAll()` can purge it from installs that wrote it
  before this fix).

Commit range `1dfedd84..bec420da` (6 commits). Full `LillistCore` suite
green **twice in a row** with unmasked exit codes and a clean grep for the
failure markers (1429 tests, 259 suites — up from `5b`'s 1419/257 baseline).
Both apps verified with unsigned `xcodebuild` builds (BUILD SUCCEEDED,
including all widget/Share/Shortcuts extensions).

**Verification ran on an unusually contended machine** (load average
persistently 4-5) — hit a `SIGSEGV` worker crash, the named "quiesce pair"
timing flake twice, the named "X16 boundary" flake, and once even a `5b`-own
`WidgetRefreshControllerTests` flake despite that plan's own two hardening
passes. Every one traced to a known, pre-existing, unrelated flake class
(confirmed by isolated re-run or the accepted serial tiebreaker) before being
discounted — see the ledger's closing report for the full run-by-run log.
Worth a heads-up to whoever runs `6a`'s own verification: this machine was
genuinely busy tonight, budget for retries.

**Class-kill demonstrations (not committed, reverted after):**
1. Hardcoded one of the three registered watermark key literals outside
   `WatermarkRegistry.swift` — `WatermarkRegistryConformanceTests` failed
   immediately, pinpointing the file.
2. Reverted `HistoryPruner.sweep()` to its pre-`5c` "prune before now" body
   — `X12WatermarkGatedPruningTests` failed red, and the lagging-consumer
   case surfaced a genuine `NSPersistentHistoryTokenExpiredError` (Core Data
   itself reporting the deleted-out-from-under-it transaction) — `X12` made
   concrete, not just theoretical.

## What `6a` (completeness-and-lows + closeout) needs to know

Every serial chain this ledger tracks is now closed for good — `6a` is a
sweep across residuals and the program's remaining low-severity findings
(`L1 L2 L6`), not a new shared-file chain. Read the ledger's *Wave/plan
table* and *Story-ID cross-reference table* for `6a`'s exact scope.

- `HistoryWatermarks.swift` no longer exists — `WatermarkRegistry`
  (`Persistence/WatermarkRegistry.swift`) is the only watermark-reset
  mechanism from here forward.
- `PersistentHistoryTokenStore`'s public API changed shape (`key: String` →
  `consumer: HistoryConsumerID`) — a fourth history consumer, if ever
  needed, registers by adding a case to `HistoryConsumerID`.
- **Discovered, out-of-scope residual, flagged not fixed
  (`5c`'s plan doc §7):** `LocalBackupCoordinator.bootstrapAtLaunch()` never
  calls its own `processRemoteChange()` as an explicit launch-time catch-up
  — it only advances its watermark from a *live* notification firing while
  the app happens to be running. `5c`'s registry-gated pruner directly
  closes `X12`'s data-loss risk regardless (a stale backup watermark now
  correctly blocks the sweep instead of being silently pruned past), but the
  underlying staleness can still cause unbounded history growth if no future
  remote-change notification happens to fire. Worth a look in `6a`; not one
  of the 70 cataloged findings.
- The `WidgetRefreshControllerTests` contention-sensitivity noted above is
  worth a glance if `6a` hits it again — not a regression, `5b`'s hardening
  may just not be proof against every load condition this shared machine can
  produce.

**Discovered, out-of-scope residuals — not fixed, all still open**
(carried forward unchanged from the `5b` handoff):
- `TaskDuplicateReconciler.diagnosticLog` unwired in both apps (`1a`'s M5,
  flagged in `4a`) — `6a` completeness sweep.
- `recoverInterruptedReseed()`'s crash-recovery path never broadcasts
  (`3b`); `LIL-81` (`3a`); `LIL-77` (`1d`) — all still open.
- A remote `NotificationSpec.snoozedUntil`/`.offsetMinutes` in-place edit is
  still invisible to `RemoteChangeReconciler`'s diff (X9's scope note) —
  latent, not reachable today.
- `LIL-83` (X10's timezone-posture schema change) — explicitly deferred out
  of this program (orchestrator decision, 2026-07-29). Not
  program-scheduled work; don't pick it up in `6a`.

## Standing worktree rules (unchanged)

No merge, no `/semver bump`, no `/deployit deploy` from this worktree.
One PR opens at the very end of Wave 6 — this session stops after
opening it, per policy.
