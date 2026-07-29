# HANDOFF — Data & Sync Hardening, Wave 3b → Wave 4a

**Worktree:** `/Volumes/Code/mikeyward/Lillist/.claude/worktrees/data-sync-hardening`
**Branch:** `hardening/data-sync-2026-07`
**State:** Wave 0, all of Wave 1 (`1a`-`1d`), all of Wave 2 (`2a`, `2b`), and
now all of Wave 3 (`3a` `account-identity-and-status`, `3b`
`reset-propagation-safety`) are **COMPLETE**. Wave 4's first plan, `4a`
`history-consumer-discipline` (findings `H6 M3`), is next; Waves 4-6 not
started.

## What landed this wave (plan `3b`)

All 7 findings closed (`S9c S10 S18 S19 S20 S22 X11` / stories `LIL-32
LIL-33 LIL-56 LIL-57 LIL-58 LIL-42 LIL-60`). Full details, the per-finding
test/commit table, and the reset-event expiry-window council decision are
in the ledger's *Wave 3b closing report*
(`docs/superpowers/plans/2026-07-28-data-sync-hardening-index.md`) and the
plan doc
(`docs/superpowers/plans/2026-07-28-plan-3b-reset-propagation-safety.md`).

- **`S10`/`S22`**: `ResetSignalMonitor` is now an `actor` implementing the
  binding always-prompt product decision — `refreshPendingDecision()`
  (replaces the auto-applying `checkAndApply()`) only ever classifies and
  surfaces via `pendingDecisionStream`/`discardNoticeStream`;
  `confirmApply()` is the sole path that ever applies anything, called
  only from the new `PendingResetDecisionDialog` on explicit confirmation.
  Events past the council-decided 180-day window, or arriving on a
  `.localOnly` device, are acked-and-discarded automatically (never
  applied, never retried forever). `ControlInbox` quarantines undecodable
  payloads into a new `ResetEventDeadLetterStore`; `AppliedEventStore`
  capped at 200 entries.
- **`S20`/`S9c`**: `ResetPropagator.broadcast` returns a new
  `BroadcastOutcome` (`.notified(peerCount:)`/`.rosterEmpty`/
  `.notConfigured`/`.skippedQuiesceTimedOut`) instead of `Void`, surfaced
  through both apps' reset-result copy.
  `resetAndReseedFromThisDevice()` now waits for the reimported data's
  own re-export to quiesce before broadcasting — a timeout skips the
  broadcast rather than pointing a peer at a knowably-partial zone.
- **`X11`**: new `HistoryWatermarks` clears the three
  `PersistentHistoryTokenStore` consumers + `HistoryPruner`'s bookkeeping
  key; new `WidgetSnapshotStore.clearAll()`/
  `WidgetRefreshCoordinator.resetAfterDestructiveOp()` clear + regenerate
  the widget cache. Both wired into every `DataStoreResetService` reset
  flavor and `MigrationCoordinator`'s `.replaceLocalWithICloud` only (the
  sole migration op that actually destroys/rebuilds the store).
- **`S19`**: `CloudKitErrorClassifier` classifies `.zoneNotFound`/
  `.userDeletedZone` as recoverable; new
  `LiveCloudKitZoneEraser.hasAnyRecords(in:)` backs a new
  `remoteZoneHasRecords` guard on `.replaceLocalWithICloud` (symmetric to
  the existing `localStoreRowCount` guard; fails open on a throwing
  probe); "Try Again" was traced to only clear the journal and dismiss —
  new `MigrationCoordinator.retryFailedOperation(from:storeURL:)`
  actually re-dispatches the failed op.
- **`S18`**: `quarantine` promoted to a stored `AppEnvironment` property;
  `bootstrap()` now calls `cleanupExpired()`.

**Council vote**: the `S10` expiry-window duration — **180 days**,
unanimous 3/3 in round 1. Full audit trail
`.council/reset-event-expiry-window/DECISION.md`.

Commit range `9843f6fc..67298bb2` (8 commits: 2 docs, 4 fix/feat, 2
`chore(stories)`). Full `LillistCore` suite green **twice in a row** (1314
tests, 232 suites, exit 0, no failure markers — up from `3a`'s 1277/231
baseline; one documented-parallel-flake SIGABRT cleared on retry);
LillistUI non-snapshot suite green (83/17, unchanged); both apps verified
with unsigned `xcodebuild` builds (BUILD SUCCEEDED, including
`LillistWidget`/`ShareExtension-iOS` on iOS and `LillistWidget-macOS` on
macOS).

## What `4a` needs to know

`4a` opens chain #4 (`RemoteChangeReconciler.swift`) and continues chain
#6 (`HistoryPruner.swift` + history-token `UserDefaults` keys) alongside
`5c` — read the ledger's *Shared-file serial chains* section before
touching either file.

- **`HistoryWatermarks`** (`Persistence/HistoryWatermarks.swift`) is a
  deliberately narrow, hand-maintained seam — NOT the formal
  `WatermarkRegistry` the ledger's chain #6 originally sketched `5c`
  building first. `3b` landed the narrow version directly rather than
  block Wave 3 on pulling `5c` forward. `5c` should **replace**
  `HistoryWatermarks` with the real registry, not build a second
  mechanism alongside it.
- `ResetSignalMonitor`'s constructor gained `currentSyncMode`/
  `deadLetters`/`clock` params (all defaulted). If `4a`'s work touches
  test fixtures near this monitor, note the `clock: { Self.fixedNow }`
  discipline every `ResetSignalMonitorTests`/`ResetSignalMonitorGateTests`
  construction now needs — a fixed historical `requestedAt` combined with
  the real system clock now falls outside the 180-day expiry window.
- Both `AppEnvironment.swift`s' `bootstrap()` gained
  `quarantine.cleanupExpired()` (after `TreeIntegrityChecker.repair`) and
  two new observer registrations right after `resetSignalMonitor.start()`
  — re-Read the current `bootstrap()` ordering before inserting anything.
- `MigrationCoordinator`/`DataStoreResetService` both gained
  `historyWatermarksReset`/`widgetCacheReset` closure params — plain
  `(() async -> Void)?`, deliberately not `@Sendable`. If you add another
  such closure in `AppEnvironment.init`, don't capture `[weak self]`
  before every stored property is assigned (violates Swift's definite-
  initialization rules) — capture the specific already-assigned property
  value into a local instead.

**Discovered, out-of-scope residual — not fixed**: `recoverInterruptedReseed()`'s
resume branch never calls `propagator?.broadcast(...)`, crashed-or-not — a
crash-recovered reseed never notifies peers even after `3b`'s `S9c` fix to
the primary path. `LIL-81`/`LIL-77` (flagged in `3a`) are also still open.

## Standing worktree rules (unchanged)

No merge, no `/semver bump`, no `/deployit deploy` from this worktree.
One PR opens at the very end of Wave 6 — this session stops after
opening it, per policy.
