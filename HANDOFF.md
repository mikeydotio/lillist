# HANDOFF — Data & Sync Hardening, Wave 4b → Wave 4c

**Worktree:** `/Volumes/Code/mikeyward/Lillist/.claude/worktrees/data-sync-hardening`
**Branch:** `hardening/data-sync-2026-07`
**State:** Wave 0, all of Wave 1 (`1a`-`1d`), all of Wave 2 (`2a`, `2b`), all
of Wave 3 (`3a`, `3b`), and now all of Wave 4's first two plans, `4a`
`history-consumer-discipline` (`H6 M3`) and `4b` `notification-truthfulness`
(`H2 X8 X9 X10`), are **COMPLETE**. Wave 4's third and final plan, `4c`
`recurrence-correctness` (findings `H1 X7 X16 X17`), is next; Waves 5-6 not
started.

## What landed this wave (plan `4b`)

All four findings closed (`H2`, `X8`, `X9`, `X10` / stories `LIL-20`,
`LIL-39`, `LIL-40`, `LIL-41`). Full details, the per-finding test/commit
table, the X8/X9 investigations, and the X10 council decision writeup are in
the ledger's *Wave 4b closing report*
(`docs/superpowers/plans/2026-07-28-data-sync-hardening-index.md`) and the
plan doc
(`docs/superpowers/plans/2026-07-28-plan-4b-notification-truthfulness.md`).

- **`H2`**: `TaskStore.softDelete`/`restore` only reconciled the ROOT task's
  notifications even though both cascade onto every descendant.
  `applySoftDelete`/`clearSoftDelete` widened to also collect the visited
  task ids (alongside the existing H7 cycle-guard `visited` set) and return
  them; `softDelete` batch-cancels the whole set (`cancelPending(forTaskIDs:)`,
  H3's shape), `restore` runs a full `reconcile(taskID:)` per id.
- **`X8`**: widget/Shortcuts/Share Extension mutations never touched a
  scheduler. Verified (not assumed) that `UNUserNotificationCenter`'s
  pending-request namespace is scoped to the containing app, shared
  automatically by every extension in its App Group — no new entitlement
  needed. New `IntentSupport`/`WidgetIntentSupport.makeTaskStore()`/
  `makeNotificationScheduler()` factories are the standardized, wired
  construction sites; `CLIBridge.StatusHandler.run` gained an optional
  `notificationScheduler` param (CLI itself deliberately untouched — see
  `NudgeHandler`'s pre-existing doc comment for why).
- **`X9`**: `RemoteChangeReconciler.affectedTaskIDs` only reacted to
  `lastFiredAt` updates. Widened inside `drainOnce()` to also catch foreign
  `NotificationSpec` INSERTs and `LillistTask` UPDATEs touching `deletedAt`
  (both resolve a live row directly). `NotificationSpec` DELETEs are
  unresolvable from history (verified: no attribute in the model is flagged
  `preservesValueInHistoryOnDeletion`, confirmed by two independent existing
  code comments describing the identical limitation) — handled instead by a
  new set-difference "orphan sweep"
  (`NotificationScheduler.reconcileOrphanedPendingRequests()`, mirroring
  `LocalBackupCoordinator`'s own tombstone-free deletion handling). macOS
  gained its first `RemoteChangeReconciler` instance.
- **`X10`**: hydrated the all-day default from `PreferencesStore` at
  bootstrap, before any reconcile can run — closes the "reconcile rewrites
  correct triggers back to 09:00" symptom at its root (the wrong in-memory
  default, not the diffing logic itself, which was always correct).
  Documented `updateDefaultAllDayTime`'s intentional-rewrite-on-explicit-
  change semantics. **Council decision** (unanimous after deliberation) on
  the separate per-device-timezone dedup defeat: the real fix (a synced
  "home time zone" field on `AppPreferences`) is a data-model change
  requiring orchestrator approval — flagged to `team-lead`, not implemented
  here. Landed only the interim discipline: design-doc note, `TODO(LIL-83)`
  markers, a KNOWN LIMITATION regression suite. `LIL-83` filed and left in
  `todo` (blocked, not simply deferred).

Commit range `03575539..46001e7e` (9 commits: 1 docs (plan), 1 fix (H2), 2
fix/feat (X9 core + macOS wiring), 1 feat (X8), 1 fix (X10, all 3 parts), 2
`chore(stories)`, 1 docs (ledger)). Full `LillistCore` suite green **twice
in a row** with unmasked exit codes and a clean grep for the failure markers
(1354 tests, 237 suites — up from `4a`'s 1324/233 baseline; no flakes hit
either run). Both apps verified with unsigned `xcodebuild` builds after
every app-touching commit (BUILD SUCCEEDED, including `LillistWidget`/
`ShortcutsActions`/`ShareExtension-iOS` on iOS and `LillistWidget-macOS` on
macOS).

## What `4c` needs to know

`4c` (`recurrence-correctness`, findings `H1 X7 X16 X17`) is not on any of
`4b`'s shared-file chains directly (`RecurrenceSpawner.swift`, likely
`Validators.swift`, `AfterCompletionRule`/`CalendarRule` are the expected
hotspots per the finding descriptions), but touches adjacent territory:

- **Recurrence spawn does not yet schedule notifications for the spawned
  task beyond what `TaskStore.transition`'s existing post-save
  `scheduler.reconcile(taskID: spawnedID)` call already does.** If `4c`'s
  work touches the widget/Shortcuts/ShareExt status-transition paths
  (`AdvanceTaskStatusFromWidget`, `CompleteTaskIntent`/`ToggleStatusIntent`),
  those now correctly reconcile a spawned instance's inherited reminders too
  — this wasn't true before `4b` landed (X8's fix is what makes it true now).
- `RemoteChangeReconciler.SyntheticChange` now carries a `changeType`
  field. If `4c`'s recurrence work needs remote-change-driven reconciliation
  for a new entity, extend `affectedTaskIDs`'s existing `switch`, don't add
  a parallel diffing path.
- `NotificationScheduler.updateDefaultAllDayTime`'s doc comment now
  explicitly documents its two-legitimate-callers rewrite semantics —
  re-read it before touching anything related to all-day default timing.
- The council process (`Skill "council:council-vote"`) worked well for a
  genuinely 2+-way architectural decision (X10's timezone posture) — full
  audit trail at `.council/x10-all-day-timezone-dedup-posture/`. Reuse the
  pattern if `4c` hits a similarly non-obvious tradeoff (e.g. recurrence
  idempotency-key design for `X7`).

**Discovered, out-of-scope residuals — not fixed, all still open:**
- `TaskDuplicateReconciler.diagnosticLog` unwired in both apps (`1a`'s M5,
  flagged in `4a`) — `6a` completeness sweep.
- `recoverInterruptedReseed()`'s crash-recovery path never broadcasts
  (`3b`); `LIL-81` (`3a`); `LIL-77` (`1d`) — all still open.
- A remote `NotificationSpec.snoozedUntil`/`.offsetMinutes` in-place edit is
  still invisible to `RemoteChangeReconciler`'s diff (X9's scope note) — no
  production path creates this today (confirmed: reminders are
  create-or-delete, never edited in place), so it's latent, not reachable —
  flagged for whichever future plan touches `NotificationSpecStore.update`'s
  callers.
- `LIL-83` (X10's timezone-posture schema change) — **explicitly deferred
  out of this program** (orchestrator decision, 2026-07-29: not worth the
  Development→Production CloudKit schema-deploy cost for a bounded, already-
  documented limitation). Redesign trigger: a real cross-timezone duplicate
  report, or Mikey scheduling it directly — see the ledger's *Decisions
  awaiting Mikey* section. Not program-scheduled work; don't pick it up in
  `6a`.

## Standing worktree rules (unchanged)

No merge, no `/semver bump`, no `/deployit deploy` from this worktree.
One PR opens at the very end of Wave 6 — this session stops after
opening it, per policy.
