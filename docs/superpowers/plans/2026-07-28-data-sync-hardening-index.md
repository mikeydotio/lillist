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

**As of 2026-07-28 — Wave 0 and Wave 1 plans `1a` (`trash-tree-integrity`) and
`1b` (`purge-cloudkit-retirement`) COMPLETE.**

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
- ⬜ Wave 1 plans `1c`-`1d`, Waves 2 through 6: not started.

**Next action for whoever picks this up:** start Wave 1, plan `1c`
(`store-location-unification`) — findings `X1 X2 X15`. It does not sit on
the `TaskStore.swift` serial chain (that chain's next link is `4b`, after
`1b`'s purge-path changes); `1c`'s hotspot is `AppEnvironment.swift` (both
platforms) and the store-location resolvers (`StoreConfiguration`,
`StoreLocator`, `appGroupOnDisk`/`defaultOnDisk`). Read the *Resume
protocol* section first, then *Wave 1b closing report* below for what
`1b` changed in `TaskStore.swift`/`AutoPurgeJob.swift`/
`NotificationReconciling.swift` that later plans in the `TaskStore.swift`
chain (`4b`, `5a`) must build on.

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
| 1 | **1c** `store-location-unification` | `X1 X2 X15` (+ iOS silent `defaultOnDisk` fallback detail, folded into the `X1`/`X2` story bodies — no separate ID) | ⬜ pending |
| 1 | **1d** `export-schema-completeness` | `X3 S9a X13 X18` | ⬜ pending |
| 2 | **2a** `migration-transitions` | `S1 S5 S6 S8 S11 S12 S14 S15 S16 S17` | ⬜ pending |
| 2 | **2b** `backup-restore-correctness` | `S2 S4 S7 S9b S23` | ⬜ pending |
| 3 | **3a** `account-identity-and-status` | `S3 S13 S21 S24` | ⬜ pending |
| 3 | **3b** `reset-propagation-safety` | `S10 S18 S19 S20 S22 X11 S9c` | ⬜ pending |
| 4 | **4a** `history-consumer-discipline` | `H6 M3` | ⬜ pending |
| 4 | **4b** `notification-truthfulness` | `H2 X8 X9 X10` | ⬜ pending |
| 4 | **4c** `recurrence-correctness` | `H1 X7 X16 X17` | ⬜ pending |
| 5 | **5a** `mutation-scope-discipline` | `H5 M4 M6 M7 L3 L4 L5 X19 X20` | ⬜ pending |
| 5 | **5b** `widget-snapshot-correctness` | `X5 X6` | ⬜ pending |
| 5 | **5c** `watermark-registry-pruning` | `X12 L7` | ⬜ pending |
| 6 | **6a** `completeness-and-lows` + closeout | `L1 L2 L6` + export round-trip equality suite + `X20` flip-flop stress (builds atop 5a's fix, not a new finding) + any residuals from Waves 1-5 | ⬜ pending |

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
| Model-derived export-completeness test (walks `NSManagedObjectModel`) | Adopt | 1d |

Other new public types requiring a proposal+UML in-wave: `DestructiveOpGate`
(2a), `AccountIdentityStore` (3a).

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
2. **`MigrationCoordinator.swift`** — `2a` (migration transitions: honors
   `.timedOut`, counts `.setup`, de-interleaves waiters, mode-store-advances-
   only-on-success, `DestructiveOpGate`) → `2b` (backup/restore: close-before-
   file-ops, quarantine-from-closed-store, staged restore package) → `3a`
   (account-identity guard wired into the pre-erase check). Three plans.
3. **`PersistenceHost.swift`** — `2a` → `2b`. Two plans, `2a` first.
4. **`RemoteChangeReconciler.swift`** — `4a` (`DrainGate`/watermark-after-
   success pattern extracted and adopted) → `4b` (spec insert/delete +
   soft-delete reconcile added on top of `4a`'s corrected watermark
   discipline). `4a` **must** land first — never widen a reconcile mechanism
   that still silently loses work.
5. **`AppEnvironment.swift`** (both iOS and macOS copies — distinct regions,
   serialize per-platform) — `1c` (canonical `StoreLocation` wiring; macOS
   App-Group migration) → `3a` (account identity store wiring) → `4b`
   (notification scheduler reaching extension/widget/CLI paths via 1c's
   standardized construction).
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
   `BackupSchema.swift`** — `1d` (adds Series/NotificationSpec/archivedAt
   DTOs + model-derived completeness test) → `2b` (backup/restore consumes
   the completed schema for its restore-in-progress guard and min-over-
   records check).

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
| **6a** completeness-and-lows | `L1`→`LIL-70`, `L2`→`LIL-71`, `L6`→`LIL-75` |

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

---

## Mikey's manual-verification checklist

Living, checkable copy (the review doc's copy is a point-in-time reference —
this one is authoritative). None of these gate the corresponding fix; all
are tracked here so nothing is silently dropped.

- [ ] CloudKit Console: audit the Production zone for orphaned/purged
      records (`C4`/`X4`) — once, at leisure; re-check after Wave 1's `1b`
      `purge-cloudkit-retirement` merges and deploys.
- [ ] macOS pre/post store-location migration with data intact (`1c`).
- [ ] End-to-end sync-mode switches on live iCloud (Wave 2).
- [ ] Account switch with a second Apple ID (`3a`).
- [ ] Two-device reset propagation, including the stale-event UX (`3b`).
- [ ] Real-widget verification: completing a task cancels its reminder; a
      local edit refreshes the widget (Waves 4-5).
- [ ] If `1d` adds any new CloudKit record types/fields: a standing
      Development → Production schema deploy in the Console is required
      before a Production build can use them.
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
