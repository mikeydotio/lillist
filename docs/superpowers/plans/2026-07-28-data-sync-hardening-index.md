# Data & Sync Hardening — Master Execution Index

> **For agentic workers:** This is the **living ledger** for the remediation
> program that closes the 2026-07-28 data & sync hardening review
> (`docs/reviews/2026-07-28-data-sync-review.md`, 70 findings). Read that
> review first (why this work exists), then this document (what's done, what's
> next, how to resume). Unlike the 2026-05-28 Foundation Hardening program
> (22 per-plan writing-plans docs, one PR per plan), this program runs as
> **one long-lived worktree branch**, commits per story, **one PR at the end**.

**Goal:** Close all 70 findings from the 2026-07-28 review by landing 14 plans
across 7 waves (Wave 0 docs/stories + Waves 1-6 remediation), ordered by
severity and shared-file dependency, without ever letting one plan silently
revert another.

**Tech stack:** Swift 6.2, SwiftUI, Core Data + `NSPersistentCloudKitContainer`,
CloudKit, XCTest + Swift Testing, xcodegen, storyhook (prefix `LIL`).

---

## 📍 Current status & how to pick this up

> **New here? Read this section first.** This file is the **living progress
> tracker** — keep it current as plans land.

**As of 2026-07-29 — Wave 0, all of Wave 1 (`1a` `trash-tree-integrity`,
`1b` `purge-cloudkit-retirement`, `1c` `store-location-unification`, `1d`
`export-schema-completeness`), all of Wave 2 (`2a` `migration-transitions`,
`2b` `backup-restore-correctness`), all of Wave 3 (`3a`
`account-identity-and-status`, `3b` `reset-propagation-safety`), and Wave 4's
first plan `4a` `history-consumer-discipline` COMPLETE. Wave 4's second plan,
`4b` `notification-truthfulness`, next.**

- ✅ **Plan `4a` closed both findings** (`H6`, `M3` / `LIL-24`, `LIL-47`) —
  `RemoteChangeReconciler.processPendingHistory` now advances its history
  watermark only after the affected-task computation *and* the consuming
  callback have both completed, mirroring `LocalBackupCoordinator
  .processRemoteChange`'s verified-correct pattern; the old `try? ... ?? []`
  swallow around `affectedTaskIDs` became a real `do`/`catch` that fails
  loud (new `diagnosticLog` property, same M5 shape) and leaves the
  watermark untouched on failure. Also fixed the hardcoded `localAuthor:
  PersistenceController.localTransactionAuthor` comparison to use
  `persistence.transactionAuthor` (this specific controller's own stamped
  value) — decided directly, no council needed: extension-authored writes
  stay classified as foreign (a same-device but separate-process write is
  still unobserved by this process's in-memory scheduler state), so the fix
  only changes "this instance's own writes vs. a hardcoded default." `M3`'s
  class-killer: `DiagnosticHistoryObserver`'s private nested `DrainGate`
  actor extracted into a public `Persistence/DrainGate.swift` type (pure
  refactor, zero behavior change, ported verbatim) and adopted in both
  `RemoteChangeReconciler` (fixes a genuine "double-process, watermark
  regression" correctness race — proven by a regression test showing 24
  concurrent calls reconcile 192 task-ids, 24× over, before the fix,
  exactly 8 after) and `TaskDuplicateReconciler` (a non-functional
  "main-queue full-table-scan thrash" fix only — each full scan is
  individually atomic via `ctx.perform`'s per-context serialization, so
  correctness was never at risk here; proven by a call-counting mirror
  identifier showing 24 concurrent calls run 24 independent full-table
  scans before the fix, a small bounded number after). Plan doc:
  `docs/superpowers/plans/2026-07-28-plan-4a-history-consumer-discipline.md`.
  Commit range `40bd3895..a809d74b` (4 commits: 1 fix (H6), 1 refactor
  (DrainGate extraction), 1 fix (M3 adoption), 1 `chore(stories)`). Full
  `LillistCore` suite green **twice in a row** with unmasked exit codes and
  a clean grep for the failure markers (1324 tests, 233 suites — up from
  `3b`'s 1314/232 baseline); one `SIGSEGV`/signal-11 flake hit on the first
  full-suite attempt after the DrainGate refactor commit — matches the
  documented parallel-test-flake class, cleared on retry per the documented
  policy, then re-confirmed clean twice more for the M3 commit. Unsigned
  `xcodebuild` build for `Lillist-iOS` (BUILD SUCCEEDED) — the only
  app-target file touched was iOS `AppEnvironment.swift`'s one-line
  `diagnosticLog` wiring; macOS was not touched (it has no
  `RemoteChangeReconciler` yet — `4b`'s job). See *Wave 4a closing report*
  below for what `4b` needs to know.

- ✅ **Plan `1a` closed all 8 findings** (`C1 C2 C3 H4 H7 M1 M2 M5` /
  `LIL-7 LIL-8 LIL-9 LIL-22 LIL-25 LIL-45 LIL-46 LIL-49`), added the
  `TreeIntegrityChecker` class-killer, and wired its self-heal into both
  apps' `bootstrap()`. Plan doc:
  `docs/superpowers/plans/2026-07-28-plan-1a-trash-tree-integrity.md`.
  Commit range `8e13b98f..56100933` (13 commits: 1 docs, 8 fix/feat, 4
  `chore(stories)`). Full `LillistCore` suite green (1134 tests, 216
  suites) after every fix commit; both apps verified with unsigned
  `xcodebuild` builds (BUILD SUCCEEDED). See *Wave 1a closing report*
  below for the per-finding breakdown, the class-kill demonstration, and
  what Wave `1b` needed to know about `TaskStore.swift`'s shape.

- ✅ **Plan `1b` closed all 3 findings** (`C4`/`X4` merged, `H3`, `X14` /
  `LIL-10`, `LIL-21`, `LIL-63`) — retired `NSBatchDeleteRequest` from both
  trash-purge paths in favor of chunked managed-object-context deletes
  (new shared `TrashPurger`), added delete-time predicate revalidation,
  and added OS-notification cancellation for `hardDelete`/`purgeAll`/
  `AutoPurgeJob`. Plan doc:
  `docs/superpowers/plans/2026-07-28-plan-1b-purge-cloudkit-retirement.md`.
  Commit range `bcfa04ac..33170218` (4 commits: 1 docs, 2 fix, 2
  `chore(stories)`). Full `LillistCore` suite green (1144 tests, 219
  suites — up from `1a`'s 1134/216 baseline); both apps verified with
  unsigned `xcodebuild` builds (BUILD SUCCEEDED). See *Wave 1b closing
  report* below for the per-finding breakdown, the `CascadeReaper` fate
  verdict, and what Wave `1c`/`1d`/`4b`/`5a` need to know about
  `TaskStore.swift`'s current shape. **Correction:** the wave-1b brief
  cited wrong story IDs for `H3`/`X14` (`LIL-23`/`LIL-48`, which actually
  belong to `H5`/`M4` under `plan-5a`) — the correct IDs, `LIL-21`/`LIL-63`,
  matched the ledger's own cross-reference table and were used throughout.

- ✅ **Plan `1c` closed all 3 findings** (`X1`, `X2`, `X15` / `LIL-15`,
  `LIL-16`, `LIL-64`) plus the iOS silent `defaultOnDisk` fallback detail
  folded into `LIL-15` — added the canonical `StoreLocation` resolver
  (four roles: `mainApp`/`extensionProcess`/`widget`/`cli`, all pinned to
  the identical `<group>/Lillist/Lillist.sqlite` path; only `mainApp` may
  arm CloudKit mirroring via the new `StoreConfiguration
  .armsCloudKitMirroring` field), wired all six processes through it, and
  added `MacAppGroupMigration` — a one-time, pure-file-system migration of
  macOS's legacy sandbox store into the App Group, run before any
  `PersistenceController` opens. Plan doc:
  `docs/superpowers/plans/2026-07-28-plan-1c-store-location-unification.md`.
  Commit range `07545d4d..e9b57e43` (10 commits: 1 docs, 6 feat/fix, 3
  `chore(stories)`). Full `LillistCore` suite green (1177 tests, 222
  suites — up from `1b`'s 1144/219 baseline) after every commit; `lillist-cli`
  builds; both apps verified with unsigned `xcodebuild` builds (BUILD
  SUCCEEDED, including the widget and Share/Shortcuts extension targets
  this plan touched). See *Wave 1c closing report* below for the per-
  finding breakdown, the both-stores-populated council decision, and what
  `3a` (which continues the `AppEnvironment.swift` shared-file chain)
  needs to know. **Correction (found post-close, 2026-07-28, fixed in
  `d4f942f8`):** `1c`'s own new `X15` test
  (`GatedPersistenceResolverTests.test_X15_...`) exposed a pre-existing
  fixture defect — every test in that file shared one literal
  `UserDefaults(suiteName:)` string for `SyncModeStore`, real disk-backed
  cross-process state that raced under `swift test --parallel`'s
  separate-worker-process model. This plan's "full suite green" claim
  above was **true in aggregate** (the race didn't always fire, and when
  it didn't, the run genuinely was green) but the verification method
  itself (piping through `tail`, reading only the swift-testing summary
  line) could not have caught it reliably even when it did fire — see the
  new *Verification protocol* bullet under *Known constraints* below,
  binding on every later wave. Filed as `LIL-79`, fixed by giving every
  test its own fresh UUID-suffixed identifier (no product code changed).
- ✅ **Plan `1d` closed all 4 findings** (`X3`, `S9a`, `X13`, `X18` /
  `LIL-17`, `LIL-30`, `LIL-44`, `LIL-67`) — plus two more silent drops the
  model-derived completeness test surfaced beyond X3's own text:
  `SmartFilter` had **zero** export/backup mapping at all, and
  `AppPreferences.defaultTagTintHex` (real, CloudKit-synced, distinct from
  Plan 21's five device-local fields) was never mapped. `ExportSchema`
  bumped to v2 with new `SeriesDTO`/`NotificationSpecDTO`/`SmartFilterDTO`
  and `TaskDTO.archivedAt`/`.seriesID`, all decode-with-default on older
  bundles; `BackupPackageSchema` bumped to v2 to match
  (`TaskBackupRecord.notificationSpecs` + new `series.json`/
  `smartFilters.json` sidecars). `Importer.apply` extends X13's
  skip-respecting, bundle-then-store-fallback discipline to the two new
  relationships (`Series.seedTask`, `Task.series`) from the start.
  `lastFiredAt` round-trips as-is (decided directly — real CloudKit-synced
  cross-device de-dup state, not device-local; see the plan doc). Plan doc:
  `docs/superpowers/plans/2026-07-28-plan-1d-export-schema-completeness.md`.
  Commit range `8d1472fb..2b1b7ad2` (7 commits: 1 docs, 2 fix, 1 feat, 1
  test, 2 `chore(stories)`). Full `LillistCore` suite green (1195 tests,
  225 suites — up from `1c`'s 1177/222 baseline) after every commit;
  `lillist-cli` builds; both apps verified with unsigned `xcodebuild`
  builds (BUILD SUCCEEDED). See *Wave 1d closing report* below for the
  per-finding breakdown, the version-compat matrix, and what `2b`
  (`backup-restore-correctness`, the chain's next link) needs to know.
  **No CloudKit-visible schema implications** — every change is to the
  export/backup file format and in-process logic; the Core Data model is
  unchanged. **Correction:** `1d`'s "full `LillistCore` suite green" claim
  above was verified with the same insufficient method flagged in `1c`'s
  correction note above (swift-testing summary line only, output piped
  through `tail`) — the `LIL-79` race living in `GatedPersistenceResolverTests`
  (a `1c`-owned file `1d` never touched) was present in every suite run
  this plan made, undetected for the same structural reason. No `1d` code
  is implicated; noted here only so this row doesn't read as having used a
  verification method later found insufficient without saying so.
- ✅ Review doc committed: `docs/reviews/2026-07-28-data-sync-review.md`
  (70 findings, faithfully reproduced from the source-of-truth plan; no
  severity softened, nothing dropped).
- ✅ This ledger index created and kept current.
- ✅ **Storyhook blocker hit, flagged, and resolved — all 70 stories filed
  (`LIL-7` through `LIL-76`).** `.storyhook/` was initialized in this
  worktree (prefix `LIL`, project created 2026-07-02; 5 pre-existing `done`
  stories from an earlier, unrelated widget-follow-up program), but every
  write-path command — `story new`, even bare with no flags — initially
  failed unconditionally with `{"error":"No such file or directory (os
  error 2)","exit_code":5}`, and `story doctor --fix` reported "nothing to
  fix." **Root cause (confirmed by `team-lead` via independent reproduction
  in a scratch repo):** the CLI requires `.storyhook/open/stories/` to exist
  and has no path-creation fallback for it. That directory is not
  git-tracked (git never commits empty directories), and since all 5 of
  this project's prior stories are archived/done, `open/stories/` was empty
  at the commit this worktree branched from — it simply didn't exist here.
  This is an **upstream storyhook CLI defect**: any write command fails with
  a bare `os error 2` when `open/stories/` is missing, there is no self-heal,
  and `story doctor --fix` does not catch it — worth Mikey fixing in the
  `story` CLI's own repo. Per the Wave-0 brief's explicit instruction, no
  stories were filed and the directory was not hand-patched; the blocker was
  flagged to `team-lead` instead, who created `.storyhook/open/stories/`
  with a `.gitkeep` and verified the identical failure+repair in a scratch
  worktree before handing it back. That `.gitkeep` is now committed (see
  below) so future worktrees inherit the structure — the actual class-kill
  for this defect. One harmless interim side effect
  (`.storyhook/next-id` bumped from committed `6` to `11` by four failed
  probe attempts, zero stories created) was reverted via `git checkout --
  .storyhook/next-id` before the fix landed; a subsequent real probe story
  (`LIL-6`) was created and cleanly `story delete`d to confirm the fix
  before the real filing pass ran.
- ✅ **Council vote resolved:** `C4` (stores sweep) and `X4` (cross-process
  sweep) describe the identical defect (same code change, same file, same
  verification caveat) and are filed as **one merged story** (`LIL-10`,
  labeled `C4/X4` in its title) rather than two stories linked by
  `duplicate-of`. All three council seats independently proposed the merge
  in round-1 research before seeing each other's reasoning; the formal
  single-choice vote was a 2-1 split over which proposal's *rationale
  phrasing* to canonize (not over whether to merge), triggering one
  deliberation + ranked-choice runoff round per protocol. See *Council-vote
  log* below for the final result and audit trail
  (`.council/c4-x4-merged-or-two-linked-stories/DECISION.md`).
- ✅ **Story-ID cross-reference table filled in** — see below.
- ✅ **Wave 1 is now fully complete** (`1a`, `1b`, `1c`, `1d`). Waves 2
  through 6 not started.
- ✅ **Discovered, out-of-scope defect from `1d` — filed as `LIL-77`, not
  fixed here (not one of the 70 cataloged findings):**
  `CrashReportingSection` (iOS `DebugPage`) and `CrashReportingPane`
  (macOS) still bind `PreferencesStore.Prefs.crashPromptsEnabled` (the
  Core-Data-backed field) for the Settings toggle and persist via
  `PreferencesStore.update`, while `AppEnvironment.crashPromptsEnabled`
  (what `CrashReporterHost` actually reads at boot) initializes from
  `DevicePreferencesStore` — and the toggle's `.onChange` only mirrors the
  new value into the in-memory `environment.crashPromptsEnabled`, never
  persisting to `DevicePreferencesStore`. Looks like a real defect: a
  user's crash-prompt choice may not survive relaunch. Per `team-lead`'s
  triage, filed as `LIL-77` (labels `plan-6a` — a completeness-sweep
  residual, not preferences-partition work that would bloat `3a`/`5a` —
  plus `discovered-during-1d`), with the full binding trail in the story
  body; added to `6a`'s row in the *Wave/plan table* and the *Story-ID
  cross-reference table* below. Not touched here to avoid conflating an
  unrelated behavior change with `1d`'s own scope.

- ✅ **Plan `2a` closed all 10 findings** (`S1 S5 S6 S8 S11 S12 S14 S15 S16
  S17` / `LIL-11 LIL-26 LIL-27 LIL-29 LIL-34 LIL-35 LIL-52 LIL-53 LIL-54
  LIL-55`) — `MigrationCoordinator.runMigration` redesigned per-op around
  one connected fix (see the plan doc's state-machine table): `S1`
  actually wipes local data before re-attaching mirroring
  (`replaceLocalWithICloud`); `S6` erases the iCloud zone before
  reconfigure re-attaches mirroring (`replaceICloudWithLocal`); `S5`
  waits for quiesce before detaching (`syncFirstThenDisable`); `S8`
  defers `syncModeStore.setMode` to the finalize step, after every
  destructive step succeeds; `S11` adds the new `DestructiveOpGate`
  public type (shared between `MigrationCoordinator` and
  `DataStoreResetService`, wired via one instance in both apps'
  `AppEnvironment`); `S12` adds the missing reattach-on-failure handler
  for `rebuildEmptyStore` and makes `PersistenceHost.flushAndSwap` throw
  instead of silently succeeding with zero attached stores; `S14` makes
  every `waitForQuiesce` caller honor `.timedOut` (asymmetrically —
  pre-destructive callers fail closed, post-destructive callers log and
  proceed) and fixes the monitor itself (`.setup` counts as activity,
  per-waiter isolation instead of one shared clock); `S15` makes
  `MigrationGate` and the coordinator's reentrancy guard fail closed on
  an undecodable journal instead of conflating it with idle; `S16` shows
  the crash-recovery sheet immediately for any in-flight journal, not
  just a stale one; `S17` routes the iCloud-unavailable launch screen's
  mode swap through the coordinator instead of an ungated, reversed-order
  direct call. Plan doc:
  `docs/superpowers/plans/2026-07-28-plan-2a-migration-transitions.md`.
  Commit range `dce3b354..568f7807` (7 commits: 1 docs, 5 fix/feat, 1
  `chore(stories)`). Full `LillistCore` suite green **twice in a row**
  (1217 tests, 228 suites, exit 0, no failure markers either run — up
  from `1d`'s 1195/225 baseline); both apps verified with unsigned
  `xcodebuild` builds (BUILD SUCCEEDED). No council votes needed — see
  the plan doc's own section 9 for why every design question resolved to
  one defensible answer. See *Wave 2a closing report* below for what `2b`
  needs to know about the current shape of `MigrationCoordinator.swift`/
  `PersistenceHost.swift`.

- ✅ **Plan `3a` closed all 4 findings** (`S3 S13 S21 S24` /
  `LIL-13 LIL-36 LIL-59 LIL-62`) — new `AccountIdentityStore` type
  (`Sync/AccountIdentityStore.swift`) persists a stable identity token from
  `FileManager.ubiquityIdentityToken` (archived/compared via `isEqual`, per
  Apple's own documented contract — no `CKContainer.fetchUserRecordID`
  fallback; a network-dependent identity check would either block or skip
  itself on every offline cold launch, and account switching needs no
  network) and distinguishes `.firstLaunch`/`.match`/`.signedOut`/
  `.mismatch`. Both `AppEnvironment.make()`s now call `check()` before
  constructing `PersistenceController`, forcing `armsCloudKitMirroring =
  false` for the launch on a mismatch (or a storage-read throw — fail
  closed). `AccountStateMonitor.refresh()` gained an optional
  `identityStore:` that overrides to `.accountChanged` on a real mismatch
  while the base `CKAccountStatus` is `.available` — the mechanism that
  makes `.accountChanged` reachable in production for the first time
  (previously only `simulateAccountChange()`, a test seam). `S13` added a
  real `CKAccountChanged` `NotificationCenter` observer
  (`startObservingSystemAccountChanges()`/`stopObservingSystemAccountChanges()`)
  plus a foreground-reactivation re-probe on both platforms, and a
  dedicated mid-session watcher that automatically severs a live mirroring
  connection (via the existing `beginDisable(.now)` primitive, non-
  destructive containment, no confirmation needed) the instant a mismatch
  is detected after cold-launch priming. `S21` added
  `SyncStatusMonitor.resetStallState()` (clears both export- and now a new
  mirrored import-axis stall counter/forensics — `applyImportOutcome`
  closes the "import-side recoverable failures never escalate" half of the
  finding) wired into `MigrationCoordinator`/`DataStoreResetService`'s
  successful-completion paths only. `S24` retired
  `PauseReasonClassifier`'s dead `setICloudDriveDisabled(_:)` push API for
  a pull-based check against the same `AccountIdentityProbing` seam
  (`ubiquityIdentityToken == nil` while the account is otherwise
  `.available` is precisely Apple's "signed in, no iCloud Drive access"
  distinction), and added `LiveNetworkReachability` — a new
  `NWPathMonitor`-backed actor placed in `LillistCore` (not duplicated per
  app) since it imports only `Network`/`Foundation` and has no
  platform-specific behavior, extending the `StoreLocation`
  canonical-resolver precedent from `1c`. Plan doc:
  `docs/superpowers/plans/2026-07-28-plan-3a-account-identity-and-status.md`.
  Commit range `b180d4de..137a6d54` (13 commits: 1 docs, 1 `chore(stories)`,
  10 fix/feat, 1 `chore(stories)` done-move not yet landed at ledger-write
  time). Full `LillistCore` suite green **twice in a row** with unmasked
  exit codes and a clean grep for the failure markers (1277 tests, 231
  suites — up from `2b`'s 1235/228 baseline); LillistUI non-snapshot suite
  green (83 tests, 17 suites); both apps verified with unsigned
  `xcodebuild` builds (BUILD SUCCEEDED) after every app-touching commit.
  See *Wave 3a closing report* below for the S3 mismatch-response council
  outcome, the two corroborated `PersistenceHost` leaks this plan closed
  as binding parts of the council decision, and what `3b` needs to know.

- ✅ **Plan `3b` closed all 7 findings** (`S9c S10 S18 S19 S20 S22 X11` /
  `LIL-32 LIL-33 LIL-56 LIL-57 LIL-58 LIL-42 LIL-60`) — `ResetSignalMonitor`
  became an `actor` implementing the binding always-prompt product decision:
  `refreshPendingDecision()` (replaces the old auto-applying `checkAndApply()`)
  only ever classifies and surfaces a pending decision via
  `pendingDecisionStream`/`discardNoticeStream`; `confirmApply()` is the sole
  path that ever applies anything, called only from the new
  `PendingResetDecisionDialog` on explicit user confirmation. Events past the
  council-decided 180-day expiry window, or arriving while the device is
  `.localOnly`, are acked-and-discarded automatically with a diagnostic
  breadcrumb and a UI-surfaced discard notice — never applied, never retried
  forever (closes `S10`; also closes `S22`'s `isApplying` race by
  construction). `S22`'s other two parts: `ControlInbox` gained
  `undecodableKeys`/`discardUndecodable` quarantining corrupt payloads into a
  new `ResetEventDeadLetterStore`; `AppliedEventStore` capped at 200 entries.
  `S20`: `ResetPropagator.broadcast` returns a new `BroadcastOutcome`
  (`.notified(peerCount:)`/`.rosterEmpty`/`.notConfigured`) instead of
  `Void`, surfaced through both apps' reset-result copy. `S9c`:
  `resetAndReseedFromThisDevice()` now waits for the reimported data's
  re-export to quiesce before broadcasting (`BroadcastOutcome
  .skippedQuiesceTimedOut` on timeout — never broadcasts a knowably-partial
  zone). `X11`: new `HistoryWatermarks` clears the three
  `PersistentHistoryTokenStore` consumers + `HistoryPruner`'s bookkeeping key;
  new `WidgetSnapshotStore.clearAll()`/`WidgetSnapshotBuilder.clearCache()`/
  `WidgetRefreshCoordinator.resetAfterDestructiveOp()` clear + regenerate the
  widget cache — both wired into `DataStoreResetService` (every reset flavor)
  and `MigrationCoordinator` (`.replaceLocalWithICloud` only — the sole
  migration op that actually destroys/rebuilds the store; the other three
  reattach the same file and must not have their watermarks cleared). `S19`:
  `CloudKitErrorClassifier` now classifies `.zoneNotFound`/`.userDeletedZone`
  as recoverable with a distinguishing message; new
  `LiveCloudKitZoneEraser.hasAnyRecords(in:)` backs a new
  `MigrationCoordinator.remoteZoneHasRecords` guard (symmetric to
  `localStoreRowCount`'s existing guard) that blocks `.replaceLocalWithICloud`
  with the new `LillistError.iCloudDataEmpty` when iCloud has no managed
  zone yet (fails open on a throwing probe); "Try Again" was traced to
  actually only clear the journal and dismiss — new
  `MigrationCoordinator.retryFailedOperation(from:storeURL:)` re-dispatches
  through `beginEnable`/`beginDisable` so a partial failure is genuinely
  retried. `S18`: `quarantine` promoted to a stored `AppEnvironment`
  property; `bootstrap()` now calls `cleanupExpired()`. Plan doc:
  `docs/superpowers/plans/2026-07-28-plan-3b-reset-propagation-safety.md` —
  contains the full always-prompt state diagram, the `BroadcastOutcome`
  design, and the X11 clear-list enumeration. Commit range `9843f6fc..89c34aa0`
  (7 commits: 1 docs, 4 fix/feat, 1 `chore(stories)`, plus a final
  `chore(stories)` done-move). Full `LillistCore` suite green twice in a row
  with unmasked exit codes and a clean grep for the failure markers (1314
  tests, 232 suites — up from `3a`'s 1277/231 baseline; one
  `SIGABRT`/Core-Data-internal-exception flake hit on the first full-suite
  attempt post-app-wiring, matching the documented parallel-test-flake class,
  cleared on retry per the documented policy); LillistUI non-snapshot suite
  green (83/17, unchanged); both apps verified with unsigned `xcodebuild`
  builds (BUILD SUCCEEDED, including `LillistWidget`/`ShareExtension-iOS` on
  iOS and `LillistWidget-macOS` on macOS) after the app-wiring commit. See
  *Wave 3b closing report* below for the council-vote outcome (180-day
  expiry, unanimous 3/3 round 1) and what `4a` needs to know.

**Next action for whoever picks this up:** start Wave 4's second plan, `4b`
(`notification-truthfulness`) — findings `H2 X8 X9 X10`. Its hotspot is the
same `RemoteChangeReconciler.swift` `4a` just hardened (chain 4 in
*Shared-file serial chains* below) — `4b` widens the diffing to spec
inserts/deletes and task soft-deletes, and per `X8`/`X9` will likely give
macOS its first `RemoteChangeReconciler` instance too. Read the *Resume
protocol* section first, then the *Wave 4a closing report* below for the
exact shape `4b` must build on (the `drainOnce()` split, the
`persistence.transactionAuthor` fix, the new `diagnosticLog` property).

---

## Wave 1a closing report (`trash-tree-integrity`)

Plan doc: `docs/superpowers/plans/2026-07-28-plan-1a-trash-tree-integrity.md`.

| Finding | Story | Fix commit | Regression test(s) |
|---|---|---|---|
| `H7` | `LIL-25` | `2e95f293` | `TreeCycleGuardTests.swift` (6 tests) — one (`deepCopyTerminatesOnCycle`) found a **real SIGSEGV** (stack overflow), not just a hang: `RecurrenceSpawner.deepCopy`'s own newly-created copies fed back into what it was walking, needing a hard node-count cap beyond the visited-set. |
| `M1` | `LIL-45` | `72f67668` | `TaskStoreTrashedParentGuardTests.swift` (5 tests) |
| `C2`/`M2`/`H4` | `LIL-8`/`LIL-46`/`LIL-22` | `ed058fd4` | `TaskStoreRestoreStateMachineTests.swift` (6 tests) — one combined commit; the three findings are inseparable in `restore(id:)`'s small surface. |
| `C1` | `LIL-7` | `d5c9d191` | `C1LiveDescendantPurgeTests.swift` (4 tests) |
| `C3`/`M5` | `LIL-9`/`LIL-49` | `cf6447ab` | `TaskDuplicateReconcilerTests.swift` (existing cascade-deletion test updated to assert re-pointing instead + 9 new tests) |
| `TreeIntegrityChecker` (class-killer) | — | `f40d7892` | `TreeIntegrityCheckerTests.swift` (8 tests) |
| Bootstrap wiring | — | `56100933` | unsigned `xcodebuild` builds, both apps |

**Class-kill demonstration (per the wave brief, not committed):** temporarily
disabled the `C2` promote-to-root block in `TaskStore.restore`, reproduced
the bug (a child restored under a still-trashed parent kept its stale
parent link), then ran `TreeIntegrityChecker.scan` against that same
context and confirmed it independently reported `.liveUnderTrashedAncestor`
for the stranded child — proving the checker is a genuine class-level
backstop, not merely a mirror of the point fix. The disabled block and the
throwaway test were reverted before continuing; `git status` was clean
before the next commit.

**Council vote:** the `H7` cycle-break tie-breaker rule (`TreeIntegrityChecker`
self-heal) — see *Council-vote log* below.

**What Wave `1b` needs to know about `TaskStore.swift`'s current shape**
(the serial chain's next link):
- `batchPurge` now calls `CascadeReaper.planPurge(ofTrashedRoots:)` (not
  the old `objectIDs(forDeleting:)`) and promotes `PurgePlan
  .liveDescendantsToPromote` to root via `TaskTreeRepair.promoteToRoot(_:)`
  **before** `CascadeReaper.batchDelete`. `1b`'s CloudKit-retirement rewrite
  of the purge path must preserve this ordering (promote-then-delete), not
  just port the old `objectIDs(forDeleting:)` call.
- `restore(id:)` now does three things in sequence inside its `context.perform`
  block: `clearSoftDelete` (clears `deletedAt` **and** `archivedAt`,
  cascaded) → conditional promote-to-root if the parent is still trashed →
  `nextPositionDetail`-based repositioning. `nextPositionDetail`'s predicate
  now filters `deletedAt == nil` on both branches (root and parented) —
  any new caller of `nextPositionDetail`/`nextPosition` inherits this
  (correct; matches every other ordering query in the file).
- `create`/`reparent`/`reorder` all call a new `assertParentNotTrashed(_:)`
  helper (`TaskStore.swift`, near `validateTitle`) at the point a *new*
  parent assignment is made — any new mutation path that assigns `.parent`
  should call it too.
- `applySoftDelete`/`clearSoftDelete` are now two-arity (public-shaped
  wrapper + `visited: inout Set<NSManagedObjectID>` recursive worker) —
  don't reintroduce the old single-arity recursive form.
- New file `Packages/LillistCore/Sources/LillistCore/Persistence/TaskTreeRepair.swift`
  — the shared `promoteToRoot(_:at:)` helper `CascadeReaper`'s caller and
  `TreeIntegrityChecker` both use. `H3`/`X14` (`1b`'s scope) purge/notification
  work should reuse it too if it needs to promote/detach a node.
- New file `Packages/LillistCore/Sources/LillistCore/Persistence/TreeIntegrityChecker.swift`
  — wired into both `AppEnvironment.bootstrap()`s right after
  `taskDuplicateReconciler.start()` and before `autoPurgeJob.run()`. Don't
  reorder relative to those two without re-reading the rationale comment at
  each call site.

---

## Wave 1b closing report (`purge-cloudkit-retirement`)

Plan doc: `docs/superpowers/plans/2026-07-28-plan-1b-purge-cloudkit-retirement.md`.

| Finding | Story | Fix commit | Regression test(s) |
|---|---|---|---|
| `C4`/`X4` | `LIL-10` | `c2284a1a` | `C4X4PurgeMirroringTests.swift` (2 tests) — asserts the mechanism (a real `NSManagedObjectContextDidSave` carrying the purged row in `NSDeletedObjectsKey`), not just end-state row counts. |
| `X14` | `LIL-63` | `c2284a1a` (same commit as `C4`/`X4` — the chunking that creates the race and the recheck that closes it are one mechanism, not separable behavior) | `X14PurgeRevalidationTests.swift` (2 tests) — deterministic restore-mid-flight + re-trash-past-cutoff races, driven via `TrashPurger`'s two decomposed steps directly (no sleep, no test-only hook — same hand-ordered-real-contexts technique as `TagStoreFindOrCreateRaceTests`). |
| `H3` | `LIL-21` | `a4af7b8c` | `H3PurgeNotificationCancellationTests.swift` (6 tests) — separate commit from `C4`/`X4`/`X14` (two hats: new behavior vs. mechanism swap). |

**Story-ID correction (flagged to `team-lead`, logged here for the audit
trail):** the wave-1b brief cited `H3`→`LIL-23` and `X14`→`LIL-48`. Both
were wrong — those IDs belong to `H5`/`M4` under `plan-5a`. The correct
IDs, matching both `story show` and this ledger's own cross-reference
table, are `H3`→`LIL-21` and `X14`→`LIL-63`; all `1b` commits close the
correct stories.

**`CascadeReaper`'s fate — decided directly, no council needed (see the
plan doc for the full reasoning):**
- `objectIDs(forDeleting:)` — **kept, and got a real caller for the first
  time.** Before `1b` its only caller was its own unit tests. `H3`'s
  `TaskStore.hardDelete` fix needs exactly its unconditional (no
  live/trashed barrier) cascade-closure semantics to collect the
  notification-cancellation id set.
- `planPurge(ofTrashedRoots:)` — kept unchanged, still the source of `1a`'s
  C1 barrier logic, now also feeding `H3`'s doomed-task-id collection.
- `batchDelete(objectIDs:in:)` — **deleted.** Zero callers once both purge
  paths moved to `TrashPurger`; it was literally the `NSBatchDeleteRequest`
  wrapper this plan retires, so leaving it in place unused would be the
  exact attractive nuisance a future contributor could reach for again.

**What Wave `1c`/`1d`/`4b`/`5a` need to know about the current shape**
(the `TaskStore.swift` serial chain's next link is `4b`; `1c`/`1d` don't
sit on this chain but touch adjacent files):
- `TaskStore.batchPurge` is now a thin wrapper around the new
  `TrashPurger.purge(predicateFormat:arguments:context:viewContext:notificationScheduler:)`
  (`Persistence/TrashPurger.swift`) — it no longer contains any purge logic
  itself. `AutoPurgeJob.run` calls the same `TrashPurger.purge`. Any future
  change to purge behavior (barrier logic, chunking, revalidation,
  notification cancellation) belongs in `TrashPurger`, not duplicated back
  into either call site.
- `TrashPurger.purgeChunk`/`fetchCandidateRootObjectIDs` are exposed
  (`internal`, not `private`) specifically so tests can drive them
  independently for race-condition coverage — follow that precedent rather
  than adding test-only hooks to production code if a future plan needs to
  test another mid-flight race.
- `TaskStore.hardDelete` now collects a doomed-task-id closure via
  `CascadeReaper.objectIDs(forDeleting:)` before deleting, and calls
  `notificationScheduler?.cancelPending(forTaskIDs:)` after a successful
  save — the same collect-before/cancel-after ordering pattern any future
  destructive mutation should follow.
- `NotificationReconciling` now has two methods:
  `reconcile(taskID:)` (existing; requires the row to still exist) and
  `cancelPending(forTaskIDs:)` (new; H3 — works whether or not the row
  exists, batches into one OS round trip). `NotificationScheduler` is the
  only conformer; any new one must implement both.
- `AutoPurgeJob` gained a `public var notificationScheduler:
  (any NotificationReconciling)?`, property-injected exactly like
  `TaskStore`'s. Both `AppEnvironment.swift`s wire it right after
  `taskStore.notificationScheduler = scheduler` — `4b`'s notification work
  should follow the same wiring point for any other store/job that needs
  scheduler access.

---

## Wave 1c closing report (`store-location-unification`)

Plan doc: `docs/superpowers/plans/2026-07-28-plan-1c-store-location-unification.md`.

| Finding | Story | Fix commit(s) | Regression test(s) |
|---|---|---|---|
| `X2` | `LIL-16` | `397f3ddb` | `StoreLocationTests.swift` (11 tests) + `StoreLocatorTests.swift`'s new `x2_resolvesCanonicalPathNotOwnThirdPath` — asserts the CLI's "store not found" message now points at the canonical `<group>/Lillist/Lillist.sqlite` path, not its old third path. |
| `X15` | `LIL-64` | `397f3ddb` (CLI role), `73c2fbf8` (extension/widget role wiring) | `PersistenceControllerCloudKitTests.swift`'s new `armsCloudKitMirroring`-gating tests + `GatedPersistenceResolverTests.test_X15_extensionAndWidgetRolesSuppressMirroring_mainAppDoesNot`. |
| `X1` (iOS half — folded-in silent-fallback detail) | `LIL-15` | `621e6ded` | Covered by `StoreLocationTests`'s container-unreachable-throws coverage; iOS's `AppEnvironment.make()` now routes through the same throwing resolver, no bespoke test needed (behavior change is "stop catching and forking," not new logic). |
| `X1` (macOS half — the App-Group migration) | `LIL-15` | `c7538745` | `MacAppGroupMigrationTests.swift` (10 tests) — every state-machine branch (`notNeeded`/`migrated`/`migratedResolvingConflict`/`conflictDetected`/`migrationFailed`), sidecar handling, and the `verifyStagedCopy`/`footprint` seams directly. |
| Keystone (serves `X1`/`X2`/`X5`/`X7`/`X15`/`X20`, no separate finding) | — | `e9b57e43` | `MultiProcessStoreHarnessTests.swift` (4 tests) — two `PersistenceController`s on one on-disk file prove write-visibility; the path-pin test proves all four roles resolve identically. |

**Commit range:** `07545d4d..e9b57e43` — 1 docs, 6 feat/fix (`397f3ddb`
`73c2fbf8` `070ba738` `621e6ded` `c7538745` `e9b57e43`), 3 `chore(stories)`
(`91f49d2e` `18fabaf4` `bcfd091c`). Full `LillistCore`
suite green (1177 tests, 222 suites, up from `1b`'s 1144/219 baseline) after
every commit; `lillist-cli` builds; both apps verified with unsigned
`xcodebuild` builds (BUILD SUCCEEDED, including the `LillistWidget`/
`LillistWidget-macOS`, `ShareExtension-iOS`, and `ShortcutsActions` targets
this plan touched).

**Post-close addendum (`LIL-79`, fixed in `d4f942f8`):** the `X15`
regression test added in `73c2fbf8`
(`GatedPersistenceResolverTests.test_X15_extensionAndWidgetRolesSuppress
MirroringMainAppDoesNot`) wrote `.iCloudSync` into a `UserDefaults`
suite name every other test in that file also shared — a pre-existing
fixture weakness the three earlier tests never exposed because they all
wrote the same value (`.localOnly`). Under `swift test --parallel`'s
separate-worker-process model this raced, reproduced twice by
`team-lead` post-close. Fixed by giving every test in the file its own
fresh UUID-suffixed suite name (matching the pattern already used
everywhere else in this test target); no production code changed.
Verified via a deliberate toggle-the-failure probe (confirmed `swift
test --parallel`'s exit code and its `Test Suite … failed` /
`Note: Some test targets reported failures` markers are trustworthy —
the swift-testing summary line alone is not, since it excludes
`XCTestCase` results) plus two full-suite green runs with unmasked exit
codes (1195 tests/225 suites + 89 `XCTestCase` methods, exit 0, no
failure markers, both runs) and five additional stress runs of the
affected file alone. See the *Verification protocol* bullet under
*Known constraints* — binding on every later wave.

**Class-killer delivered:** `StoreLocation`
(`Packages/LillistCore/Sources/LillistCore/Persistence/StoreLocation.swift`)
— a `Role` enum (`mainApp`/`extensionProcess`/`widget`/`cli`) whose
`resolve(role:appGroupID:containerProvider:fileManager:)` is now the single
authority every one of the six processes calls for "where is the store,"
and whose `makeConfiguration(syncMode:)` is the single authority for "may
this process arm CloudKit mirroring." `StoreConfiguration.appGroupOnDisk`
(the pre-`1c` ad-hoc App-Group path builder) was retired once its last
caller (iOS) moved to `StoreLocation` — same "don't leave an attractive
nuisance" precedent `1b` applied to `CascadeReaper.batchDelete`.

**Both-stores-populated council decision (`X1`'s macOS-migration edge
case):** SyncMode-conditioned policy — `.iCloudSync` quarantines the
pre-existing App-Group store and migrates legacy into its place;
`.localOnly` makes zero file mutation (no CloudKit safety net exists for
the App-Group store in that mode, so quarantining it would be
unconditional, permanent data loss). Full audit trail, including the
round-1 2-1 split and the source-grounded deliberation that resolved it:
`.council/macos-migration-both-stores-populated/DECISION.md`. Logged below
in the *Council-vote log*.

**Deviation from the plan doc's commit plan:** the plan doc sketched 6 code
commits; the landed shape is 6 code commits (matching count, different
composition — the plan's items 2/3 [`StoreLocation` + CLI wiring, then
`armsCloudKitMirroring` + role wiring] each landed as planned, but a 7th
originally-unplanned commit, `fix(core): disambiguate QuarantineManager
folder names for same-second calls`, was inserted between the iOS fix and
the macOS migration once the council-vote deliberation surfaced the
folder-collision hazard — the plan doc's *binding implementation
requirement #3* already called this out as a requirement, just not as its
own numbered commit-plan step) + 3 `chore(stories)` commits (not spelled
out as a separate line item in the plan doc's commit plan, same pattern
`1a`/`1b` used). No scope changed, only the commit breakdown.

**What `3a` (`account-identity-and-status`, the next plan to touch
`AppEnvironment.swift` per the shared-file-chain note) needs to know:**
- Both `AppEnvironment.swift`s' `make()` now resolve the store through
  `StoreLocation.resolve(role: .mainApp, ...)` — iOS unconditionally,
  macOS after `MacAppGroupMigration.migrateIfNeeded` runs. Any future
  change to *how* the store path is resolved belongs in `StoreLocation`,
  never reintroduced ad-hoc in either `AppEnvironment.swift`.
- macOS's `AppEnvironment` gained a new stored property,
  `macAppGroupMigrationOutcome: MacAppGroupMigration.Outcome`, threaded
  through `private init` and logged via `breadcrumbs` in `bootstrap()`
  (the very first line, before `preferencesPartitionMigrator.runIfNeeded()`).
  If `3a`'s account-identity guard needs to run before other bootstrap
  steps too, re-read this ordering — don't just prepend blindly.
- `GatedPersistenceResolver` and `MigrationGate.resolveStoreConfiguration`
  both now take a required `role: StoreLocation.Role` parameter. Any new
  caller (e.g. if `3a` adds a new extension/process) must pick the correct
  role — there is no default.
- `QuarantineManager.quarantineStore(at:label:)`/`copyStore(at:label:)`
  gained an optional `label` parameter (nil preserves prior behavior) to
  avoid a same-second folder-name collision when a caller makes more than
  one quarantine/copy call in one synchronous run. `3a`'s account-switch
  guard, if it ever needs multiple quarantine calls in one flow, should use
  distinct labels rather than rediscovering this collision.

---

## Wave 1d closing report (`export-schema-completeness`)

Plan doc: `docs/superpowers/plans/2026-07-28-plan-1d-export-schema-completeness.md`.

| Finding | Story | Fix commit | Regression test(s) |
|---|---|---|---|
| `X13` | `LIL-44` | `2d99e623` | `X13SkipExistingParentTests.swift` (6 tests) — skip-respecting + destination-store-fallback parent resolution, for both tasks and tags. |
| `S9a` | `LIL-30` | `2e4f1856` | `DataStoreResetServiceTests.resetAndReseedPreservesAttachmentBytes` (new `RealWipingResetHost` fake — the shared `FakePersistenceReconfigurer` never actually clears the store, which would make a naive before/after check pass regardless of the bug). `Importer.importBundle` itself had no `assetsDirectory` parameter at all; also fixed the two sibling callers with the identical gap — the iOS/macOS Settings "Import a Backup" flows (`AdvancedSection.swift`/`AdvancedPane.swift`). |
| `X3` + `X18` (one commit — see the plan doc's *X18* section for why they turned out inseparable) | `LIL-17`, `LIL-67` | `16bb7125` | `X3ExportSchemaCompletenessTests.swift` (7 tests: full round trip, v1-bundle decode-with-defaults, forward-incompatibility unchanged, orphan/dangling-seed handling, skip-discipline for the two new relationships) + 3 new `LocalBackupCoordinatorTests` cases (series/smartFilter sidecar refresh, notificationSpec task-file routing) + extended `BackupRestoreServiceTests.fullRestoreRoundTrip` (`defaultTagTintHex`, verified red→green by temporarily reverting the one-line `applyPreferences` fix). |
| Model-derived completeness class-killer | — | `ff8ac9e4` | `ExportSchemaCompletenessTests.swift` (1 test, walks every entity) — kill demonstrated locally (removed `SmartFilter`'s mapping entry, confirmed the failure names `SmartFilter` specifically, restored, `git status` clean). |

**Commit range:** `8d1472fb..2b1b7ad2` — 1 docs, 2 fix (`2d99e623` X13,
`2e4f1856` S9a), 1 feat (`16bb7125` X3+X18), 1 test (`ff8ac9e4`
class-killer), 2 `chore(stories)` (`57d7fd71`, `2b1b7ad2`). Full
`LillistCore` suite green (1195 tests, 225 suites, up from `1c`'s
1177/222 baseline) after every commit; `lillist-cli` builds; both apps
verified with unsigned `xcodebuild` builds (BUILD SUCCEEDED).

**Scope grew beyond the four named findings.** Walking the full Core Data
model against `ExportSchema` (required to build the completeness test)
surfaced two more silent drops the wave brief's "any other silently-dropped
attribute/relationship you find" clause explicitly anticipated:
`SmartFilter` had **zero** export/backup mapping at all (same severity
class as `Series` — it's an equally `syncable="YES"` CloudKit entity), and
`AppPreferences.defaultTagTintHex` — a real, synced, account-level field,
distinct from the five fields Plan 21 deliberately partitioned into
device-local `DevicePreferencesStore` — was never mapped. Both fixed in the
same `X3` commit. A third gap surfaced by writing the round-trip test
itself: `BackupRestoreService.applyPreferences` never copied
`defaultTagTintHex` either, even after it started round-tripping correctly
through export/import — fixed in the same commit, verified red→green.

**Version-compat matrix (verified, not just asserted):** `ExportSchema
.version` 1→2, `BackupPackageSchema.version` 1→2. A v1-shaped JSON document
(no `series`/`notificationSpecs`/`smartFilters`/`archivedAt`/`seriesID`/
`defaultTagTintHex` keys) decodes cleanly via the v2 `Importer`, defaulting
absent keys to `[]`/`nil`/the model's own defaults — proven with a
hand-written v1 JSON fixture, not just a Swift-level default value. The
existing forward-incompatibility guard (`document.version <=
ExportSchema.version`, else `.unsupportedExportVersion`) is unchanged and
still correctly rejects a v2 bundle carrying the new fields when the guard
is exercised at `ExportSchema.version + 1`.

**`lastFiredAt` — decided directly, no council needed:** round-trips as-is;
import does not reset it. It's already a real CloudKit-mirrored
cross-device de-dup field (`NotificationScheduler.computeDesiredRequests`'s
`lastFired >= fireDate - 60s` guard, only ever consulted when `fireDate >
Date()`), and `resetAndReseedFromThisDevice` converging every device on
this device's exact state is the field's *correct* behavior — the
counter-argument doesn't survive contact with the guard's own short-circuit,
so this didn't meet the "2+ defensible alternatives" bar. Full reasoning in
the plan doc.

**X18's real shape, reconciled with the review's literal text:** the
review describes "4 independent fetches"; `Exporter.swift`'s four fetches
(task/tag/journal/attachment) were already inside one `ctx.perform` block
*before* this plan touched anything — an earlier, unrelated refactor
(`25b8de94`) had already restructured them that way. What was NOT already
fixed: `preferences.read()` ran via a *separate* `PreferencesStore` round
trip on the view context, before that `ctx.perform` block even started — a
live instance of the exact torn-bundle defect X18 describes, just
uncounted by the review's "4". Fixed by fetching `AppPreferences` directly
from the same background context, inside the same `perform` block, as
every other fetch (including the three `1d` adds). Sibling-swept the
identical pattern in `LocalBackupCoordinator.reconcileFull()`/
`refreshSidecars()`, which had the same shape — not itself one of the 70
findings, fixed per "fix any hits unless distant and unrelated."

**No CloudKit-visible schema implications.** The Core Data model
(`LillistModel.xcdatamodeld`) is unchanged — every change in `1d` is to the
export/backup *file format* (`ExportSchema`, `BackupPackageSchema`, both
plain Codable structs serialized to JSON) and to `Importer`/`Exporter`/
`LocalBackupCoordinator`/`BackupRestoreService`'s in-process logic. Nothing
to deploy Development→Production in the CloudKit Console for this plan.

**What `2b` (`backup-restore-correctness`, next link in chain 7) needs to
know about the current shape:**
- `ExportSchema.Document`/`TaskDTO`/`PreferencesDTO` and
  `BackupPackageSchema.TaskBackupRecord` each now have a custom
  `init(from:)` for backward-compat decoding — extend the same
  `CodingKeys` + `decodeIfPresent(...) ??` pattern for any new field `2b`
  adds, rather than reverting to synthesized Codable.
- `Importer.apply`'s pass order is now: tags → tag.parent → tasks →
  task.parent → series → series.seedTask → task.series → journal entries →
  attachments → notification specs → smart filters → save. Any new
  cross-referencing relationship `2b` introduces should slot into this
  same create-then-wire sequence, respecting the skip-tracking discipline
  (`skippedTagIDs`/`skippedTaskIDs`/`skippedSeriesIDs`) already
  established for tags/tasks/series.
- `TaskBackupStore.writeSidecars`/`.replaceAll` and `BackupPackageReader`
  now handle four sidecars (`tags.json`, `series.json`,
  `smartFilters.json`, `preferences.json`) plus the per-task files
  (`notificationSpecs` lives there, not a sidecar — it's task-owned).
  `BackupRestoreService.applyPreferences` copies every `PreferencesDTO`
  field individually (not a struct assignment) — a new `PreferencesDTO`
  field needs an explicit line added there too, a gap this plan's own
  `defaultTagTintHex` fix closed but a future field could reopen.
- `Exporter`/`LocalBackupCoordinator` both kept their `preferences:
  PreferencesStore` constructor parameter for API compatibility, but
  neither reads from it anymore for the atomic-fetch paths — see each
  type's doc comments before reaching for `preferences.read()` in new code
  added to either type.

---

## Wave 2a closing report (`migration-transitions`)

Plan doc: `docs/superpowers/plans/2026-07-28-plan-2a-migration-transitions.md`
— contains the full target state machine (phases × crash-recovery behavior
per op), the `DestructiveOpGate` type proposal with UML, the quiesce
semantics table, and the `S6` ordering rationale. Read it before touching
`MigrationCoordinator.swift` again.

| Finding | Story | Fix commit | Regression test(s) |
|---|---|---|---|
| `S11` (foundation) | `LIL-34` | `071c9440` | `DestructiveOpGateTests.swift` (6 tests) — new standalone type, no consumers wired yet. |
| `S14` (monitor internals) | `LIL-52` | `38c7d1cf` | `SyncQuiesceMonitorTests.swift` — inverts `setupEventsAreIgnored` (renamed `setupEventsCountAsActivity`, now asserts `.timedOut` under churn) + new `concurrentWaitersDoNotInterleave`. |
| `S1`, `S5`, `S6`, `S8`, `S11` (coordinator wiring), `S12` (coordinator half), `S14` (coordinator call sites), `S15` (coordinator half) | `LIL-11`, `LIL-26`, `LIL-27`, `LIL-29`, `LIL-34`, `LIL-35`, `LIL-52`, `LIL-53` | `1156c808` | `MigrationRunnerExecutingTests.swift` (+6: S1 class-kill via `RealWipingReconfigurer`, S12 reattach, S5 happy-path + timeout-fails-closed, S14 post-destructive timeout-completes) + `MigrationCoordinatorRestoreTests.swift` (+1: S15 corrupt-journal via new `CorruptMigrationJournalStore`) + `MigrationGateTests.swift` (+1: S15) + two finding-driven rewrites in `MigrationCoordinatorTests.swift`/`MigrationRecoveryTests.swift` (see below). One combined commit — `runMigration`'s per-op step sequence is one connected redesign, not independently separable patches (see plan doc §3). |
| `S11` (reset service), `S12` (reset service half), `S14` (reset service call site), `S15` (n/a — reset service has no journal) | `LIL-34`, `LIL-35`, `LIL-52` | `b63f0f52` | `DataStoreResetServiceTests.swift` (+2: S12 reattach-on-rebuild-failure, S14 post-rebuild timeout-completes) + new `CrossTypeDestructiveOpGateTests.swift` (3 tests, both directions) + new `ResetSignalMonitorGateTests.swift` (2 tests, end-to-end through a real gated `DataStoreResetService`, not just a synthetic throwing closure). |
| `S11` (production wiring), `S16`, `S17` | `LIL-34`, `LIL-54`, `LIL-55` | `02a183ac` | App-level — no host-side unit test target reaches `OnboardingPresentationModifier` (private to each `LillistApp.swift`, UI-tested only via full XCUITest); verified by unsigned `xcodebuild build` for both apps (BUILD SUCCEEDED) + the reasoning captured in the plan doc §6/§7. |

**Commit range:** `dce3b354..568f7807` — 1 docs (`dce3b354`), 5 fix/feat
(`071c9440` S11 foundation, `38c7d1cf` S14 monitor, `1156c808` the big
coordinator redesign, `b63f0f52` reset-service wiring + S12 half, `02a183ac`
app wiring + S16/S17), 1 `chore(stories)` (`568f7807`). Full `LillistCore`
suite green **twice in a row** with unmasked exit codes and a clean grep
for the failure markers (1217 tests, 228 suites — up from `1d`'s 1195/225
baseline); both apps verified with unsigned `xcodebuild` builds (BUILD
SUCCEEDED).

**Two finding-driven test rewrites (two-hats — landed in the same commit
as their fix, not separately, since there is no way to land the fix and
keep the old assertion):**
- `MigrationCoordinatorTests.runMigrationRejectsLowDiskSpace` asserted
  `host.currentMode`/`modeStore.currentMode()` had already flipped to the
  target post-failure — that assertion *was* the `S8` bug. Now asserts
  both stay at the original mode (and, per `S6`'s reorder, that reconfigure
  never even ran before the disk-space pre-flight threw).
- `MigrationRunnerExecutingTests`'s `replaceICloudWithLocalExecutes` test
  (renamed, was "reconfigure precedes erase") asserted the exact ordering
  `S6` reports as the bug. Now asserts erase precedes reconfigure.
- `MigrationRecoveryTests.secondaryWriteFailureDoesNotMask`'s
  `throwOnWrite` index moved from `3` to `5` — the new per-op step
  sequence writes the journal more times before `disableNow` reaches
  `reconfigure` (quarantine now writes twice: once before the copy, once
  with the folder name after).

**No council votes.** See the plan doc's section 9 — every design question
that came up (`S6`'s erase-before-reconfigure ordering, whether
`replaceLocalWithICloud`'s teardown/rebuild sub-steps needed a new
persisted journal state, `S16`'s staleness-gate removal, `DestructiveOpGate`'s
class-vs-actor shape) resolved to one defensible answer once traced
against the existing code's own documented invariants and constraints —
none met the "two genuinely defensible alternatives" bar the wave brief
set as the council-invocation criterion.

**Deviation from the wave brief's suggested commit shape:** the brief
implied per-finding commits; the actual landed shape groups by
*mechanism* instead (foundation type, monitor internals, coordinator
redesign, reset-service wiring, app wiring) because most of the 10
findings are not independently separable within `runMigration`'s single
per-op step sequence — see the commit-message rationale in `1156c808`.
Every finding still has a named regression test and is traceable to its
landing commit via the table above.

**What `2b` (`backup-restore-correctness`, next link on chains 2 and 3)
needs to know about the current shape:**
- `MigrationCoordinator.host` is now typed `any PersistenceReconfiguring &
  PersistenceResetting` (was just `PersistenceReconfiguring`) — both
  production conformers (`PersistenceHost`) and the test fake
  (`FakePersistenceReconfigurer`) already satisfied both protocols, so
  this widening required no other changes. Any new conformer needs both.
- `restoreFromBackup` now acquires `destructiveOpGate` (as `Owner.restore`)
  before doing anything — keep that acquire/release wrapping in place when
  `2b` reorders `restoreFromBackup`'s internals (its ordering bugs, `S2`,
  are explicitly `2b`'s scope, not touched here).
- The quarantine-copy MECHANISM itself (`quarantine.copyStore(at:)` on a
  live, possibly-just-reopened store) is UNCHANGED — `S7`'s "WAL-active
  re-opened store" concern is real and untouched. `2a` only changed *when*
  the copy runs relative to erase/reconfigure for `replaceICloudWithLocal`
  (now before both), never *how* the copy itself is taken.
- `replaceLocalWithICloud` quarantines via `host.tearDownStore(backupVia:)`
  instead — a different (and safer: connection already closed before the
  copy) mechanism than the other three ops still use directly via
  `quarantine.copyStore(at:)`. If `2b` unifies quarantine timing/mechanism
  across all four ops, this asymmetry is the one to reconcile; the plan
  doc's crash-recovery matrix (§3.4) explains why each op's current timing
  is correct for what it needs today.
- `MigrationJournal.State` did NOT gain a new persisted case for `S1`'s
  teardown/rebuild sub-steps — both reuse `.reconfiguringStore`. See the
  plan doc §3.2 for the reasoning (no recovery-behavior difference hinges
  on which sub-step crashed). If `2b`'s restore work reveals a case where
  it actually would, revisit then.
- New injectable constructor params on both `MigrationCoordinator` and
  `DataStoreResetService`: `quiesceMinQuietWindow`/`quiesceHardTimeout`
  (default 5s/300s, unchanged from the prior hardcoded values). Reuse this
  pattern rather than hardcoding a new literal if `2b` adds another
  `waitForQuiesce` call site that needs a deterministic-timeout test.
- `DestructiveOpGate` (`Sync/DestructiveOpGate.swift`) is the new shared
  serialization point for every destructive operation against
  `PersistenceHost`. Both apps' `AppEnvironment` construct exactly ONE
  instance and inject it into `migrationCoordinator` and `dataStoreReset` —
  if `2b`'s restore work needs its own destructive sequence, acquire this
  same gate (`Owner.restore` already covers `restoreFromBackup`; add a new
  `Owner` case only if a genuinely distinct operation shape emerges).

---

## Wave 2b closing report (`backup-restore-correctness`)

Plan doc: `docs/superpowers/plans/2026-07-28-plan-2b-backup-restore-correctness.md`
— contains the full restore/reseed state-machine tables, the `S7`
unification design, the `S4` staging design, and the `S9b` journal
decision (with the "why not `MigrationJournal`" reasoning). Read it
before touching `MigrationCoordinator.swift`/`DataStoreResetService.swift`/
`BackupRestoreService.swift`/`LocalBackupCoordinator.swift` again.

| Finding | Story | Fix commit | Regression test(s) |
|---|---|---|---|
| `S2` | `LIL-12` | `42b2e657` | `MigrationRecoveryTests.swift` (+2: same-mode-still-reattaches class-kill, failed-attachStore-reattaches-without-clobbering-journal) |
| `S7` | `LIL-28` | `959a5e65` | `MigrationRunnerExecutingTests.swift` (+2 dedicated quarantine-via-tearDownStore proofs) + 4 existing tests updated from `reconfigureCalls` to `resetSteps`/`attachCalls` assertions (mechanism changed, not just call count) |
| `S9b` | `LIL-31` | `11e24b70` | `DataStoreResetServiceTests.swift` (+5: pre-wipe-failure leaves `localDataWiped=false`, `recoverInterruptedReseed`'s three branches — idle/discard/resume — the resume case a genuine class-kill via `RealWipingResetHost`, missing-staged-path throws) + 1 existing test rewritten (durable-location cleanup, not the old temp-dir) |
| `S4` | `LIL-14` | `7c863ebd` | `BackupRestoreServiceTests.swift` (`PackageWipingResetter` — deletes the entire live package mid-reset, restore still recovers the pre-wipe data; class-kill verified red against the pre-fix code) + `LocalBackupCoordinatorTests.swift` (gate-held-skips-prune / gate-released-prunes, class-kill verified red) |
| `S23` | `LIL-61` | `d43afe1f` | `BackupRestoreServiceTests.swift` (manifest-lies-record-tells-truth + 3 existing incompatible-package tests updated to bump the real record, not just the manifest) + `BackupSnapshotManagerTests.swift` (20-way concurrent `replaceAll`/`zipPackage` stress against one actor, asserting every zip is 0-or-5 files, never torn) + `DataStoreResetServiceTests.swift`/`BackupRestoreServiceTests.swift` (reconcile-called-once-on-success / never-on-failure) |

**Commit range:** `eed4e709..d43afe1f` — 1 docs (`eed4e709`), 5 fix
(`42b2e657` S2, `959a5e65` S7, `11e24b70` S9b, `7c863ebd` S4, `d43afe1f`
S23), 2 `chore(stories)` (in-progress, done). Full `LillistCore` suite
green **twice in a row** with unmasked exit codes and a clean grep for
the failure markers after every fix commit (1235 tests, 228 suites — up
from `2a`'s 1217/228 baseline); both apps verified with unsigned
`xcodebuild` builds (BUILD SUCCEEDED) after every commit that touched
an app target (`S9b`, `S4`, `S23`). One `SmartFilterPerformanceTests`
timing-budget flake and one `SyncQuiesceMonitorTests` timing flake hit
during verification — both match documented pre-existing flake classes
(CLAUDE.md's parallel-test-flakes section), unrelated to this plan's
changes, and cleared on retry per the documented policy.

**New type: `PersistenceResetting.attachStore(at:)`.** Added alongside
`tearDownStore`/`rebuildEmptyStore`/`reattachStore` — attaches a fresh
store at an explicit mode, always performing a real add and always
updating `currentMode` (unlike `reconfigure(to:)`'s same-mode no-op or
`reattachStore()`'s attach-at-unchanged-mode). `S2`'s `restoreFromBackup`
needed it because the on-disk file changes out from under the
coordinator even when the target mode doesn't change; `S7`'s
`replaceICloudWithLocal`/`syncFirstThenDisable`/`disableNow` reuse it as
the trailing half of their new tearDown-then-attach shape. All four
`PersistenceResetting` conformers (`PersistenceHost`,
`FakePersistenceReconfigurer`, `RealWipingReconfigurer`,
`RealWipingResetHost`) implement it.

**New type: `ReseedJournal`/`ReseedJournalStore`
(`Sync/ReseedJournal.swift`/`Sync/ReseedJournalStore.swift`).**
Deliberately NOT a `MigrationJournal.State` case — see the plan doc §2
for the full reasoning (a reseed's recovery action is categorically
different from a migration's, and `DataStoreResetService`'s own header
comment already forbids touching `MigrationJournal`). Mirrors
`MigrationJournal`'s exact file-backed/atomic-write shape. Staging root
is `quarantine.rootDirectory.appendingPathComponent("Reseed")` — reused,
not a new durable-root concept. `DataStoreResetService
.recoverInterruptedReseed()` is wired into both apps' `bootstrap()`,
first thing, best-effort.

**New type: `BackupPackageReconciling`
(`Sync/DataStoreResetService.swift`, next to `BackupPackageReconciling`'s
one production conformer `LocalBackupCoordinator`).** Mirrors
`BackupDataResetting`'s existing shape but deliberately NOT `@MainActor`
— `LocalBackupCoordinator` isn't actor-isolated the way
`DataStoreResetService` is. Injected into both `DataStoreResetService`
(one chokepoint inside `performReset`'s success path, covering all four
reset flavors, plus two explicit extra calls in
`resetAndReseedFromThisDevice`/`recoverInterruptedReseed` after their
reimports) and `BackupRestoreService` (after a successful restore's
reimport).

**Production wiring note for future contributors:** both
`AppEnvironment.swift`s now construct `localBackupCoordinator` and its
backing `backupSnapshotManager`/`backupPackageDirectory` *before*
`dataStoreReset` (moved up from their original position after it) so
`localBackupCoordinator` can be injected into `dataStoreReset` as
`backupReconciler` — the ledger's *shared-file serial chains* section's
note on `AppEnvironment.swift` ordering (macOS's
`macAppGroupMigrationOutcome` logging, `3a`'s account-identity guard)
should account for this reordering if `3a` touches the same region.

**No council votes.** `S9b`'s journal-type decision (dedicated
`ReseedJournal` vs. reusing `MigrationJournal`) and `S23`'s
min-vs-max-vs-reject schema-gate design (min-over-records won once the
manifest's actual write behavior — always-current, never
records-derived — was traced from source, the same "one defensible
answer once traced against existing invariants" pattern `2a` used) both
resolved without needing the council — see the plan doc §2 and §4a for
the full reasoning trails.

**Deviation from the plan doc's implied commit shape:** `S9b`'s test
updates (`resetAndReseedFromThisDevice: cleans up its temp export
directory`) and `S7`'s four call-site test updates
(`reconfigureCalls`→`resetSteps`/`attachCalls`) landed in the SAME
commit as their respective fixes, not separately — both are
necessitated by the fix itself (the old assertions test a mechanism the
fix replaces), matching the two-hats principle's own carve-out ("fix
first" commits may include the test changes the fix's own behavior
change requires, distinct from a separate refactor).

**Discovered, out-of-scope residual — not fixed here, flagged per the
`LIL-77` precedent:** `MigrationCoordinator.restoreFromBackup` (the
raw-SQLite migration-crash-recovery restore, a DIFFERENT subsystem from
`BackupRestoreService`'s JSON-package restore — see the plan doc §0) has
the same "nothing tells `LocalBackupCoordinator` to resync" gap `S23`
fixed for the JSON-package subsystem: it swaps the live SQLite file
directly, with no Core Data save for the backup coordinator's observers
to react to. Not one of the 70 findings, not touched here to avoid
scope creep on an already-large plan; worth a future `6a`-style
completeness-sweep entry.

**What `3a` (`account-identity-and-status`, the next plan to touch
`MigrationCoordinator.swift`/`AppEnvironment.swift`) needs to know:**
- `MigrationCoordinator.host` still `any PersistenceReconfiguring &
  PersistenceResetting` (unchanged) — but the PROTOCOL itself gained
  `attachStore(at:)`. Any new conformer needs it.
- `.replaceICloudWithLocal`/`.syncFirstThenDisable`/`.disableNow` no
  longer call `host.reconfigure(to:)` at all — they call
  `host.tearDownStore(backupVia:)` then `host.attachStore(at:)`.
  `.replaceLocalWithICloud` is the ONE op still using
  `host.reconfigure(to:)` (its trailing step, after `rebuildEmptyStore`
  leaves a store attached to swap). If `3a`'s account-switch guard needs
  to intercept "is the store about to change," check ALL of
  `tearDownStore`/`attachStore`/`reconfigure`, not just `reconfigure`.
- The catch block's reattach-on-failure is now unconditional across all
  four ops (was gated to `.replaceLocalWithICloud` only pre-`2b`).
- `restoreFromBackup`'s ordering is now tearDown → file swap →
  `attachStore(at: prev)` → `syncModeStore.setMode(prev)` → journal
  clear. If `3a`'s account-identity guard needs a pre-flight check
  before a migration/restore proceeds, the account-changed pattern
  `.replaceICloudWithLocal` already uses (a probe consulted right before
  the irreversible step, throwing into the existing catch) is the
  precedent to extend — `restoreFromBackup` currently has no equivalent
  account-changed pre-flight; consider whether it needs one before `3a`
  lands its own probe elsewhere.
- Both `AppEnvironment.swift`s' backup-subsystem block
  (`backupSnapshotManager`/`localBackupCoordinator`) now constructs
  BEFORE `dataStoreReset` (see the production-wiring note above) — don't
  move it back after without re-threading `backupReconciler:`.

---

## Wave 3a closing report (`account-identity-and-status`)

Plan doc: `docs/superpowers/plans/2026-07-28-plan-3a-account-identity-and-status.md`
— contains the `AccountIdentityStore` type proposal with UML, the
identity-source decision (`ubiquityIdentityToken`, no
`fetchUserRecordID` fallback), the S3 mismatch-response council outcome,
and the launch-sequence integration diagram.

| Finding | Story | Fix commit(s) | Regression test(s) |
|---|---|---|---|
| `S3` (foundation) | `LIL-13` | `df522814` | `AccountIdentityStoreTests.swift` (8 tests) + `FileAccountIdentityStoreTests` (4 tests) — `check()`'s four-way truth table, token equality via round-trip archive, `adoptCurrentIdentity()` ordering. |
| `S3`/`S13` (monitor integration) | `LIL-13`/`LIL-36` | `53fc6719` | `AccountStateMonitorTests.swift` (+7) — `refresh()` override on mismatch, no override on firstLaunch/match, a stale stored identity never promotes `.noAccount`/`.restricted` to `.accountChanged`, `CKAccountChanged` observer start/stop. |
| `S3` (fix 1 — `PersistenceHost` leak) | `LIL-13` | `93a858bb` | `PersistenceHostTests.swift` (+2) — a host built with `armsCloudKitMirroring: false` stays suppressed across every reconfigure/attachStore/reattachStore; a normally-armed host still preserves `true`. |
| `S3` (resolution primitive) | `LIL-13` | `c72c2d5c` | `DataStoreResetServiceTests.swift` (+4) — `resolveAccountMismatchByRedownloading()` requires an active mismatch, bypasses the preflight once, `resetAndRedownload()` itself stays unmodified/blocked, a failed resolution's reattach doesn't rearm mirroring. |
| `S3` (missing `.replaceLocalWithICloud` preflight) | `LIL-13` | `29449d44` | `MigrationRunnerExecutingTests.swift` (+1) — mirrors `.replaceICloudWithLocal`'s existing guard at the same relative position (after the recovery-anchor backup, before the irreversible wipe). |
| `S3`/`S13` (app wiring) | `LIL-13`/`LIL-36` | `eee6fd67` | App-level — no host-side unit test target reaches `AppEnvironment.make()`/`bootstrap()`'s private launch-gate logic (same precedent as `2a`'s `S16`/`S17`); verified by unsigned `xcodebuild build` for both apps (BUILD SUCCEEDED) + the `PauseExplainerDialog` two-button resolution flow (LillistUI, compiles + `Localizable.xcstrings` keys added/orphans removed). |
| `S21` (core) | `LIL-59` | `645e9c80` | `SyncStatusMonitorTests.swift` (+6) — import-axis escalation mirrors the export axis exactly (threshold, streak-resets-on-success, structural-failure-resets, axes-independent, `resetStallState` clears both + forensics). |
| `S21` (coordinator/service wiring) | `LIL-59` | `f628f370` | `MigrationRunnerExecutingTests.swift` (+2), `MigrationRecoveryTests.swift` (+1), `DataStoreResetServiceTests.swift` (+2) — `syncStatusReset` fires only on the successful-completion path, never on failure. |
| `S21` (app wiring) + `S3` (activated `MigrationCoordinator` preflight) | `LIL-59`/`LIL-13` | `2216ea08` | App-level — `SyncStatusMonitor` promoted to a shared stored property on both `AppEnvironment`s; discovered and fixed in the same commit that `MigrationCoordinator` was NEVER given an `accountStateProvider` in production on either platform (only `DataStoreResetService` was) — its own `.replaceICloudWithLocal`/`.replaceLocalWithICloud` account-changed preflights (closed earlier in this same plan) were dead code in production until this commit. Verified by unsigned `xcodebuild build`. |
| `S24` (core) | `LIL-62` | `fae77f8e` | `PauseReasonClassifierTests.swift` (rewritten to drive the new `identityProbe` seam instead of the deleted `setICloudDriveDisabled` setter, +4 new) + `LiveNetworkReachabilityTests.swift` (3 tests) — pre-`start()` default, idempotent `start()`, a live `NWPathMonitor` read completes without hanging. |
| `S24` (app wiring) | `LIL-62` | `137a6d54` | App-level — both apps construct `LiveNetworkReachability` and call `start()` before priming `pauseReason`; verified by unsigned `xcodebuild build`. |

**Commit range:** `b180d4de..137a6d54` — 1 docs (`b180d4de`), 1
`chore(stories)` in-progress move (`1d4668ef`), 10 fix/feat (listed above),
plus a `chore(stories)` done-move landing alongside this report. Full
`LillistCore` suite green **twice in a row** with unmasked exit codes and a
clean grep for the failure markers (1277 tests, 231 suites — up from `2b`'s
1235/228 baseline); LillistUI non-snapshot suite green (83 tests, 17
suites); both apps verified with unsigned `xcodebuild` builds (BUILD
SUCCEEDED) after every app-touching commit.

**Identity-source decision (no council needed — see plan doc §2):**
`FileManager.ubiquityIdentityToken` over `CKContainer.fetchUserRecordID`.
Synchronous, no network, works offline (account switching itself needs no
network), and is Apple's own documented mechanism for this exact "did the
account change" question. The one documented ambiguity
(`ubiquityIdentityToken` reflecting iCloud Drive access specifically, not
bare CloudKit sign-in) is *reused*, not worked around — it's exactly the
signal `S24`'s `iCloudDriveDisabled` needed, one seam serving two findings.

**S3 mismatch-response policy — council vote (unanimous 3/3 in the
ranked-choice runoff, after one deliberation round from an initial 1-1-1
split):** cold launch stays **non-blocking** (extends the existing
`PauseReason.accountChanged` badge/`PauseExplainerDialog` path — mirroring
is already suppressed by construction, so a new blocking gate would buy no
additional safety and would misuse the `OnboardingPresentationModifier`
mechanism, reserved for a structurally-unusable store). Mid-session
detection is **automatic, silent containment** (sever mirroring immediately
via the existing `beginDisable(.now)` primitive, before any prompt — a
non-destructive action, so it doesn't need confirmation). Two resolution
choices, both routed through existing hardened primitives: "Use This
Account" (a new narrowly-scoped, re-validating
`resolveAccountMismatchByRedownloading()` that bypasses the ambient
`accountStateProvider` throw only for this one confirmed call, leaving
`resetAndRedownload()` itself — and therefore `ResetSignalMonitor`'s
automatic peer-triggered path — unconditionally blocked on a real
mismatch) and "Stay Local For Now" (the existing `beginDisable(.now)`,
unmodified). `AccountIdentityStore.adoptCurrentIdentity()` is called only
AFTER either resolution primitive reports success, never before — round-1
deliberation surfaced (independently, by two council seats) that
`PersistenceHost.configuration(for:)` silently defaulted
`armsCloudKitMirroring` back to `true` on every structural swap, which
would have let an early-adopted identity re-arm mirroring against a
still-mismatched store on a mid-reset failure; fixing that defect (this
plan's Fix 1) closes the leak at its root rather than relying on
adoption-ordering alone as the only safety mechanism. Full audit trail:
`.council/s3-account-mismatch-response-policy/DECISION.md` (gitignored
plugin-state directory — not committed to git, same as every prior
council's `.council/<slug>/` artifacts in this program; the DECISION
summary above is the durable record).

**Two corroborated `PersistenceHost` leaks closed as binding parts of the
council decision (not just the presentation question):**
1. `configuration(for:)` now captures and threads `armsCloudKitMirroring`
   as its own stored property (same treatment as `storeURL`/
   `cloudKitContainerIdentifier`) instead of hand-rebuilding a
   `StoreConfiguration` via the raw initializer, whose default is `true`.
   Every `reconfigure`/`rebuildEmptyStore`/`reattachStore`/`attachStore`
   call now preserves whatever the host was originally constructed with.
2. `resolveAccountMismatchByRedownloading()`'s failure path reuses
   `performReset`'s existing unconditional `reattachStore()` handling —
   once Fix 1 landed, no separate "mirroring-suppressed reattach variant"
   was needed (an earlier council-deliberation proposal, superseded once
   Fix 1's existence was settled): the host's own `armsCloudKitMirroring`
   is already `false` for the one call path where a stale-account failure
   reattach would otherwise be dangerous.

**Discovered, out-of-scope residual — filed as `LIL-81`, not fixed here
(per the `LIL-77` precedent):** `MigrationCoordinator.restoreFromBackup`
(the raw-SQLite migration-crash-recovery restore — a different subsystem
from the JSON-package `BackupRestoreService`) still has no
`accountStateProvider` check anywhere in its body before
`host.attachStore(at: prev)`. The `2b` closing report flagged this exact
gap for `3a`'s consideration ("`restoreFromBackup` currently has no
equivalent account-changed pre-flight; consider whether it needs one");
after tracing it, the compound scenario it protects against (a migration
crashes, THEN the account changes before the user triggers recovery, AND
`previousMode == .iCloudSync`) is narrow enough, and adding it would touch
`restoreFromBackup`'s core ordering again with its own new test coverage,
that it's better filed than silently expanded into an already-large plan.
Fix shape recorded on the story.

**No other council votes needed beyond the one above** — the identity-source
decision, the `PersistenceHost` fix's exact placement, and `S24`'s
setter-removal were all direct calls per the plan doc's own reasoning (see
§2, §5, §6) — none met the "2+ genuinely defensible alternatives" bar.

**What `3b` (`reset-propagation-safety`, the next plan to touch
`AppEnvironment.swift`/the account-identity seam) needs to know:**
- `AccountIdentityStore`/`AccountIdentityProbing`/`AccountIdentityToken`
  (`Sync/AccountIdentityStore.swift`) are the new canonical identity
  primitives. Both apps construct one `AccountIdentityStore` in `make()`
  and store it as `environment.accountIdentityStore` — if `3b`'s
  reset-propagation work ever needs to reason about "did the account
  change" (e.g. should a propagated `ResetControlEvent` from a peer be
  trusted differently after a local account switch), this is the
  synchronous, already-injectable seam to consult — don't reinvent a
  parallel check.
- `MigrationCoordinator` and `DataStoreResetService` now BOTH receive the
  same `accountStateProvider` closure in both apps (`accountStateProbe`,
  defined once per `AppEnvironment.swift` ahead of both constructions) —
  if `3b` adds a new destructive-op type, wire it the same way rather than
  duplicating the closure.
- `SyncStatusMonitor` is now a stored property on both `AppEnvironment`s
  (`environment.syncStatusMonitor`), no longer constructed inline inside
  `CloudKitSyncStatusAdapter`. If `3b`'s reset-propagation work needs to
  observe or reset sync health (e.g. clearing stall state when a peer's
  reset event applies), this is the instance to use —
  `ResetSignalMonitor`'s automatic-apply path (`resetAndRedownload()`) will
  itself trigger `resetStallState()` via `DataStoreResetService`'s existing
  wiring, so no new plumbing should be needed there specifically.
- `resolveAccountMismatchByRedownloading()` established the "narrow,
  re-validating bypass method, ambient method stays unmodified" pattern
  for letting a confirmed user action route around a safety preflight
  without weakening it for automatic/peer-triggered callers. If `3b`'s
  `S10` product decision (remote reset events never auto-applied, but an
  expiry window is still worth a council-decided duration) needs a similar
  "confirmed user choice bypasses an ambient guard" shape, this is the
  precedent to follow.
- `LIL-81` (the `restoreFromBackup` account-changed gap) and `LIL-77` (the
  pre-existing `CrashReportingSection`/`AppEnvironment.crashPromptsEnabled`
  persistence gap from `1d`) are both still open, unrelated to `3b`'s named
  findings — don't accidentally fold them into `3b`'s scope without a
  deliberate decision to do so.

---

## Wave 3b closing report (`reset-propagation-safety`)

Plan doc: `docs/superpowers/plans/2026-07-28-plan-3b-reset-propagation-safety.md`
— contains the full always-prompt state diagram (detected → pending-decision
→ confirmed/declined/expired/dead-letter), the `BroadcastOutcome` design
(shared by `S20`/`S9c`), and the `X11` watermark clear-list enumeration.

| Finding | Story | Fix commit | Regression test(s) |
|---|---|---|---|
| `S10`, `S22` (`isApplying` race + `ControlInbox`/`AppliedEventStore` halves) | `LIL-33`, `LIL-60` | `d3897ee7` | `ResetSignalMonitorTests.swift` (rewritten in full — every existing test asserted the auto-apply behavior the fix removes, per the `2a`-established two-hats carve-out for this exact situation — +expiry boundary tests, local-only-discard tests, dead-letter tests, stream tests) + `ResetSignalMonitorGateTests.swift` (rewritten for the `refreshPendingDecision()`/`confirmApply()` split) |
| `S20`, `S9c`, `X11` (`DataStoreResetService` side) | `LIL-32`, `LIL-58`, `LIL-42` | `0875470d` | `ResetPropagatorTests.swift` (+2), `DataStoreResetServiceTests.swift` (+8: broadcast-outcome assertions on existing tests, new `rosterEmpty`/quiesce-timeout/local-only-broadcasts tests, new X11 watermark/widget-cache-clear-count tests), new `HistoryWatermarksTests.swift` (3 tests), `WidgetSnapshotStoreTests.swift`/`WidgetSnapshotBuilderTests.swift` (+4) |
| `S19`, `X11` (`MigrationCoordinator` side) | `LIL-56`, `LIL-57` | `bd6fe02f` | `CloudKitErrorClassifierTests.swift` (+3), `MigrationRunnerExecutingTests.swift` (+9: X11 watermark/widget-cache gating by op, `remoteZoneHasRecords` guard incl. fail-open, `retryFailedOperation` dispatch table for all 4 `ModeTransitionOp`s + no-recorded-op throw) |
| `S18` + app-layer wiring for all seven findings | `LIL-56`(app half) | `89c34aa0` | App-level — no host-side unit test target reaches `AppEnvironment.bootstrap()`'s private wiring or the `PendingResetDecisionDialog` sheet flow (same precedent as `2a`'s `S16`/`S17` and `3a`'s app-wiring rows); verified by unsigned `xcodebuild build` for both apps (BUILD SUCCEEDED, including `LillistWidget`/`ShareExtension-iOS` on iOS and `LillistWidget-macOS` on macOS) |

**Commit range:** `9843f6fc..4d492c9e` — 1 docs (`9843f6fc`), 4 feat/fix
(`d3897ee7`, `0875470d`, `bd6fe02f`, `89c34aa0`), 2 `chore(stories)` (the
in-progress moves folded into the working tree, plus `4d492c9e`'s done-move).
Full `LillistCore` suite green **twice in a row** with unmasked exit codes
and a clean grep for the failure markers (1314 tests, 232 suites — up from
`3a`'s 1277/231 baseline). One `SIGABRT`/`-[__NSCFSet addObject:]: attempt to
insert nil` Core-Data-internal-exception crash hit on the first full-suite
attempt after the app-wiring commit — matches the documented parallel-test-
flake class (`CLAUDE.md`'s "heavy concurrent in-memory store creation
intermittently SIGSEGVs inside Core Data" note, same root cause — CPU/thread
contention under `--parallel --num-workers 2`, not a manifestation new to
this plan's changes), cleared on retry per the documented policy, then
re-confirmed clean twice more. LillistUI non-snapshot suite green (83 tests,
17 suites, unchanged from baseline — this plan added no new LillistUI
tests, only new views/types covered by the app-level build verification).

**Always-prompt design, delivered exactly as specified in the plan doc:**
`ResetSignalMonitor` is now an `actor`. `refreshPendingDecision()` (replaces
the old auto-applying `checkAndApply()` — every call site in both apps
updated) only ever classifies each pending `ControlInbox` event into one of
four terminal fates — pending (surfaced via `pendingDecisionStream`),
expired (180-day council-decided window, acked+discarded silently),
not-syncing (this device is `.localOnly`, acked+discarded with a
`discardNoticeStream` notice), or dead-lettered (undecodable payload,
quarantined into the new `ResetEventDeadLetterStore`) — and never applies
anything. `confirmApply()` is the **only** path that ever invokes the
injected `apply` closure (`DataStoreResetService.resetAndRedownload()` in
production), and it's called exclusively from the new
`LillistUI.PendingResetDecisionDialog`, reached via a new banner row in
`ICloudSyncSettingsSection` (mirrors `divergenceWarning`/`recoveryAdvisory`'s
existing visual pattern) and a new `SyncSheetRoute.pendingResetDecision`
case on both platforms. Confirming applies once and acknowledges **every**
currently-pending event, not just the one shown, since they all resolve to
the identical "converge to current iCloud state" action. "Not Now" is
purely a UI-local dismiss — no monitor call — so the event stays live and
re-offerable, extending the `S3`-established "non-blocking dialog must stay
genuinely persistent" precedent rather than inventing new state.

**Council vote (round 1, unanimous 3/3, no deliberation needed):** the
`S10` expiry-window duration — **180 days**. Full audit trail:
`.council/reset-event-expiry-window/DECISION.md` (gitignored plugin-state
directory, same as every prior council in this program). Rationale in
brief: since apply is always user-confirmed, the two failure directions are
asymmetric — a too-short window silently defeats the actual convergence
mechanism issue #71 built (a bare CloudKit zone delete does not "stick" on
its own), while a too-long window costs almost nothing (cheap KVS entries,
rare/deliberate resets, still requires an explicit tap). 90 days sits at
the edge of the brief's own stated "weeks to a few months" secondary-device
dormancy window rather than comfortably past it; 180 days clears it with
real margin while remaining a genuine bound.

**X11's precise scope, re-verified against current source (not assumed
from the finding's prose):** only `DataStoreResetService.performReset`
(every flavor) and `MigrationCoordinator`'s `.replaceLocalWithICloud` op
actually destroy/rebuild the local store (`host.rebuildEmptyStore()`); the
other three migration ops (`.replaceICloudWithLocal`, `.syncFirstThenDisable`,
`.disableNow`) tear down and reattach the **same** on-disk file, so their
watermarks stay valid and must not be cleared — verified this distinction
with dedicated tests (`replaceICloudWithLocalNeverClearsWatermarks`,
`disableNowNeverClearsWatermarks`) proving the gate, not just the
positive case.

**New type `HistoryWatermarks`
(`Persistence/HistoryWatermarks.swift`)** — deliberately narrow, hand-
maintained seam bundling the three `PersistentHistoryTokenStore` consumers
(`RemoteChangeReconciler`/`DiagnosticHistoryObserver`/`LocalBackupCoordinator`)
plus `HistoryPruner`'s own bookkeeping key (verified via source read that
`HistoryPruner.sweep()` never actually reads its own key back to resume —
stale-but-inert today, cleared anyway for hygiene/correctness-by-
construction). **This is the forward-reference seam chain 6 flagged for
`5c`** (`watermark-registry-pruning`) to formalize into a real
`WatermarkRegistry` — `5c` should replace `HistoryWatermarks` with the
registry rather than building a second, parallel mechanism.

**New type `BroadcastOutcome`
(`Sync/ResetPropagator.swift`)** — `.notConfigured`/`.notified(peerCount:)`/
`.rosterEmpty`/`.skippedQuiesceTimedOut`. One type deliberately serves both
`S20` (roster-empty visibility) and `S9c` (quiesce-timeout visibility)
since both are "the destructive op itself succeeded locally, but peers
were not told" with the same UI-facing shape. `resetEverywhereToEmpty()`/
`resetAndReseedFromThisDevice()` both changed return type from `Void` to
`BroadcastOutcome`; `resetAllData()`/`resetAndRedownload()` (the two
non-propagating flavors) are unchanged.

**S19's "Try Again" fix, traced to its actual production wiring (not
assumed):** `Apps/*/Sources/App|Preferences/LillistApp.swift`'s
`onTryAgain` closure previously only called `migrationJournalStore.clear()`
and dismissed — never re-invoking anything. New
`MigrationCoordinator.retryFailedOperation(from:storeURL:)` clears the
journal (required — `runMigration`'s reentrancy guard treats `.failed` as
"already in progress") then dispatches back through `beginEnable`/
`beginDisable` per the journal's recorded `ModeTransitionOp`, so a partial
zone erase (or any other partially-completed step) is genuinely re-attempted
from the top. Both apps' `onTryAgain` now mirror the existing
`ICloudUnavailableScreen` catch→re-check-journal→re-present-or-dismiss shape.

**Discovered, out-of-scope residual — not fixed here (flagged per the
`LIL-77`/`LIL-81` precedent):** `recoverInterruptedReseed()`'s resume
branch never calls `propagator?.broadcast(...)`, crashed-or-not — a
crash-recovered reseed never notifies peers even after this plan's `S9c`
fix to the primary (non-crashed) path. Narrow, pre-existing, worth a
future wave.

**No deviations from the plan doc's commit plan beyond the documented
"group by mechanism, not strict per-finding" pattern `2a` already
established** — `MigrationCoordinator.swift` in particular carries three
findings' worth of changes (`X11` gating, `S19`'s `remoteZoneHasRecords`
guard, `S19`'s `retryFailedOperation`) in one commit because they're
adjacent, overlapping edits to the same `runMigration`/init region; splitting
them via `git add -p` would have been high-risk surgery for no real
audit-trail benefit given every finding still has a named regression test
traceable via the table above.

**What `4a` (`history-consumer-discipline`, opens chain 4 —
`RemoteChangeReconciler.swift` — and continues chain 6 alongside `5c`) needs
to know:**
- `ResetSignalMonitor`'s constructor gained `currentSyncMode`/`deadLetters`/
  `clock` parameters (all defaulted for source compat) — if `4a`'s
  `DrainGate`/watermark-after-success work touches anything that also
  constructs test fakes sharing this monitor's patterns, match the new
  `clock: { Self.fixedNow }` test-fixture discipline (a fixed historical
  `requestedAt` combined with the real system clock now falls outside the
  180-day expiry window — every `ResetSignalMonitorTests`/
  `ResetSignalMonitorGateTests` construction needed an explicit `clock:`
  override to avoid events reading as pre-expired under today's date).
- `HistoryWatermarks` (`Persistence/HistoryWatermarks.swift`) is the
  seam `5c`'s `WatermarkRegistry` should absorb — see its own doc comment
  and the X11 section above. Don't build a second registry mechanism
  alongside it.
- Both `AppEnvironment.swift`s' `bootstrap()` gained two new observer
  registrations (`startObservingPendingResetDecision()`/
  `startObservingResetEventDiscardNotice()`) right after
  `resetSignalMonitor.start()`, and a `quarantine.cleanupExpired()` call
  right after the `TreeIntegrityChecker.repair` block — re-Read the current
  `bootstrap()` ordering before inserting anything new near there.
- `MigrationCoordinator`/`DataStoreResetService` both gained
  `historyWatermarksReset`/`widgetCacheReset` closure parameters (plain
  `(() async -> Void)?`, deliberately **not** `@Sendable` — both types are
  already `@MainActor`-isolated, so no Sendable-capture gymnastics are
  needed, and capturing `[weak self]` for these closures inside `init`
  would violate Swift's definite-initialization rules since many stored
  properties aren't assigned yet at that point in `AppEnvironment.init` —
  capture the specific already-assigned property value into a local instead,
  as both `AppEnvironment.swift`s now do for `widgetRefreshForReset`).

---

## Wave 4a closing report (`history-consumer-discipline`)

Plan doc: `docs/superpowers/plans/2026-07-28-plan-4a-history-consumer-discipline.md`
— contains the full watermark-ordering sequence diagram, the `DrainGate`
class diagram, and the `transactionAuthor` semantics decision writeup.
Deliberately the smallest plan in the program (two findings, one shared
mechanism).

| Finding | Story | Fix commit | Regression test(s) |
|---|---|---|---|
| `H6` | `LIL-24` | `40bd3895` | `RemoteChangeReconcilerTests.swift` (+2): `watermarkAdvancesOnlyAfterCallbackCompletes` (an actor spy reads `tokenStore.lastToken` from *inside* the callback and asserts it's still `nil` — proves the ordering mechanism directly, not just end-state) + `usesInstanceTransactionAuthorNotHardcodedDefault` (a controller built with `macAppTransactionAuthor` writes `lastFiredAt` through its own context; asserts `onAffectedTasks` is never called — red under the old hardcoded-`localTransactionAuthor` comparison). |
| `M3` (`RemoteChangeReconciler` half) | `LIL-47` | `5078cbfd` (extraction) + `84f77d85` (adoption) | `DrainGateTests.swift` (6 tests, the extracted type's own contract) + `RemoteChangeReconcilerTests.concurrentCallsProcessEachChangeExactlyOnce` — 24 concurrent `processPendingHistory()` calls; verified genuinely red first (192 = 24×8 task-ids reconciled, one full independent pass per call) by temporarily reverting the source file to the pre-M3 commit, then green (exactly 8) after re-applying. |
| `M3` (`TaskDuplicateReconciler` half) | `LIL-47` | `84f77d85` | `TaskDuplicateReconcilerTests.concurrentCallsCollapseIntoBoundedPasses` — an intentionally ambiguous/never-resolving duplicate group + a call-counting `MirroredObjectIdentifying` wrapper; verified red first (24 concurrent calls → exactly 24 full-table passes, one per call, no coalescing), green after (a small, bounded count). |

**Commit range:** `40bd3895..a809d74b` — 1 fix (`40bd3895` H6), 1 refactor
(`5078cbfd` DrainGate extraction), 1 fix (`84f77d85` M3 adoption in both
consumers), 1 `chore(stories)` (`a809d74b`). Full `LillistCore` suite green
**twice in a row** with unmasked exit codes and a clean grep for the failure
markers (1324 tests, 233 suites — up from `3b`'s 1314/232 baseline). One
`SIGSEGV`/signal-11 crash (`exited with unexpected signal code 11`) hit on
the first full-suite attempt right after the DrainGate refactor commit —
matches the documented parallel-test-flake class (CLAUDE.md's "heavy
concurrent in-memory store creation intermittently SIGSEGVs inside Core
Data" note), cleared on retry, then the M3 commit's own two-in-a-row
verification ran clean with no further flakes. Unsigned `xcodebuild` build
for `Lillist-iOS` (BUILD SUCCEEDED) — the only app-target file touched.

**Two-hats discipline, strictly separated across three code commits** (per
the wave brief's explicit "one commit per completed red→green cycle"
requirement): `40bd3895` is the H6 behavior fix in isolation (no `DrainGate`
yet — `processPendingHistory` still runs unguarded, single-flight, exactly
as before this plan except for the ordering/author/fail-loud fix);
`5078cbfd` is a pure mechanism move with zero behavior change
(`DiagnosticHistoryObserverTests` pass unchanged); `84f77d85` is the M3
behavior fix, adopting the now-extracted gate in both consumers. Each commit
was verified independently before the next began.

**Verification method for both M3 regression tests — red confirmed against
the actual pre-fix code, not assumed:** for `RemoteChangeReconciler`, the
already-committed post-H6 version of the source file was checked out via
`git checkout HEAD -- <file>` (safe: the M3 changes existed only as an
uncommitted working-tree diff at that point, saved first via `git diff HEAD
-- <file> > /tmp/rcr_m3.patch` and re-applied with `git apply` after
confirming red), then the M3 test was run and failed exactly as predicted
before the source changes were restored. `TaskDuplicateReconciler`'s test
was written and run against the then-current (pre-fix, no gate) source
directly, since that file had no other uncommitted changes to protect.

**The `transactionAuthor` decision (H6, §1b of the plan doc) — decided
directly, no council invoked:** `processPendingHistory` now compares against
`persistence.transactionAuthor` (this specific `PersistenceController`
instance's own stamped value) instead of the hardcoded
`PersistenceController.localTransactionAuthor` default. Same-device,
cross-process writes (a future extension-authored `NotificationSpec`
change) stay classified as **foreign** — this process's in-memory
`NotificationScheduler` state cannot have observed a write a different OS
process made, so the correct binary is "authored by this specific
controller instance" vs. everything else, which is exactly what the fix
produces. No production behavior changed today (only iOS constructs a
`RemoteChangeReconciler`, always with the default author) — this closes a
latent footgun for `4b`, which is expected to give macOS its own instance
with `macAppTransactionAuthor`.

**Correctness vs. thrash for `TaskDuplicateReconciler`'s M3 half — verified
against the actual mechanism, not assumed:** `NSManagedObjectContext.perform`
serializes execution on the context's own private queue, so concurrent
calls into `reconcileDuplicates` (one `ctx.perform` block each) cannot
interleave or corrupt state even without `DrainGate` — confirmed by the
regression test's own shape (an *ambiguous, never-resolving* duplicate
group was needed to get a stable, repeatable call count; a resolvable one
would only ever call the mirror identifier once regardless of concurrency,
since the first pass to run would merge it away for every later pass). The
fix here is real but non-functional (thrash reduction), unlike
`RemoteChangeReconciler`'s half, where the watermark write sits *outside*
the `ctx.perform` block it reads from and the race is a genuine correctness
defect.

**Discovered, out-of-scope residual — not fixed here (flagged per the
`LIL-77`/`LIL-81` precedent):** `TaskDuplicateReconciler.diagnosticLog`
(added by `1a`'s M5 fix) is never wired in either `AppEnvironment.swift` —
`taskDuplicateReconciler` is constructed and started in both apps, but
nothing ever assigns its `diagnosticLog`, so an M5 reconcile failure today
logs via `os.Logger` only and never reaches the structured diagnostic
stream. Adjacent to this plan's own `RemoteChangeReconciler.diagnosticLog`
wiring but a distinct, pre-existing gap from a different wave's fix — not
part of either `H6` or `M3`'s mechanism, left for the `6a` completeness
sweep.

**What `4b` (`notification-truthfulness`) needs to know:**
- `RemoteChangeReconciler.processPendingHistory()`'s body is now `private
  func drainOnce()`, wrapped by an acquire/loop pair reading
  `drainGate.tryAcquire()`/`finishOrRerun()`. `4b`'s widened diffing (spec
  inserts/deletes, task soft-deletes per `X9`) belongs inside `drainOnce()`,
  not as a parallel code path — it inherits the watermark-after-success
  ordering and the serialization for free only if it stays inside that
  function.
- `affectedTaskIDs`'s `localAuthor` parameter is now called with
  `persistence.transactionAuthor` at the one production callsite. Any new
  callsite `4b` adds must do the same — never reintroduce the hardcoded
  `PersistenceController.localTransactionAuthor` default.
- `RemoteChangeReconciler` now has a `public var diagnosticLog:
  DiagnosticSink?`, wired in iOS `AppEnvironment.swift` only (macOS still
  has no `RemoteChangeReconciler` — per the ledger's chain-4 note and `X9`,
  `4b` is where that changes). Wire the same property when macOS gains one,
  mirroring the iOS wiring right after `diagnosticLog`'s own construction.
- `Persistence/DrainGate.swift` is the shared serialization primitive for
  *any* `NSPersistentStoreRemoteChange` consumer — one instance per
  consumer instance, never a shared singleton (matches
  `DiagnosticHistoryObserver`'s existing per-instance ownership). A macOS
  `RemoteChangeReconciler` instance `4b` constructs gets its own.
- `TaskDuplicateReconciler.reconcileNow()` (zero-arg) and
  `reconcileNow(mirrorIdentifier:)` (the test seam) both route through the
  same `DrainGate` now — the seam is where the gate lives, so a test
  driving it directly still exercises the real serialization. Don't add a
  new entry point that bypasses it.

---

## Execution model (per Mikey's directives, 2026-07-28)

- **One dedicated worktree** on a long-running branch:
  `/Volumes/Code/mikeyward/Lillist/.claude/worktrees/data-sync-hardening`,
  branch `hardening/data-sync-2026-07`. All fixes land here as small
  conventional commits (two-hats discipline — never mix a behavior fix with a
  refactor in one commit). **One PR at the end; stop after opening it** — no
  merge, no version bump, no deploy from this worktree (standing worktree
  rule: those happen later from `main`).
- **Sequential subagents, Sonnet 5, autonomous.** Each wave (or story
  cluster/plan) is executed by a fresh subagent with a self-contained brief:
  findings + fix-at-origin approach + files + verification commands + commit
  instructions. The orchestrating session never implements directly —
  preserves context for the whole program. Subagents settle 2+-defensible-
  alternative technical questions via `council:council-vote` (Mikey is
  unavailable for the duration of this program).
- **Verification gate per subagent:**
  ```bash
  swift test --package-path Packages/LillistCore --parallel --num-workers 2
  ```
  (+ LillistUI where touched, + unsigned `xcodebuild` builds for app-touching
  plans). Signed/simulator suites attempted per the documented worktree
  procedure (regenerate the gitignored scheme with `xcodegen generate` first,
  then the canonical debug-dylib path + retry-once). iCloud-dependent suites
  (app-hosted live-swap, UI tests) are flagged in this ledger for Mikey's
  post-merge manual verification — see the checklist below.
- **Docs + stories first (Wave 0), before any fix** — done; all 70 stories
  filed as `LIL-7`..`LIL-76` (see the *Story-ID cross-reference table*
  below). Every Wave 1-6 fix commit references its story (`Closes LIL-N` or
  a `story comment`/`story move … done` note, per `.storyhook/CLAUDE.md`).
- **Scope:** everything; waves ordered by severity; lows may be batched
  (Wave 6); wontfix only via an explicit triage note in this ledger, nothing
  dropped silently.
- **Batch-delete finding (`C4`/`X4`):** fix proceeds directly per the
  documented Apple limitation (mirrored-context deletes replace batch
  deletes) — device verification is opportunistic for Mikey, **not** a gate.

---

## Wave/plan table

14 plans across Waves 1-6, plus Wave 0 (this wave, docs/stories only) and a
Wave 6 closeout. **Status** starts `pending` for everything except Wave 0.

| Wave | Plan | Findings (IDs) | Status |
|------|------|-----------------|--------|
| 0 | *(docs + stories, no code)* | — | ✅ complete |
| 1 | **1a** `trash-tree-integrity` | `C1 C2 C3 M1 M2 H4 H7 M5` | ✅ complete |
| 1 | **1b** `purge-cloudkit-retirement` | `C4`/`X4` (merged), `X14`, `H3` | ✅ complete |
| 1 | **1c** `store-location-unification` | `X1 X2 X15` (+ iOS silent `defaultOnDisk` fallback detail, folded into the `X1`/`X2` story bodies — no separate ID) | ✅ complete |
| 1 | **1d** `export-schema-completeness` | `X3 S9a X13 X18` | ✅ complete |
| 2 | **2a** `migration-transitions` | `S1 S5 S6 S8 S11 S12 S14 S15 S16 S17` | ✅ complete |
| 2 | **2b** `backup-restore-correctness` | `S2 S4 S7 S9b S23` | ✅ complete |
| 3 | **3a** `account-identity-and-status` | `S3 S13 S21 S24` | ✅ complete |
| 3 | **3b** `reset-propagation-safety` | `S10 S18 S19 S20 S22 X11 S9c` | ✅ complete |
| 4 | **4a** `history-consumer-discipline` | `H6 M3` | ✅ complete |
| 4 | **4b** `notification-truthfulness` | `H2 X8 X9 X10` | ⬜ pending |
| 4 | **4c** `recurrence-correctness` | `H1 X7 X16 X17` | ⬜ pending |
| 5 | **5a** `mutation-scope-discipline` | `H5 M4 M6 M7 L3 L4 L5 X19 X20` | ⬜ pending |
| 5 | **5b** `widget-snapshot-correctness` | `X5 X6` | ⬜ pending |
| 5 | **5c** `watermark-registry-pruning` | `X12 L7` | ⬜ pending |
| 6 | **6a** `completeness-and-lows` + closeout | `L1 L2 L6` + export round-trip equality suite + `X20` flip-flop stress (builds atop 5a's fix, not a new finding) + any residuals from Waves 1-5, incl. `LIL-77` (discovered during `1d`, not one of the 70 findings) | ⬜ pending |

**Finding-count check:** 70 unique findings (`C1`-`C4`, `H1`-`H7`, `M1`-`M7`,
`L1`-`L7` from the stores sweep = 25; `S1`-`S4`, `S5`-`S13` with `S9` split
into `S9a`/`S9b`/`S9c` (11), `S14`-`S24` from the sync sweep = 26; `X1`-`X5`,
`X6`-`X13`, `X14`-`X20` from the cross-process sweep = 20; minus 1 for the
`C4`/`X4` merge = **70**). Every row above sums to 70 with no ID appearing in
two rows (except `X20`, whose *fix* lives in 5a and whose *additional stress
test* is called out again in 6a as follow-on hardening — one story, one
owning plan: 5a).

## Class-killer verdicts

New public types below get a type-system proposal + UML diagram in their
landing wave's plan doc (house rule) before implementation:

| Move | Verdict | Wave/Plan |
|---|---|---|
| Canonical `StoreLocation` resolver + multi-process pin test | Adopt | 1c |
| `TreeIntegrityChecker` (launch self-heal + post-mutation assertions) | Adopt | 1a |
| `DrainGate` extraction (public) + `WatermarkRegistry` (min-watermark prune) | Adopt, split | 4a + 5c |
| Full `MutationContext` re-architecture | **Reject** → `withMutationRollback` helper + conformance test + logged tech debt | 5a |
| Model-derived export-completeness test (walks `NSManagedObjectModel`) | Adopt — delivered | 1d |
| `DestructiveOpGate` (shared, synchronous-acquire lock replacing `MigrationCoordinator.isMigrating`/`DataStoreResetService.isResetting`) | Adopt — delivered | 2a |
| `AccountIdentityStore` (persisted `ubiquityIdentityToken`-based identity comparison, gates launch-time CloudKit mirroring) | Adopt — delivered | 3a |
| `LiveNetworkReachability` (`NWPathMonitor`-backed actor, canonical single implementation vs. one-per-app-target) | Adopt — delivered | 3a |
| `ResetSignalMonitor` actor conversion (always-prompt state machine — `apply` is structurally unreachable except via explicit `confirmApply()`, replacing the prior class of "an automatic peer-triggered apply can run without confirmation" bugs) | Adopt — delivered | 3b |

---

## Shared-file serial chains (re-anchor by structure, not line number)

Every plan sharing a hotspot file **re-Reads it first** and anchors by code
structure — each earlier plan in the chain will have moved line numbers.

1. **`TaskStore.swift`** — `1a` (trash/restore state machine) → `1b` ✅ done
   (purge logic extracted into `TrashPurger`; `batchPurge` is now a thin
   wrapper; `hardDelete` collects a notification-cancellation closure via
   `CascadeReaper.objectIDs(forDeleting:)`) → `4b` (descendant notification
   reconcile — next link) → `5a` (mutation-rollback helper adopted across
   its mutators). Four plans, one file — serialize strictly in this order.
2. **`MigrationCoordinator.swift`** — `2a` ✅ done (`host` widened to
   `PersistenceReconfiguring & PersistenceResetting`; per-op step sequence
   redesigned — see the plan doc's state-machine table; `destructiveOpGate`
   stored property replaces `isMigrating`; `quiesceMinQuietWindow`/
   `quiesceHardTimeout` are now injectable constructor params;
   `restoreFromBackup` also acquires the gate, as `Owner.restore`) → `2b`
   ✅ done (`restoreFromBackup` now tearDown→file-swap→`attachStore(at:)`,
   never `reconfigure`; the same tearDown+`attachStore` shape replaces
   `reconfigure` for `replaceICloudWithLocal`/`syncFirstThenDisable`/
   `disableNow` too — `replaceLocalWithICloud` is the only op still calling
   `reconfigure`; catch-block reattach is now unconditional across all four
   ops) → `3a` ✅ done (gained an activated `accountStateProvider` in
   production for the first time on both platforms — it existed as a
   constructor param since `2a` but neither `AppEnvironment.swift` ever
   passed one; `.replaceLocalWithICloud` gained the account-changed
   preflight `.replaceICloudWithLocal` already had, at the same relative
   position after the recovery-anchor backup; `restoreFromBackup`/
   `runMigration` both gained a `syncStatusReset` closure called on their
   successful-completion path only — see the *Wave 3a closing report* for
   the full shape). `restoreFromBackup` itself still has NO
   `accountStateProvider` check — filed as `LIL-81`, not fixed in `3a`,
   still open for a future plan. → `3b` ✅ done (`.replaceLocalWithICloud`
   gained a `remoteZoneHasRecords` pre-flight — symmetric to the existing
   `localStoreRowCount` guard — right before `host.rebuildEmptyStore()`,
   throwing `LillistError.iCloudDataEmpty`; the same op-gated success path
   also now calls `historyWatermarksReset`/`widgetCacheReset` closures,
   `.replaceLocalWithICloud`-only; new
   `retryFailedOperation(from:storeURL:)` re-dispatches a failed journal's
   recorded op back through `beginEnable`/`beginDisable` — see the *Wave 3b
   closing report* for the full shape). Four plans, all done.
3. **`PersistenceHost.swift`** — `2a` ✅ done (`flushAndSwap` throws instead
   of silently succeeding with zero attached stores) → `2b` ✅ done (new
   `attachStore(at:)` on `PersistenceResetting` — attaches fresh at an
   explicit mode, always updating `currentMode`, never a no-op; all four
   conformers implement it). Two plans, both done.
4. **`RemoteChangeReconciler.swift`** — `4a` ✅ done (`processPendingHistory`'s
   body is now `private func drainOnce()`, wrapped by a `DrainGate`
   acquire/loop pair; the watermark advances only after `affectedTaskIDs`
   AND `onAffectedTasks` have both completed; `localAuthor` is now
   `persistence.transactionAuthor`, not the hardcoded
   `PersistenceController.localTransactionAuthor`; new `public var
   diagnosticLog: DiagnosticSink?`) → `4b` (spec insert/delete + soft-delete
   reconcile added on top of `4a`'s corrected watermark discipline, inside
   `drainOnce()` — see the *Wave 4a closing report* for the exact shape and
   what `4b` needs to preserve).
5. **`AppEnvironment.swift`** (both iOS and macOS copies — distinct regions,
   serialize per-platform) — `1c` ✅ done (canonical `StoreLocation` wiring;
   macOS App-Group migration; macOS's `AppEnvironment` gained a new
   `macAppGroupMigrationOutcome` stored property logged at the top of
   `bootstrap()` — see the *Wave 1c closing report* for exactly where) →
   `2b` ✅ done, not originally on this chain but landed here anyway
   (backup-subsystem construction — `backupSnapshotManager`/
   `localBackupCoordinator` — moved BEFORE `dataStoreReset` so it can be
   injected as `backupReconciler`; `reseedJournal` construction added
   alongside `quarantine`; `bootstrap()` gained a
   `recoverInterruptedReseed()` best-effort call as its first line — see
   the *Wave 2b closing report* for the exact diff shape) → `3a` ✅ done
   (`make()` gained the `AccountIdentityStore.check()` call ahead of
   `PersistenceController` construction — the launch-sequence integration
   point, see the plan doc's diagram; `bootstrap()` gained
   `networkReachability.start()`, `accountStateMonitor
   .startObservingSystemAccountChanges()`, and a new
   `startObservingMidSessionAccountMismatch()` observer, all added AFTER
   the existing `recoverInterruptedReseed()`/`preferencesPartitionMigrator`
   first lines — re-Read `bootstrap()`'s full current ordering before
   prepending anything; `SyncStatusMonitor` promoted to a stored property,
   no longer constructed inline inside `CloudKitSyncStatusAdapter`) → `3b`
   ✅ done (`resetSignalMonitor` construction gained `currentSyncMode`/
   `deadLetters` params; `quarantine` promoted from a local to a stored
   property; `bootstrap()` gained a `quarantine.cleanupExpired()` call
   right after `TreeIntegrityChecker.repair` and two new observer
   registrations — `startObservingPendingResetDecision()`/
   `startObservingResetEventDiscardNotice()` — right after
   `resetSignalMonitor.start()`; `migrationCoordinator`/`dataStoreReset`
   construction both gained `historyWatermarksReset`/`widgetCacheReset`/
   (`migrationCoordinator` only) `remoteZoneHasRecords` closures, built
   from a new `HistoryWatermarks` instance + `WidgetRefreshCoordinator
   .resetAfterDestructiveOp()` — see the *Wave 3b closing report* for the
   exact diff shape and the definite-initialization gotcha it hit) → `4b`
   (notification scheduler reaching extension/widget/CLI paths via 1c's
   standardized construction).
6. **`HistoryPruner.swift` + the three history-token `UserDefaults` keys** —
   `3b` ✅ done, landed AHEAD of `5c` (the reverse of the originally-planned
   order — see below) — new `HistoryWatermarks`
   (`Persistence/HistoryWatermarks.swift`) bundles the three
   `PersistentHistoryTokenStore` consumers + `HistoryPruner`'s own
   bookkeeping key and is wired into `DataStoreResetService`'s every reset
   flavor + `MigrationCoordinator`'s `.replaceLocalWithICloud`. **Deviation
   from the plan doc's originally-sketched ordering:** the ledger's own
   pre-`3b` note said "land `5c`'s registry first structurally, `3b`
   consumes it" — in practice `3b` landed a deliberately narrow, hand-
   maintained `HistoryWatermarks` seam directly (not a stub against a
   not-yet-built registry) rather than block Wave 3 on pulling `5c`
   forward out of wave order. `5c` (`watermark-registry-pruning`) should
   now **replace** `HistoryWatermarks` with the formal `WatermarkRegistry`
   (min-over-consumers pruning) rather than build a second, parallel
   mechanism — see `HistoryWatermarks`' own doc comment, which says this
   explicitly.
7. **`Importer.swift` + `Exporter.swift` + `ExportSchema.swift` +
   `BackupSchema.swift`** — `1d` ✅ done (`ExportSchema`/`BackupPackageSchema`
   both at v2; `SeriesDTO`/`NotificationSpecDTO`/`SmartFilterDTO` +
   `TaskDTO.archivedAt`/`.seriesID` + `PreferencesDTO.defaultTagTintHex`,
   all decode-with-default on older bundles; `Importer.apply`'s pass order
   is now tags→tag.parent→tasks→task.parent→series→series.seedTask→
   task.series→journal entries→attachments→notification specs→smart
   filters→save; model-derived completeness test landed) → `2b` ✅ done
   (consumed the completed schema for the min-over-records schema-gate
   fix and the live-package staging guard — see the *Wave 2b closing
   report* for exactly what shape landed).

---

## Resume protocol

A fresh session with zero prior context should be able to continue this
program from this document alone. Steps:

1. **Confirm the worktree.** `pwd` should be
   `/Volumes/Code/mikeyward/Lillist/.claude/worktrees/data-sync-hardening`;
   `git branch --show-current` should be `hardening/data-sync-2026-07`. If
   not, use `EnterWorktree` — **never** work on this program from the main
   checkout or a different worktree.
2. **Read, in order:** this file (current status + next action, above) →
   `docs/reviews/2026-07-28-data-sync-review.md` (why this work exists;
   finding IDs, file:line anchors, severities, product decisions) → the
   current wave's plan doc if one exists yet (`docs/superpowers/plans/2026-07-28-<plan-slug>.md`
   — plan docs are written **as each wave starts**, not all up front, per the
   Foundation Hardening precedent this program is modeled on).
3. **Check story state:** `story summary` / `story list --state in-progress`
   to see what's actively being worked; `story list --label plan-<slug>` to
   pull up a specific plan's stories.
4. **Re-Read every shared hotspot file before editing** — see the *serial
   chains* above; line numbers drift with every landed plan.
5. **Verify the previous wave's claimed-green state** before building on it:
   `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --package-path Packages/LillistCore --parallel --num-workers 2`
   (retry once on a known flake per `CLAUDE.md`'s documented parallel-test
   flakes section — do not treat a single SIGSEGV/timing flake as a real
   failure without a re-run).
6. **Execute the next `⬜ pending` plan** in wave order, respecting the serial
   chains. Fresh subagent per plan (or per story cluster within a plan),
   TDD (red→green regression test per fix), two-hats commit discipline,
   `council:council-vote` for any 2+-defensible-alternative decision.
7. **On plan completion:** flip its status in the *Wave/plan table* above,
   update the *shared-file serial chains* section if line-anchor drift or a
   scope adjustment occurred, append to the *Council-vote log* if one was
   invoked, and update Mikey's manual-verification checklist if the plan
   added a new manual-only verification item.
8. **On wave completion:** write a closing note in this ledger's *Current
   status* section (model on the Foundation Hardening index's per-wave
   status entries) — what landed, commits, test counts, what the next wave's
   executor must know that isn't already captured in the serial chains.
9. **After Wave 6 closes:** final ledger update, open **one PR** with the
   full program description (link the review doc + this ledger), **stop**
   (worktree rule — no merge, no version bump, no deploy from here).

---

## Story-ID cross-reference table

All 70 findings filed as storyhook stories `LIL-7` through `LIL-76`
(2026-07-28). Each story carries the finding description, failure scenario,
file:line anchors, severity (as its priority field), and wave/plan (as a
`plan-<slug>` label), so an implementing agent can work from `story show
LIL-N` alone. Grouped here by plan, in wave order, for quick lookup —
`story list --label plan-1a` (etc.) gets the same set from the CLI directly.

| Plan | Finding ID(s) → Story ID |
|------|--------------------------|
| **1a** trash-tree-integrity | `C1`→`LIL-7`, `C2`→`LIL-8`, `C3`→`LIL-9`, `H4`→`LIL-22`, `H7`→`LIL-25`, `M1`→`LIL-45`, `M2`→`LIL-46`, `M5`→`LIL-49` |
| **1b** purge-cloudkit-retirement | `C4`/`X4`→`LIL-10` (merged), `H3`→`LIL-21`, `X14`→`LIL-63` |
| **1c** store-location-unification | `X1`→`LIL-15`, `X2`→`LIL-16`, `X15`→`LIL-64` |
| **1d** export-schema-completeness | `X3`→`LIL-17`, `S9a`→`LIL-30`, `X13`→`LIL-44`, `X18`→`LIL-67` |
| **2a** migration-transitions | `S1`→`LIL-11`, `S5`→`LIL-26`, `S6`→`LIL-27`, `S8`→`LIL-29`, `S11`→`LIL-34`, `S12`→`LIL-35`, `S14`→`LIL-52`, `S15`→`LIL-53`, `S16`→`LIL-54`, `S17`→`LIL-55` |
| **2b** backup-restore-correctness | `S2`→`LIL-12`, `S4`→`LIL-14`, `S7`→`LIL-28`, `S9b`→`LIL-31`, `S23`→`LIL-61` |
| **3a** account-identity-and-status | `S3`→`LIL-13`, `S13`→`LIL-36`, `S21`→`LIL-59`, `S24`→`LIL-62` |
| **3b** reset-propagation-safety | `S9c`→`LIL-32`, `S10`→`LIL-33`, `S18`→`LIL-56`, `S19`→`LIL-57`, `S20`→`LIL-58`, `S22`→`LIL-60`, `X11`→`LIL-42` |
| **4a** history-consumer-discipline | `H6`→`LIL-24`, `M3`→`LIL-47` |
| **4b** notification-truthfulness | `H2`→`LIL-20`, `X8`→`LIL-39`, `X9`→`LIL-40`, `X10`→`LIL-41` |
| **4c** recurrence-correctness | `H1`→`LIL-19`, `X7`→`LIL-38`, `X16`→`LIL-65`, `X17`→`LIL-66` |
| **5a** mutation-scope-discipline | `H5`→`LIL-23`, `M4`→`LIL-48`, `M6`→`LIL-50`, `M7`→`LIL-51`, `L3`→`LIL-72`, `L4`→`LIL-73`, `L5`→`LIL-74`, `X19`→`LIL-68`, `X20`→`LIL-69` |
| **5b** widget-snapshot-correctness | `X5`→`LIL-18`, `X6`→`LIL-37` |
| **5c** watermark-registry-pruning | `X12`→`LIL-43`, `L7`→`LIL-76` |
| **6a** completeness-and-lows | `L1`→`LIL-70`, `L2`→`LIL-71`, `L6`→`LIL-75`, discovered-during-`1d` residual→`LIL-77` (not one of the 70 review findings — see *Current status* above for the discovery trail) |

**Verification:** 70 findings → 70 stories, one-to-one (the `C4`/`X4` merge
is the one many-to-one mapping, per the council decision above). Cross-
checked against the *Finding-count check* under the Wave/plan table — every
ID appears exactly once across both tables.

---

## Council-vote log

Decisions escalated to `council:council-vote` per the Wave-0 brief (2+
defensible alternatives, Mikey unavailable). Full audit trails live under
`.council/<slug>/` in this worktree.

1. **C4/X4 story granularity** (Wave 0, 2026-07-28) — should the cross-sweep-
   corroborated finding `C4` (stores) / `X4` (cross-process) be filed as one
   merged storyhook story or two linked via `duplicate-of`?
   **Decision: one merged story** (filed as `LIL-10`), by ranked-choice
   majority after one deliberation round. All three seats —
   `project-manager`, `software-architect`, `skeptic` — independently
   proposed merging in round-1 research (before seeing each other's
   reasoning); the round-1 single-choice vote split 2-1 over *which
   proposal's rationale phrasing* to canonize (not over whether to merge),
   triggering deliberation, after which all three proposals converged even
   further and the round-2 ranked-choice runoff resolved with an outright
   majority (2 of 3 first-choice votes) for the skeptic's revised proposal.
   Rationale: the review document itself already treats C4/X4 as one of its
   70 unique findings ("merged into one entry, tagged C4/X4"), and its
   S9→S9a/S9b/S9c split is the mirror-image precedent — split when work is
   genuinely separable, merge when genuinely identical, which C4/X4 is
   (same code change, same file, same wave/plan cell, same verification
   caveat); `duplicate-of` is for duplication discovered *after* the fact,
   not identity known with zero ambiguity at filing time, and using it here
   would manufacture a second, passively-linked ticket at real risk of
   becoming a phantom-open story once the single shared fix ships. Both IDs
   are carried as labels on the one story instead. Dissent: the skeptic
   ranked their own alternate proposal first (a stylistic preference for one
   crisp governing test over an explicit dual-risk enumeration), but by the
   end of deliberation all three proposals recommended the identical filing
   action. Full audit trail:
   `.council/c4-x4-merged-or-two-linked-stories/DECISION.md`.

2. **`H7` cycle-break tie-breaker rule** (Wave 1, plan `1a`, 2026-07-28) —
   which deterministic rule should `TreeIntegrityChecker`'s self-heal use to
   pick which node's parent link to sever when it finds a parent-cycle,
   given the repair runs independently and uncoordinated on every process
   that opens the store?
   **Decision: sever the cycle member with the lexicographically-greatest
   `id.uuidString`** — the same structural tie-break idiom `SiblingOrder`
   already uses — by unanimous ranked-choice majority (3/3 first-place
   votes in the runoff) after one deliberation round. Round 1 was a 1-2-0
   split (`data-engineer` voted their own proposal; `software-architect`
   and `skeptic` voted `software-architect`'s), but both proposals were
   substantively the same rule differing only in supporting rationale. In
   deliberation, `skeptic` went beyond relitigating the existing proposals
   and read `TaskDuplicateReconciler.swift`, discovering the codebase
   already documents a reachable scenario (issue #66) where `id.uuidString`
   is *not* actually tie-free — withdrew their own round-1 `createdAt`-first
   hybrid proposal entirely and converged on id-max as the primary rule,
   but hardened it into a binding implementation requirement: an id-tie
   (two cycle members sharing one `id`) must not be resolved via incidental
   Core Data fetch order — the implementation skips breaking that specific
   cycle and logs, deferring to `TaskDuplicateReconciler` to resolve the
   duplicate first. `data-engineer` and `software-architect` independently
   revised in the same direction (verifying the `Optional<Date>` vs.
   non-optional `UUID` type asymmetry between `createdAt` and `id` from
   source) but only `skeptic`'s revision closed the tie-free-implementation
   gap, and all three seats ranked it first in the runoff. Dissent: none —
   unanimous. Full audit trail:
   `.council/h7-cycle-break-tiebreaker-rule/DECISION.md`. Implemented in
   `TreeIntegrityChecker.breakCycle(_:)`
   (`Packages/LillistCore/Sources/LillistCore/Persistence/TreeIntegrityChecker.swift`),
   tested by `TreeIntegrityCheckerTests.repairSkipsAmbiguousIDTie`.

3. **macOS both-stores-populated migration policy** (Wave 1, plan `1c`,
   2026-07-28) — when the one-time `MacAppGroupMigration` finds BOTH the
   legacy Application-Support store and the App-Group store already
   populated (reachable if this Mac's widget ever ran under the `X1` bug
   and pulled a full CloudKit replica into the App-Group location before
   the fix landed), what should it do?
   **Decision: branch on the device's persisted `SyncMode`** — by
   unanimous ranked-choice majority (3/3 first-place votes) after one
   deliberation round. Round 1 was a 2-1 split: `data-engineer` voted for
   their own "defer indefinitely, mutate nothing, hand off a typed
   conflict signal" proposal; `software-architect` and `skeptic` both
   voted for `software-architect`'s "quarantine + migrate, legacy wins"
   proposal. Neither round-1 proposal survived deliberation unchanged.
   `software-architect` went beyond re-arguing the tradeoff and actually
   read `Extensions/LillistWidget/AdvanceTaskStatusFromWidget.swift` →
   `WidgetIntentSupport` → `GatedPersistenceResolver`/`MigrationGate` →
   `StoreConfiguration.appGroupOnDisk`, discovering that in `.localOnly`
   sync mode the App-Group store has **no CloudKit mirror at all** —
   `cloudKitContainerOptions` is never attached — so the original
   "CloudKit re-flows anything unique to the losing store" risk-bounding
   argument for "legacy wins" was categorically false in that mode, where
   quarantining the App-Group store would be irreversible, unconditional
   loss of a real user action (e.g. a task completed via the widget).
   Revised into a `SyncMode`-conditioned hybrid: `.iCloudSync` keeps
   "quarantine App-Group store, migrate legacy into its place" (CloudKit's
   mirroring genuinely is the convergence mechanism there); `.localOnly`
   switches to "zero file mutation, typed `.conflictDetected` outcome,
   keep booting on legacy" (no convergence mechanism exists to bound the
   risk). `data-engineer`, who had defended indefinite deferral as
   categorically safest, conceded in deliberation that unbounded deferral
   without a forcing function is itself a data-integrity failure mode (the
   migration-equivalent of an untested backup) and dropped their
   opposition once the revised proposal addressed the specific case
   (`.localOnly`) where their concern was actually valid. `skeptic`
   independently surfaced two binding implementation requirements during
   the same round — a `QuarantineManager` same-second folder-naming
   collision (confirmed in source: `Int(clock().timeIntervalSince1970)`
   granularity, `moveItem`/`copyItem` throw on an existing destination,
   and the conflict path makes up to three quarantine/copy calls in one
   synchronous run) and a correction to the original "widget-only edits
   are low-risk" framing (undercut by `X15`'s own ~30MB widget memory
   budget concern, filed in this same plan) — that don't change the
   winning direction but are binding on the implementation. All three
   seats ranked the revised hybrid first, unanimously, in the runoff.
   Dissent: none in the final vote. Full audit trail:
   `.council/macos-migration-both-stores-populated/DECISION.md`.
   Implemented in `MacAppGroupMigration.migrateIfNeeded`
   (`Packages/LillistCore/Sources/LillistCore/Persistence/MacAppGroupMigration.swift`),
   tested by `MacAppGroupMigrationTests.swift`'s
   `migratedResolvingConflict_iCloudSync`/`conflictDetected_localOnly_noMutation`.
   The folder-collision finding was fixed separately in `QuarantineManager`
   (commit `070ba738`) ahead of the migration landing.

4. **S3 account-mismatch response policy** (Wave 3, plan `3a`, 2026-07-28) —
   what should Lillist do when it detects, at launch, that the currently
   signed-in iCloud account differs from the account the local store
   belongs to?
   **Decision: non-blocking at cold launch (extend the existing
   `PauseReason.accountChanged` badge/dialog path), automatic silent
   containment mid-session (sever mirroring before any prompt), two
   resolution choices both routed through existing hardened primitives**
   — by unanimous ranked-choice majority (3/3 first-place votes) after one
   deliberation round from an initial 1-1-1 three-way split. Round 1: the
   mobile-UX seat favored a new blocking full-screen gate (matching the
   `OnboardingPresentationModifier` precedent, on the theory this is a
   comprehension-critical state); the software-architect seat favored the
   non-blocking extension with identity adopted *before* invoking the
   resolution primitive (required by `DataStoreResetService.performReset`'s
   own unconditional `accountStateProvider`-changed preflight, which would
   otherwise self-block the user's own confirmed resolution forever); the
   security-researcher seat favored the same non-blocking extension but
   with identity adopted only *after* the resolution primitive succeeded
   (tracing a real leak: an early-adopted identity plus a mid-reset
   failure's `reattachStore()` call could re-arm mirroring against the new
   identity while the store still held the old account's data). In
   deliberation, the security-researcher seat conceded the self-block
   critique (verified against real code) but resolved it without moving
   adoption earlier — by adding a narrowly-scoped, re-validating
   resolution entry point that bypasses only the ambient throw for the one
   confirmed call, leaving the ambient method itself (and therefore
   automatic/peer-triggered callers) fully protected — and independently
   traced a second, adoption-timing-independent leak in `performReset`'s
   failure-path `reattachStore()` calls that neither other proposal had
   found. All three seats converged on this revised proposal, unanimously,
   in the runoff; the mobile-UX seat's own revision (still favoring
   blocking) conceded that the architectural fix (mirroring can never
   silently re-arm) outweighed the UX case for forcing acknowledgment, but
   the ledger's binding implication is that the non-blocking dialog must
   stay genuinely *persistent* (survives dismissal, re-triggerable via the
   badge) rather than silently disappearing across launches. Full audit
   trail: `.council/s3-account-mismatch-response-policy/DECISION.md`.
   Implemented in `AccountIdentityStore`
   (`Packages/LillistCore/Sources/LillistCore/Sync/AccountIdentityStore.swift`),
   `DataStoreResetService.resolveAccountMismatchByRedownloading()`, and
   both `AppEnvironment.swift`s' launch/bootstrap wiring — see the *Wave 3a
   closing report* above for the full implementation shape and the two
   `PersistenceHost` leaks closed as binding parts of this decision.

5. **`S10` reset-event expiry window** (Wave 3, plan `3b`, 2026-07-28) —
   what expiry window (in days) should gate whether a still-undecided
   `ResetControlEvent` gets acked-and-discarded automatically vs. surfaced
   as a pending decision, given the binding product decision that apply is
   never automatic regardless of age (so the window is a pure hygiene
   bound, not a safety mechanism)?
   **Decision: 180 days** — unanimous 3/3 in the round-1 single-choice
   vote, no deliberation round needed (all three seats — `ux-designer-mobile`,
   `software-architect`, `skeptic` — independently proposed 30/90/180 days
   respectively in blind round-1 research, then converged unanimously on
   the skeptic's 180-day proposal once voting). Rationale: since apply is
   always user-confirmed, the two failure directions are asymmetric — a
   too-short window silently defeats the actual convergence mechanism
   issue #71 built (traced directly from `DataStoreResetService`/
   `ResetPropagator`'s own source comments: a bare CloudKit zone delete
   does not self-correct, `NSPersistentCloudKitContainer` simply re-creates
   the zone and re-uploads a peer's own data, resurrecting what a reset was
   meant to erase), while a too-long window costs almost nothing (cheap KVS
   entries against the account-wide budget, rare/deliberate resets, still
   requires an explicit "Apply Reset" tap regardless of age). The
   architect's own 90-day proposal was shown in deliberation-equivalent
   voting reasoning to sit at the edge of the review's own stated "weeks to
   a few months" secondary-device dormancy window rather than comfortably
   past it; 180 days clears that window with real margin while remaining a
   genuine bound (not "persist indefinitely"). A dynamic/per-device policy
   was considered and rejected as unwarranted complexity (YAGNI) for this
   account's 2-4-device personal topology. Dissent: none — unanimous. Full
   audit trail: `.council/reset-event-expiry-window/DECISION.md`.
   Implemented as `ResetSignalMonitor.expiryWindowDays`
   (`Packages/LillistCore/Sources/LillistCore/Sync/ResetSignalMonitor.swift`),
   tested by `ResetSignalMonitorTests.swift`'s `exactBoundaryIsExpired`/
   `justUnderBoundaryIsStillActionable` (inclusive-boundary proof) — see
   the *Wave 3b closing report* above for the full implementation shape.

---

## Mikey's manual-verification checklist

Living, checkable copy (the review doc's copy is a point-in-time reference —
this one is authoritative). None of these gate the corresponding fix; all
are tracked here so nothing is silently dropped.

- [ ] CloudKit Console: audit the Production zone for orphaned/purged
      records (`C4`/`X4`) — once, at leisure; re-check after Wave 1's `1b`
      `purge-cloudkit-retirement` merges and deploys.
- [ ] macOS pre/post store-location migration with data intact (`1c`):
      (a) simple case — a Mac with only the legacy Application-Support
      store migrates cleanly into the App Group on first launch after this
      fix, data intact, legacy quarantined not deleted; (b) conflict case —
      a Mac where the widget already populated the App-Group store (i.e.
      one that hit the `X1` bug pre-fix) with the legacy store also
      present: confirm the `iCloudSync` branch lands on the legacy store's
      content with the App-Group original recoverable from quarantine, and
      the `localOnly` branch makes no mutation at all (still boots on
      legacy). See the council decision:
      `.council/macos-migration-both-stores-populated/DECISION.md` and
      `docs/superpowers/plans/2026-07-28-plan-1c-store-location-unification.md`.
- [ ] End-to-end sync-mode switches on live iCloud (Wave 2), including `2b`'s
      restored `restoreFromBackup` crash-recovery flow specifically: force a
      migration crash (kill the app mid-`.reconfiguringStore`), relaunch,
      trigger recovery, confirm the store reopens correctly at both a
      same-mode and a different-mode `previousMode` (the `S2` same-mode
      no-op this plan fixed can only be proven end-to-end on a real
      `NSPersistentCloudKitContainer`, not the fakes the unit suite uses).
- [ ] `2b`/`S9b`: force-kill the app mid-`resetAndReseedFromThisDevice`
      (after the wipe, before the reimport completes) and confirm
      `recoverInterruptedReseed()` resumes cleanly on next launch with no
      data loss — the unit suite proves the mechanism via
      `RealWipingResetHost`, not a real crash mid-flight.
- [ ] Account switch with a second Apple ID (`3a`) — needs a Mac and/or
      iPhone signed into a SECOND, disposable Apple ID with its own iCloud
      account (never test against a real primary account you care about).
      Exact steps:
      1. **Cold-launch mismatch.** With Lillist already installed and
         synced under account A, sign out of iCloud entirely (Settings →
         [name] → Sign Out, or System Settings → Apple ID → Sign Out) and
         sign into account B. Relaunch Lillist. Confirm: (a) the sync
         status badge shows the paused/cloud-with-slash state, tapping it
         opens the dialog titled "iCloud account changed"; (b) CloudKit
         Console for account B's private database shows NO new records
         from this device (mirroring never armed); (c) account A's local
         tasks are still visible in the app (the local store is untouched,
         just not currently mirroring).
      2. **"Use This Account."** From the dialog, tap "Use This Account."
         Confirm: (a) it completes without error (a spinner shows briefly);
         (b) the local store is now empty of account A's tasks; (c) after
         relaunching Lillist once (per the plan doc's "relaunch to
         complete" design — mirroring re-arms on the NEXT cold launch's
         identity check, not in-session), the app downloads and shows
         account B's actual tasks; (d) CloudKit Console for account A's
         private database shows NO trace of this device's local edits
         having uploaded at any point in this flow.
      3. **"Stay Local For Now"** (repeat step 1 fresh, or use a second
         test device). From the dialog, tap "Stay Local For Now." Confirm:
         (a) it completes without error; (b) Settings → iCloud Sync shows
         Local Only; (c) account A's local tasks are still all present and
         editable; (d) relaunching Lillist does NOT re-show the mismatch
         dialog (identity was adopted, so the next launch sees a match);
         (e) manually re-enabling "iCloud Sync" in Settings afterward
         correctly downloads account B's data fresh (no account A data
         leaks into account B's zone).
      4. **Mid-session switch.** With Lillist foregrounded and actively
         synced under account A, switch to account B via System
         Settings/Settings WITHOUT force-quitting Lillist first. Confirm:
         (a) within roughly one `CKAccountChanged` notification delivery
         (should be near-immediate), the app auto-disables sync (Settings
         shows Local Only) with no user action required; (b) the pause
         dialog/badge subsequently offers the same two resolution choices;
         (c) CloudKit Console for account B shows no records uploaded
         during the brief window between the account switch and the
         auto-disable completing (the one residual risk the council
         decision explicitly flagged as a documented, Apple-API-bounded
         limitation — verify it's negligible in practice, not literally
         zero).
      5. **False-positive check.** Sign out of iCloud entirely (no second
         account) and confirm this does NOT trigger the mismatch dialog —
         only the existing "iCloud isn't signed in" pause reason, per
         `AccountIdentityStore`'s `.signedOut` case (distinct from
         `.mismatch`).
- [ ] Two-device reset propagation, including the always-prompt UX (`3b`) —
      needs two devices signed into the SAME test iCloud account (reuse the
      second Apple ID from the `3a` checklist item above; never test
      against a real primary account).
      1. **Basic propagation + always-prompt.** On device A, Settings →
         Debug → Reset → "Erase Data from All Devices and Start Over…" (or
         "…Restore All from This Device's Backup…"). Confirm on device A:
         the result text names whether other devices were actually
         notified (a live `BroadcastOutcome`, not a hardcoded "will erase
         and reload" claim). On device B (already open or opened shortly
         after, both online): confirm a "Reset requested" banner appears in
         Settings → iCloud Sync **without** device B's data changing on its
         own — tap it, confirm `PendingResetDecisionDialog` shows the
         correct sender name and reset kind, tap "Apply Reset," confirm
         device B converges only after that explicit tap.
      2. **"Not Now" persistence.** Repeat step 1; on device B tap "Not
         Now" instead. Confirm: device B's data is untouched, and the
         "Reset requested" banner is STILL present (re-tappable) after
         dismissing — reopening Settings → iCloud Sync (or relaunching)
         still offers the same pending decision.
      3. **`rosterEmpty` outcome.** From a device that has never
         registered a peer (e.g. right after a fresh Erase Everywhere
         wiped the KVS roster, or a genuinely solo test account), trigger
         "Erase Everywhere." Confirm the result text says nobody else was
         notified (not a false "your other devices will erase and reload"
         claim).
      4. **Local-only auto-discard.** Put device B in Local Only mode
         (Settings → iCloud Sync toggle off) BEFORE device A broadcasts a
         reset. Confirm on device B: no "Reset requested" banner ever
         appears; instead a dismissible discard notice explains a request
         arrived while offline from iCloud Sync and couldn't be applied.
      5. **Stale-event expiry (180 days) — inspection only, not a live
         180-day wait.** Confirm via Console/breadcrumb inspection (not a
         literal multi-month wait) that an event older than the council-
         decided 180-day window is acked-and-discarded with a diagnostic
         breadcrumb rather than surfaced, e.g. by hand-editing a test
         device's local `ControlInbox` entry's `requestedAt` (or reasoning
         from the shipped `ResetSignalMonitorTests` expiry-boundary
         coverage, which already exercises this deterministically) if a
         live 180-day-old event isn't practical to produce.
      6. **Reseed quiesce-gated broadcast (`S9c`).** On device A, trigger
         "Restore All from This Device's Backup" on a connection slow
         enough to observe the re-export in progress (Settings → iCloud
         Sync status). Confirm device B's pending-reset banner does NOT
         appear until device A's re-export has actually settled — device B
         should never be invited to redownload a zone still mid-upload.
      7. **`S19` retry-for-real.** Force a migration crash mid-`.reconfiguringStore`
         (kill the app, matching the existing Wave 2 checklist item above)
         so the recovery sheet appears, then tap "Try Again." Confirm the
         operation actually re-runs (visible progress UI, not an instant
         silent dismiss back to Settings) and either completes or leaves a
         fresh, accurate failure state — not the old silently-cleared-
         journal-with-nothing-retried behavior.
- [ ] Real-widget verification: completing a task cancels its reminder; a
      local edit refreshes the widget (Waves 4-5).
- [x] `1d` does **not** add any new CloudKit record types/fields — verified
      (its changes are to the export/backup file format and in-process
      logic only; the Core Data model is unchanged). No schema deploy
      needed for this plan.
- [x] `2b` does **not** add any new CloudKit record types/fields either —
      verified (every change is to the migration/reset/backup
      orchestration logic and the on-disk JSON backup package; the Core
      Data model is unchanged). No schema deploy needed for this plan.
- [x] `3a` does **not** add any new CloudKit record types/fields either —
      verified (the account-identity token is persisted to a local JSON
      file in the App Group container, never synced via CloudKit itself;
      every other change is to launch-sequencing/orchestration logic and
      the Core Data model is unchanged). No schema deploy needed for this
      plan.
- [x] `3b` does **not** add any new CloudKit record types/fields either —
      verified (every change is to the `ControlInbox`/`DeviceRoster` KVS
      channel, local UserDefaults/JSON dead-letter and watermark storage,
      and in-process migration/reset orchestration logic; the Core Data
      model is unchanged, and the KVS channel was already a separate
      pre-existing iCloud subsystem from issue #71, not something this plan
      introduced). No schema deploy needed for this plan.
- [ ] iCloud-dependent app-hosted/UI tests — standing CI-scope rule, verified
      manually per wave (same posture as the Foundation Hardening program).

---

## Known constraints carried from the review

- **Product decision (`C2`):** restoring a child whose parent is still
  trashed promotes it to root. Binding for `1a`.
- **Product decision (`S10`):** remote reset events are never auto-applied —
  always prompt. An expiry window as a hygiene bound is still worth keeping;
  its exact duration was a `3b` council-vote decision — **resolved: 180
  days**, unanimous 3/3 in round 1. Delivered in `3b`; see the *Wave 3b
  closing report* and `.council/reset-event-expiry-window/DECISION.md`.
- **`C4`/`X4` verification is non-blocking** — the fix ships regardless of
  device verification timing; see *Execution model* above.
- **`X20`'s flip-flop stress test** is additional hardening on top of `5a`'s
  fix, called out again in `6a`'s scope — one story (owned by `5a`), not two.
- **Verification protocol (added after `LIL-79`, binding on every later
  wave):** `swift test`'s swift-testing summary line ("Test run with N
  tests in M suites passed") does **not** include `XCTestCase`-based test
  results — under `--parallel` specifically, passing `XCTestCase` tests
  print only progress lines (`[N/M] Testing Bundle.Class/method`), no
  per-test pass/fail confirmation and no XCTest bundle summary, so a
  visual scan of "did the last lines say passed" is not sufficient. Every
  suite-verification claim in this ledger (and every wave's closing
  report) must capture the real process exit code — never pipe through
  `tail`/`grep -m1`/`head`, which discard it — and additionally grep the
  full captured output for `Test Suite .* failed` and `Note: Some test
  targets reported failures` (the two markers XCTest emits on a real
  failure, confirmed via a deliberate toggle-the-failure probe during the
  `LIL-79` fix). Minimum command shape:
  `swift test --package-path Packages/LillistCore --parallel --num-workers 2 > /tmp/suite.log 2>&1; echo EXIT:$?`
  then `grep -E "Test Suite .* failed|Note: Some test targets reported failures" /tmp/suite.log`.
  Run twice when a change touches shared test fixture state (in-process
  singletons, `UserDefaults(suiteName:)`, shared temp directories) to
  derisk parallel-worker races — see the `LIL-79` postmortem in the
  `1c` correction note above for the shape of defect this catches.
