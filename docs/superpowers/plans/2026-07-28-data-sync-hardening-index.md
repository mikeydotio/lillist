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

**As of 2026-07-28 — Wave 0, all of Wave 1 (`1a` `trash-tree-integrity`,
`1b` `purge-cloudkit-retirement`, `1c` `store-location-unification`, `1d`
`export-schema-completeness`), and all of Wave 2 (`2a` `migration-transitions`,
`2b` `backup-restore-correctness`) COMPLETE. Wave 3 next.**

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

**Next action for whoever picks this up:** start Wave 3, plan `3a`
(`account-identity-and-status`) — findings `S3 S13 S21 S24`. Its
hotspots include `MigrationCoordinator.swift` and both
`AppEnvironment.swift`s (see the *Shared-file serial chains* section,
chains 2 and 5 — `2a`/`2b` ✅ done are the first two links on chain 2;
`1c` ✅ done is the first link on chain 5). Read the *Resume protocol*
section first, then *Wave 2b closing report* below for what `2b` left
in place (the unified tearDown+attachStore quarantine mechanism now
covers all four migration ops; `DestructiveOpGate` also gates
`LocalBackupCoordinator`'s prune step; a new `ReseedJournal` +
`BackupPackageReconciling` protocol exist if `3a`'s account-switch work
ever needs a similar durable-recovery or resync pattern).

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
| 3 | **3a** `account-identity-and-status` | `S3 S13 S21 S24` | ⬜ pending |
| 3 | **3b** `reset-propagation-safety` | `S10 S18 S19 S20 S22 X11 S9c` | ⬜ pending |
| 4 | **4a** `history-consumer-discipline` | `H6 M3` | ⬜ pending |
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

Other new public types requiring a proposal+UML in-wave: `AccountIdentityStore`
(3a).

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
   ops) → `3a` (account-identity guard wired into the pre-erase check —
   see the *Wave 2b closing report* for exactly what shape to extend).
   Three plans.
3. **`PersistenceHost.swift`** — `2a` ✅ done (`flushAndSwap` throws instead
   of silently succeeding with zero attached stores) → `2b` ✅ done (new
   `attachStore(at:)` on `PersistenceResetting` — attaches fresh at an
   explicit mode, always updating `currentMode`, never a no-op; all four
   conformers implement it). Two plans, both done.
4. **`RemoteChangeReconciler.swift`** — `4a` (`DrainGate`/watermark-after-
   success pattern extracted and adopted) → `4b` (spec insert/delete +
   soft-delete reconcile added on top of `4a`'s corrected watermark
   discipline). `4a` **must** land first — never widen a reconcile mechanism
   that still silently loses work.
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
   the *Wave 2b closing report* for the exact diff shape) → `3a` (account
   identity store wiring — re-Read `bootstrap()`'s new first-line ordering
   before prepending anything) → `4b` (notification scheduler reaching
   extension/widget/CLI paths via 1c's standardized construction).
6. **`HistoryPruner.swift` + the three history-token `UserDefaults` keys** —
   `3b` (reset clears watermarks + widget cache; `WatermarkRegistry` doubles
   as the reset-clear enumeration) ↔ `5c` (formalizes the registry itself,
   min-over-consumers pruning). These two co-depend — read both plans before
   starting either; land `5c`'s registry first structurally, `3b` consumes it
   for the reset-clear path, even though `3b` is the earlier wave (a
   **forward reference**: `3b`'s plan doc should stub/interface against the
   registry shape `5c` will formalize, or `5c` should be pulled earlier if
   the forward-reference proves awkward in practice — flag this at Wave 3
   kickoff if so).
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
- [ ] Account switch with a second Apple ID (`3a`).
- [ ] Two-device reset propagation, including the stale-event UX (`3b`).
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
- [ ] iCloud-dependent app-hosted/UI tests — standing CI-scope rule, verified
      manually per wave (same posture as the Foundation Hardening program).

---

## Known constraints carried from the review

- **Product decision (`C2`):** restoring a child whose parent is still
  trashed promotes it to root. Binding for `1a`.
- **Product decision (`S10`):** remote reset events are never auto-applied —
  always prompt. An expiry window as a hygiene bound is still worth keeping;
  its exact duration is a `3b` council-vote decision.
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
