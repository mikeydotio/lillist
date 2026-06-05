# Foundation Hardening — Master Execution Index

> **For agentic workers:** This is the **orchestration index** for the 22 plans
> that close the 2026-05-28 foundation review
> (`docs/reviews/2026-05-28-foundation-review.md`). Each linked plan is a
> self-contained writing-plans document with checkbox TDD tasks. Execute plans
> in the **wave order** below; within the per-file **serial chains**, the named
> plan lands first and later plans **re-Read the file and re-anchor by code
> structure, not line number**. Use `superpowers:subagent-driven-development`
> (fresh subagent per task, review between tasks) or `superpowers:executing-plans`.

**Goal:** Take Lillist from `solid-with-gaps` to a rock-solid foundation by
landing 22 focused plans (171 tasks / ~847 TDD steps) in a dependency-correct
order that never lets one plan silently revert another.

**Architecture:** Wave-based execution. Waves run in priority order (P0 → P3 +
ship-blockers). Within a wave, plans on disjoint files run in parallel; plans
sharing a file run as a serial chain with a designated owner. Five files are
high-traffic hotspots (`MigrationCoordinator.swift`, `TaskStore.swift`,
`IntentSupport.swift`, `ShareRootView.swift`, the iOS/macOS `project.yml` +
`pbxproj`) and have explicit chains below.

**Tech Stack:** Swift 6.2, SwiftUI, Core Data + `NSPersistentCloudKitContainer`,
CloudKit, XCTest + Swift Testing, xcodegen, GitHub Actions (new).

---

## 📍 Current status & how to pick this up

> **New here? Read this section first, then start the next pending plan.** This
> file is the **living progress tracker** for the program — keep it current as
> plans merge.

**As of 2026-06-04 (Wave 4 complete):**

- ✅ **Wave 1 · `store-swap-safety`** — **merged to `main`** (commits
  `bfd8635`..`6f008f7`; 663 LillistCore tests green). Closed persist-3,
  sync-1/3/4/7, conc-4, test-1/2, Roadmap #1. ⚠️ Its `liveSwapAllowed`-gated
  *live-container* swap tests execute only on a **code-signed** simulator host
  (CI or a developer Mac) — verify them there:
  `xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -only-testing:Lillist-iOSAppHostedTests`.
- ✅ **Wave 1 · `recurrence-input-hardening`** — **merged to `main`** (commits
  `758a14b`..`b6b80dd`; 687-test LillistCore suite green, warning-free). Closed
  rec-1, rec-2, stores-7. A post-merge **adversarial audit** found and closed an
  additional crash the plan's "0 or negative" scope missed: a huge *positive*
  untrusted `interval` overflowed the monthly `12 * n + 1` bound (trap) / forced
  an O(interval) scan (hang). Now bounded by `CalendarRule.maxInterval` (1000) +
  a two-sided `clampedInterval` at the boundary **and** every expander site. Two
  non-crash follow-ups were logged as residuals (#8, #9 below), **not**
  silently fixed: non-positive `count` semantics (existing tested behavior is
  "count=0 ⇒ empty series" — changing it is a product call) and
  `byMonthDay`/`bySetPos`/AfterCompletion-interval out-of-range.
- ✅ **Wave 2 · `breadcrumb-truthfulness`** — **merged to `main`** (commits
  `97ed3a8`..`7c2ebcd` + `collectPhases` determinism fix; 705 LillistCore tests
  green ×3, warning-free). Closed conc-1, stores-2, persist-8. All nine
  `defer { Task { recordCrumb(success: true) } }` store sites converted to inline
  do/catch with a true success flag; the `MigrationCoordinator.breadcrumb` helper
  is now `async`/awaited inline. A **post-merge follow-up** strengthened a Wave-1
  test helper: `MigrationRunnerExecutingTests.collectPhases` relied on a fixed
  50ms `Task.sleep` to drain the terminal phase, which the new `await` checkpoints
  exposed as a flaky race — replaced with `await consumer.value` (deterministic).
- ✅ **Wave 2 · `fractional-ordering-compaction`** — **merged to `main`** (commits
  `3ecd71d`..`20f4126`; 712 LillistCore tests green, warning-free). Closed
  stores-1, stores-3. Added `FractionalPosition.anchorsAreOutOfOrder` +
  `needsCompaction` as the shared source of truth; wired the previously-dead
  `PositionCompactor.recompact` into both `TaskStore.reorder` and
  `SmartFilterStore.reorder` (recompact-in-same-perform on gap underflow), plus a
  shared anchor-order guard. Note: with the anchor guard landing first (Tasks 2/3),
  the stores-1 underflow now surfaces as a thrown `anchors out of order` one step
  earlier rather than as duplicate positions — same root collision, louder failure;
  the 60-insert compaction tests still gate it.
- ✅ **Wave 2 · `predicate-parity`** — **merged to `main`** (commits
  `0be04fa`..`2f7dc3e`; 716 LillistCore tests green ×3, warning-free). Closed
  rules-1…7. Unified ancestor-depth limit, diacritic+case-insensitive equals,
  one source of truth for recurrence/hasNudges, symmetric `isAncestorOf`, and the
  `weeksFromNow` integer-overflow clamp (residual #7 — **now resolved**). The
  parity suite is now matrix-driven under **two calendars (UTC + an
  America/New_York DST run seeded on the 2026-03-08 spring-forward)**; date
  fixtures re-seed via calendar-relative offsets so expecteds are correct by
  construction. **Result: zero divergence between the NSPredicate and Swift
  evaluators across all 102 cases — including window math straddling the 23-hour
  DST day.** Two plan fixture defects were corrected (empty-needle `CONTAINS`
  expectation; absolute-seed-vs-DST-now premise), not papered over. *(Note: a
  one-off transient SIGSEGV in the concurrent in-memory Core Data tests appeared
  in one baseline run and never reproduced — flagged as harness flakiness, not a
  regression.)*
- ◧ **Wave 2 · `link-preview-ssrf-guards`** — **Tasks 1–5 merged to `main`**
  (commits `356ed97`..`4bb6154`; 738 LillistCore tests green, warning-free). Closed
  linkpreview-1, linkpreview-2, and the policy/fetcher/CLI halves of linkpreview-3.
  Added the pure-value `URLPreviewPolicy` (http/https scheme allow-list + literal
  localhost/`*.local`/loopback/link-local/RFC1918/IPv6-ULA/IPv6-LL block-list),
  enforced it in `URLSessionLinkPreviewFetcher` (pre-check + `bytes(for:delegate:)`
  streaming 5 MB early-abort + per-task `RedirectGuard` re-applying the policy and
  capping hops), and gated `CLIBridge.LinkHandler` ingest. **Task 6 (iOS Share
  Extension `ShareRootView` gate) is DEFERRED to Wave 6** per chain #3 (that file
  is restructured first by `app-layer-test-rehab`/`extension-persistence-unification`)
  — tracked as residual #10 below. (Test used `attachments(forTask:).isEmpty` —
  `AttachmentStore` exposes no `count(forTask:)`.)
- ✅ **Wave 2 COMPLETE** (modulo the link-preview Share-Extension gate explicitly
  carried to Wave 6).
- ✅ **Wave 3 · `cloudkit-convergence`** — **merged to `main`** (commits
  `795290c`..`cc9e581`; 760 LillistCore tests green, iOS app builds clean,
  warning-free). Closed persist-2, conc-3, notif-2, persist-5. Established
  `PersistenceController.localTransactionAuthor` (the hard dep for Wave 4
  `concurrency-stress-tests`), well-known `AppPreferences.singletonID` +
  `normalizeSingletons`, one-default-spec-per-(task,kind) guard,
  `PersistentHistoryTokenStore` + `RemoteChangeReconciler`, `CloudKitErrorClassifier`,
  and wired the reconciler + normalization into the iOS launch path. Three faithful
  compile-fixes to the plan's verbatim source were needed (a non-Sendable
  `NSPersistentHistoryToken` captured across a `@Sendable` `perform` boundary ×2;
  an unused outer `try`; `fetchHistory(after: nil)` overload ambiguity) — none
  changed behavior or weakened a test. **⚠️ A pre-existing, rare, test-only SIGSEGV
  in heavy parallel in-memory store creation was investigated during verification
  — see residual #11; not a Wave-3 regression (760 green ×10).**
- ✅ **Wave 3 · `resolve-inert-features`** — **merged to `main`** (commits
  `a2e4ac1`..`aac4435`; 767 LillistCore tests green, iOS + macOS apps build clean,
  warning-free). Closed persist-6, ios-1, ios-4, macos-2, logs-2, crumbs-3, cli-1.
  Wired `AutoPurgeJob` into both `bootstrap()` paths + an iOS `BGProcessingTask`
  (shared `BackgroundPurgeSchedule` constant + pin test), drove
  `PauseReasonClassifier` into the `pauseReason` mirror on both platforms, deleted
  the dead iOS `CommandMenu("Task")` block + four unobserved macOS menu commands
  (behind a co-compiled observer guard test), stripped the overpromising
  crash-report breadcrumb/log preview copy, and centralized the CLI `time_zone`
  via `Config.resolvedCalendar()`. Notes: this plan does **NOT** wire
  `HistoryPruner.sweep` (the earlier index claim was wrong — that's Wave 4's
  `background-context-seam`); one faithful compile-fix to the plan's Task-9 BGTask
  handler (redundant `try?` on a non-throwing `Task.value`, same pattern as
  cloudkit-convergence); the plan's stale pbxproj path was corrected to
  `Apps/Lillist-macOS.xcodeproj`.
- ✅ **Wave 3 COMPLETE.**
- ✅ **Wave 4 · `concurrency-stress-tests`** — **merged to `main`** (commits
  `f093884`..`805291f`; 777→ tests green, warning-free). Closed conc-2, conc-3,
  stores-4, notif-3, notif-9, test-3. Test-only plan; two beyond-plan findings
  handled honestly: (a) `FakeUserNotificationCenter.add` was not upsert-faithful
  to `UNUserNotificationCenter` (concurrent reconciles would trap the scheduler's
  `Dictionary(uniqueKeysWithValues:)`) — fixed; (b) the plan's "revert-check bites"
  premise for the AsyncStream suite is **false** (verified empirically; actor
  scheduling masks Race A in the `recordEvent` seam — the existing
  `preSubscriptionEventBuffering` has the same limitation). The N-subscriber suite
  was kept (guards fan-out/no-starvation/churn-liveness) with honest docs;
  `StoreReconfigureConcurrencyTests` wired into `Lillist-iOSAppHostedTests` so its
  gated cases execute on a signed host. See `docs/engineering-notes.md`.
- ✅ **Wave 4 · `migration-adjacent-correctness`** — **merged to `main`** (commits
  `af7c29f`..`3a676d8`; 791 tests green; iOS + macOS apps build clean). Closed
  notif-1, sync-2, sync-5, sync-6, sync-8. `NotificationScheduler.restoreSteadyState`
  + morning-summary-preserving `cancelAllPending`; coordinator reads
  `PreferencesStore` and restores in `.finalizing`; `MigrationJournal.isStale`
  (600s threshold, recovery-sheet-only — `MigrationGate` untouched); truthful
  `PauseReason.accountChanged` docstring + optional pre-erase `accountStateProvider`
  guard; `runMigration` reentrancy guard. The new live-swap-gated
  `MigrationCoordinatorRestoreTests` (+ `FakeUserNotificationCenter.swift`) are
  wired into `Lillist-iOSAppHostedTests`; their executing proof is on a signed host.
- ✅ **Wave 4 · `background-context-seam`** — **merged to `main`** (commits
  `5caef1e`..`45b7d7d`; 805 tests green; iOS + macOS apps build clean). Closed
  threading-1, persist-4, conc-5, notif-7, persist-1. `makeBackgroundContext`
  helper; Exporter reads + Importer writes + `purgeAll`/`AutoPurgeJob` moved off
  the main `viewContext`; `CascadeReaper` reproduces the Cascade rules
  `NSBatchDeleteRequest` skips; `context.rollback()` added to all 8 mutating
  catch paths (one line each, breadcrumb-truthfulness shape untouched);
  `HistoryPruner.sweep` (localOnly-gated, idempotent) created **and wired into
  both `bootstrap()`s**. Two required deviations (both correct): `batchPurge` takes
  a predicate format+args (NSPredicate non-Sendable), and `CascadeReaper.batchDelete`
  groups per-entity leaf-first because `NSBatchDeleteRequest(objectIDs:)` is
  single-entity (the plan's mixed-entity batch crashed at runtime). Residual #3
  (un-cancelled OS pending notifications on purge) documented as acknowledged.
- ✅ **Wave 4 post-merge review + hardening** (commits `18c00ed`..`479d47a`; final
  state 808 tests green, both apps build). A 4-dimension adversarial review found no
  prior-wave regression and clean cross-plan composition, plus **4 important findings
  that were fixed and re-verified closed**: (1) the conc-5 rollback fix had missed
  `transition`/`reorder`/`assignTag`/`unassignTag` (now roll back; "every mutating
  method" claim now true — purgeAll is the sole exclusion); (2) the `runMigration`
  reentrancy guard had a TOCTOU window (now a synchronous `@MainActor isMigrating` flag
  set before the first await); (3) the HistoryPruner tests were near-tautological (now
  `fetchHistory`-based, proving real pruning); (4) background contexts now stamp
  `transactionAuthor` (author-attribution hardening). CascadeReaper test tightened
  `>=6`→`==6`. Full analysis: `docs/superpowers/handoffs/wave-4.md`.
- ✅ **Wave 4 COMPLETE. Next: Wave 5** — `crash-reporter-privacy` (fully isolated),
  `app-layer-test-rehab` (introduces `GatedPersistenceResolver`; **must precede**
  `extension-persistence-unification`; starts the iOS `project.yml` chain). See
  `docs/superpowers/handoffs/wave-4.md`.
- ⬜ **Waves 5–7** — pending. Follow the wave order + serial chains below.

### Progress checklist

- **Wave 1 (P0):** ✅ store-swap-safety · ✅ recurrence-input-hardening
- **Wave 2 (P1):** ✅ breadcrumb-truthfulness · ✅ fractional-ordering-compaction · ✅ predicate-parity · ◧ link-preview-ssrf-guards (Tasks 1–5 done; **Task 6 Share-Extension gate → Wave 6**)
- **Wave 3 (P1):** ✅ cloudkit-convergence · ✅ resolve-inert-features
- **Wave 4:** ✅ concurrency-stress-tests · ✅ migration-adjacent-correctness · ✅ background-context-seam
- **Wave 5 (P2):** ⬜ **crash-reporter-privacy ← NEXT** · ⬜ app-layer-test-rehab
- **Wave 6:** ⬜ extension-persistence-unification · ⬜ export-import-robustness · ⬜ cli-robustness · ⬜ performance-budgets-and-paging · ⬜ observability-logging
- **Wave 7 (closing):** ⬜ privacy-manifest-export-compliance · ⬜ recovery-hardening · ⬜ lillistui-localization-a11y · ⬜ ci-and-build-posture (LAST)

_When a plan merges, flip its box here and update its in-plan status banner._

### How to execute (zero context)

1. **Read** the review [`docs/reviews/2026-05-28-foundation-review.md`](../../reviews/2026-05-28-foundation-review.md)
   (why this work exists) and `CLAUDE.md` (conventions, build/test, signing).
2. **Read the prior wave's handoff** — `docs/superpowers/handoffs/wave-(N−1).md`
   (see *Wave Handoff Protocol*). Then **pick** the next ⬜ plan in wave order —
   respect the **serial chains** and **hard dependencies** below. Each plan is
   written to be correct against current `main` (reconciled to post-Wave-3
   reality on 2026-06-04); start with its standard pre-flight.
3. **Execute** task-by-task with the `superpowers:subagent-driven-development`
   skill (fresh subagent per task; spec-review then quality-review each).
   `superpowers:executing-plans` is the alternative.
4. **Re-Read every file before editing** — each wave shifts the shared hotspot
   files, so plan line numbers drift; anchor by code **structure**, not line
   number.
5. **Verify** `swift test --package-path Packages/LillistCore` and `…/LillistUI`;
   app targets via the `xcodebuild … CODE_SIGNING_ALLOWED=NO build` recipe in
   `CLAUDE.md`; the host-gated swap tests need a signed simulator run.
6. **Land** small conventional commits; merge each plan to `main` when its suite
   is green (solo project — direct to `main`). **On wave completion, write
   `docs/superpowers/handoffs/wave-N.md`** for the next executor.

### Wave-1 execution learnings (what later plans must know)

`store-swap-safety` changed reality in ways the other plans were authored
before. Each affected plan now carries a **⚠️ Wave-1 reconciliation** note;
highlights:

- **`localStoreRowCount` is wired LIVE in production** (both `AppEnvironment`s +
  `PersistenceController.localTaskRowCount()`, fail-closed) — **no later plan
  should wire it again.**
- **`restoreFromBackup` already honors the journal's recorded folder** and
  **`test-2` is CLOSED** — `recovery-hardening` should DELETE its
  restoreFromBackup-coverage tasks and focus on disk-space pre-flight +
  auto-backup + user-facing restore, against the new **`copyStore`** (copy-not-
  move), not `quarantineStore`.
- **`runMigration` was reordered** (precondition → reconfigure → `copyStore` →
  erase → settle → finalize); `MigrationJournal.quarantineBackupID` →
  `quarantineFolderName`.
- **`PersistenceReconfiguring`, `FakePersistenceReconfigurer`, the executing
  migration tests, and the `Lillist-iOSAppHostedTests` target all exist** —
  reuse them, don't recreate. `ci-and-build-posture` *runs* the app-hosted
  target; it doesn't create it.
- **One deferred follow-up** in `docs/engineering-notes.md`:
  `wal_checkpoint(TRUNCATE)` around `copyStore` — owned by `recovery-hardening`.

### Readiness-audit pass (2026-05-29)

All 22 plans were audited for blind-contributor readiness: every plan got the
status banner above; 11 received Wave-1 reconciliation notes; and specific
plan-internal defects (zero-matching `--filter` commands, wrong test-count
gates, an unsound poison-object test, wrong file pointers, a `Self.appGroupID`
scope bug, CI app-hosted-signing guidance, a BGTask `@MainActor` hop, a stale
verbatim method paste, and a `breadcrumb-truthfulness` prerequisite) were
corrected in the plans.

### Wave 2–3 reconciliation pass (2026-06-04)

The 2026-05-29 audit predated Waves 2 and 3. After those merged, an 18-agent
read-only audit (workflow `wf_8ddc8c63-ae5`) re-checked all 14 remaining plans
against current `main`. The plans were then **rewritten in place to be correct
as if authored today** — the per-plan Wave-1 reconciliation notes were folded
into direct prose, stale line anchors refreshed (structural anchors made primary
on the shared hotspot files), and the following load-bearing fixes applied:

- `concurrency-stress-tests` Task 1 flipped **RED→GREEN** (its
  at-most-one-default dependency landed in Wave 3, commit `893c359`).
- `background-context-seam` Task 1 insertion point corrected (after
  `localTaskRowCount()`), Task 6 rollback re-anchored structurally onto the
  Wave-2 `do/catch` shape, Task 5 `purgeAll` whole-method replacement; **owns
  `HistoryPruner.sweep`**; absorbs residual #3 as a documented limitation.
- `extension-persistence-unification` routes through `GatedPersistenceResolver`
  (Wave 5) and **absorbs residual #10** (link-preview Task 6 Share-Extension gate).
- `export-import-robustness` `applyEntry` Task 3/4 signature conflict resolved.
- `recovery-hardening` retargeted to `copyStore` (not `quarantineStore`) with
  post-reconfigure Task-5 assertions; Tasks 6–7 stay **deleted** (test-2 closed,
  `MigrationRecoveryTests.swift` exists).
- `ci-and-build-posture` **absorbs residual #11** (bound test parallelism / flake
  retry).
- `lillistui-localization-a11y` test-count arithmetic fixed (33, not 38).

Two audit findings were **verified false and rejected** (do not reintroduce):
"`MigrationRecoveryTests.swift` doesn't exist" (it does — keep Tasks 6–7
deleted) and "iOS 26.2 doesn't exist, use 19.2" (`iPhone 17 / iOS 26.2` is the
canonical destination per `CLAUDE.md`).

### Wave 4 reconciliation pass (2026-06-04)

After Wave 4 merged (commits `f093884`..`479d47a` incl. the post-merge hardening),
an 11-agent read-only audit (workflow `wf_ddd80970-326`) re-checked all remaining
Wave-5/6/7 plans against current `main`. Each affected plan got a concise
`⚠️ Wave-4 reconciliation (2026-06-04)` banner note + targeted structural anchor
fixes (commit on `main`). **9 affected, 2 verified unaffected** (`crash-reporter-privacy`,
`lillistui-localization-a11y`). Load-bearing reconciliations:

- **`recovery-hardening` + `observability-logging`** (chain #1): `runMigration` now
  opens with TWO reentrancy guards + an `isMigrating` `defer`, a phase-6
  `accountStateProvider` guard, and a phase-8 `restoreSteadyState(...)` block; the init
  grew two nil-defaulted optional params. Both plans re-anchor by step comment and **do
  NOT add a third guard**; `recovery-hardening`'s Task-4 copy block stays a comment-only
  edit, and `MigrationJournal.isStale` is consumed (not re-added — it landed Wave 4).
- **`export-import-robustness`** (chain — bg-seam): `Importer.apply` / `Exporter.buildDocument`
  now run on `makeBackgroundContext()` (Importer's rollback-on-save already present;
  Exporter's attachment map split into TWO `taskID:` sites); the save-failure analysis now
  references the background context; reuse `CascadeReaper`.
- **`performance-budgets-and-paging`** (chain #2): `children(of:)` is structurally
  unchanged but `purgeAll` is batch-based and `countDescendants` is gone; **do NOT reroute
  list fetches through `makeBackgroundContext`** (they're the budgeted viewContext UI path).
- **`app-layer-test-rehab` / `extension-persistence-unification` / `privacy-manifest` /
  `ci-and-build-posture`** (chain #4): the iOS `Lillist-iOSAppHostedTests` target gained 3
  Wave-4 sources — re-Read `project.yml`, preserve them, grep the pbxproj after regenerating.
  `ci-and-build-posture` also: its pbxproj-drift gate validates the post-Wave-4 tree; it is
  the first place the two Wave-4 live-swap tests actually execute; **residual #11 now has
  THREE manifestations** (its bounded-parallelism + retry must name all three).
- **`cli-robustness`**: essentially unaffected, but a note now warns NOT to "modernize"
  `PurgeCommand` to the new batch `purgeAll` (per-resolution `hardDelete` is the correct
  all-or-nothing CLI path).

---

## Wave Handoff Protocol

Each wave is executed by a *different* executor in a vacuum. To bridge them,
**every executor reads the prior wave's handoff before starting and writes its
own on completion** — `docs/superpowers/handoffs/wave-N.md`. Waves 1–3 are
backfilled from the status entries above. Template:

```markdown
# Wave N handoff
From: Wave N executor   To: Wave N+1 executor   Date: <abs date>

## What landed
- <plan>: commits <shas>; <N> LillistCore tests green (+ iOS scheme if app-touching). Closed: <findings>.

## Shared files I moved (anchor by structure — line numbers are as-of-landing)
- <file>: <method/section> now ~<line>; <what changed>

## Assumptions I invalidated for later waves
- <e.g. runMigration gained a reentrancy guard at its first statement>

## Residuals I opened / closed
- <#refs>

## Pre-flight the next executor should run
- git log --oneline main | head -20  (confirm my commits present)
- <re-Read commands / anchor greps>
```

---

## The 22 plans

| Wave | Plan | Tier | Findings | Closes |
|------|------|------|----------|--------|
| 1 | [store-swap-safety](2026-05-28-store-swap-safety.md) | P0 | persist-3, sync-1/3/4/7, conc-4, test-1/2 | Transactional crash-safe store swap **+ executing migration test harness** (keystone) |
| 1 | [recurrence-input-hardening](2026-05-28-recurrence-input-hardening.md) | P0 | rec-1/2, stores-7 | `interval==0` crash on synced/imported data; count budget counts soft-deleted |
| 2 | [breadcrumb-truthfulness](2026-05-28-breadcrumb-truthfulness.md) | P1 | conc-1, stores-2, persist-8 | Breadcrumbs record false success on failed mutations |
| 2 | [fractional-ordering-compaction](2026-05-28-fractional-ordering-compaction.md) | P1 | stores-1/3 | Dead compaction valve → silent position collisions |
| 2 | [predicate-parity](2026-05-28-predicate-parity.md) | P1 | rules-1…7 | Two evaluators diverge on 4 ops; one-example parity suite; weeksFromNow overflow |
| 2 | [link-preview-ssrf-guards](2026-05-28-link-preview-ssrf-guards.md) | P1 | linkpreview-1/2/3 | Zero SSRF/scheme/redirect/size validation on pasted URLs |
| 3 | [cloudkit-convergence](2026-05-28-cloudkit-convergence.md) | P1 | persist-2/5, conc-3, notif-2 | Stable identities, remote-change reconcile, spec dedup, CKError posture |
| 3 | [resolve-inert-features](2026-05-28-resolve-inert-features.md) | P1 | persist-6, ios-1/4, macos-2, logs-2, crumbs-3, cli-1 | Wire-up or remove inert features |
| 4 | [concurrency-stress-tests](2026-05-28-concurrency-stress-tests.md) | P1 | conc-2/3, stores-4, notif-3/9, test-3 | CLAUDE.md-mandated actor-crossing stress tests |
| 4 | [migration-adjacent-correctness](2026-05-28-migration-adjacent-correctness.md) | P2 | notif-1, sync-2/5/6/8 | Morning-summary loss, staleness gate, account contract, reentrancy guard |
| 4 | [background-context-seam](2026-05-28-background-context-seam.md) | P2 | threading-1, persist-1/4, conc-5, notif-7 | Bulk work off the main-queue viewContext + rollback + history pruning |
| 5 | [crash-reporter-privacy](2026-05-28-crash-reporter-privacy.md) | P2 | redact-1/5, canary-4, test-6 | Redaction leaks + adversarial fixtures + canary PID fix |
| 5 | [app-layer-test-rehab](2026-05-28-app-layer-test-rehab.md) | P2 | ios-2/3, macos-4, ext-6 | Replace tautological/substitution tests; `GatedPersistenceResolver` seam |
| 6 | [extension-persistence-unification](2026-05-28-extension-persistence-unification.md) | P2 | ext-1…6 | Route `TaskEntityQuery` through the gate; Share/Intent correctness |
| 6 | [export-import-robustness](2026-05-28-export-import-robustness.md) | P3 | import-1/2/3, export-1 | Schema-version guard, orphan-entry skip, transaction contract |
| 6 | [cli-robustness](2026-05-28-cli-robustness.md) | P3 | cli-2…6 | Atomic batches, golden formats, dead `--exact`, `watch` via FRC |
| 6 | [performance-budgets-and-paging](2026-05-28-performance-budgets-and-paging.md) | Blind-spot | §761 budget, unbounded fetch | 10k-task perf budget test + `fetchBatchSize`/paging |
| 6 | [observability-logging](2026-05-28-observability-logging.md) | Blind-spot | logs-2 + no logger/MetricKit | `os.Logger` taxonomy, MetricKit, signposts; makes crash "logs" real |
| 7 | [privacy-manifest-export-compliance](2026-05-28-privacy-manifest-export-compliance.md) | **Ship-blocker** | critic #3 | `PrivacyInfo.xcprivacy` + `ITSAppUsesNonExemptEncryption` (app + 2 extensions) |
| 7 | [recovery-hardening](2026-05-28-recovery-hardening.md) | Blind-spot | critic #5 | Disk-space pre-flight, auto-backup, user-visible restore path |
| 7 | [lillistui-localization-a11y](2026-05-28-lillistui-localization-a11y.md) | P3 | ui-loc-1/2, ui-a11y-1, ui-test-1 | `defaultLocalization`, `.module` strings, reorder-action gating |
| 7 | [ci-and-build-posture](2026-05-28-ci-and-build-posture.md) | P2 | build-1…5, ui-warn-1, ui-snap-1, test-5 | GitHub Actions CI, warnings-as-errors parity, momc inputs (lands **last**) |

---

## Execution waves

Plans within a wave that touch **disjoint files** run in parallel. Plans sharing
a file follow the **serial chains** in the next section.

- **Wave 1 (P0 foundation):** `store-swap-safety` (keystone — owns the
  `runMigration` rewrite, the `PersistenceReconfiguring` seam +
  `FakePersistenceReconfigurer`, `QuarantineManager.copyStore` +
  `QuarantinedBackup`, the `MigrationJournal` field rename, and the app-hosted
  iOS test target; **five later plans rebase onto it**), in parallel with
  `recurrence-input-hardening` (fully disjoint).
- **Wave 2 (P1, no hard deps):** `breadcrumb-truthfulness` (must precede
  `background-context-seam`; re-anchors its 3 MigrationCoordinator crumb calls
  onto wave-1's rewritten `runMigration`), `fractional-ordering-compaction`,
  `predicate-parity` (≈zero collisions), `link-preview-ssrf-guards` (its
  LillistCore/CLI/policy work is independent; its `ShareRootView` gate defers to
  wave 6).
- **Wave 3 (P1):** `cloudkit-convergence` (prereq for
  `concurrency-stress-tests`; establishes `PersistenceController.localTransactionAuthor`),
  then `resolve-inert-features` (wires `AutoPurgeJob` + wave-4's
  `HistoryPruner.sweep` into `bootstrap()`; **wave-1 already wired
  `localStoreRowCount` in production — do NOT re-add it**). Both edit iOS
  `AppEnvironment.swift` in distinct regions — serialize them.
- **Wave 4:** `concurrency-stress-tests` (dependsOn `cloudkit-convergence`;
  reuses wave-1's `FakePersistenceReconfigurer`),
  `migration-adjacent-correctness` (dependsOn `store-swap-safety`),
  `background-context-seam` (after `breadcrumb-truthfulness` and
  `cloudkit-convergence`).
- **Wave 5 (P2):** `crash-reporter-privacy` (fully isolated),
  `app-layer-test-rehab` (introduces `GatedPersistenceResolver`; **must precede**
  `extension-persistence-unification`; starts the iOS `project.yml` chain).
- **Wave 6:** `extension-persistence-unification` (after `app-layer-test-rehab`),
  `export-import-robustness` (rebase onto wave-4 Importer/Exporter bodies),
  `cli-robustness`, `performance-budgets-and-paging`, `observability-logging`
  (last two coordinate the `TaskStore.children(of:)` signpost+paging+count-log
  ordering — land together, re-Read `TaskStore.swift` first).
- **Wave 7 (closing):** `privacy-manifest-export-compliance` (**last
  `project.yml` editor** — owns the final coordinated `xcodegen generate`),
  `recovery-hardening` (dependsOn `store-swap-safety`),
  `lillistui-localization-a11y` (just before CI so its lint becomes a CI job),
  then `ci-and-build-posture` **dead last** so its pbxproj-drift gate validates
  the final committed pbxprojs and CI runs the app-hosted tests every earlier
  plan contributed.

Declared hard dependencies: `concurrency-stress-tests` → `cloudkit-convergence`;
`migration-adjacent-correctness`, `ci-and-build-posture`, `recovery-hardening` →
`store-swap-safety`.

---

## Shared-file serial chains (do not parallelize these)

For each hotspot, land in the listed order; every non-owner **re-Reads the file
and re-anchors by code structure, not the review's line numbers** (wave-1's
rewrite invalidates line anchors).

1. **`Sync/MigrationCoordinator.swift`** (6 plans) — ✅ `store-swap-safety`
   (owns the `runMigration` rewrite: reconfigure-before-copy, `copyStore` not move,
   `quarantineFolderName` rename, `localStoreRowCount` precondition,
   `host: any PersistenceReconfiguring`) → ✅ `breadcrumb-truthfulness`
   (3 `breadcrumb(...)` calls now `await`) → ✅ `migration-adjacent-correctness`
   (**landed Wave 4** — `runMigration` now opens with TWO reentrancy guards: a
   synchronous `journal.read().isInFlight` throw THEN a `@MainActor isMigrating`
   flag + `defer`, both before the first `await`; a `restoreSteadyState(...)` call
   in `.finalizing`; a pre-erase `accountStateProvider` guard in the
   `replaceICloudWithLocal` block; init grew `preferencesStore` + `accountStateProvider`
   optional params) → ✅ `cloudkit-convergence` (additive) → ⬜ `recovery-hardening`
   (**Wave 7** — hook disk-check into store-swap-safety's precondition; **do NOT add
   a THIRD entry guard** — reconcile onto the two Wave-4 guards; Task 4's step-5 copy
   block is byte-identical and stays a comment-only edit; init's 2 new optional params
   are nil-defaulted, so the test construction is unchanged) → ⬜ `observability-logging`
   (**Wave 6** — signpost/log brackets woven AFTER the reentrancy guards, around the
   phase-6 account guard and the phase-8 `restoreSteadyState` block; re-anchor by step
   comment, not line number).
2. **`Stores/TaskStore.swift`** (6 plans) — ✅ `breadcrumb-truthfulness` (owns the
   canonical `do/catch` shape on the 4 defer mutators) → ✅ `background-context-seam`
   (**landed Wave 4** — `context.rollback()` added to ALL 12 shared-context mutators
   (the original 8 + `transition`/`reorder`/`assignTag`/`unassignTag`, the last three
   newly wrapped in `do/catch`); `purgeAll` rewritten to a background-context batch
   delete via `batchPurge` + `CascadeReaper`; the private `countDescendants` helper
   **deleted**; bodies otherwise untouched). Disjoint methods, any order, each
   re-Reading first: ✅ `fractional-ordering-compaction` (`reorder`), ⬜
   `performance-budgets-and-paging` (`children` overload — `children(of:)` itself is
   structurally UNCHANGED by Wave 4; do NOT reroute list fetches through
   `makeBackgroundContext`), `recurrence-input-hardening` (test-only, ✅),
   ⬜ `observability-logging` (`children` signpost). **`performance-budgets-and-paging`
   + `observability-logging` co-land (both edit `children(of:)`) — re-Read first.**
3. **`Extensions/ShortcutsActions/IntentSupport.swift` + `ShareRootView.swift`**
   — `app-layer-test-rehab` (extracts `GatedPersistenceResolver`, routes
   `makePersistence()` + `save()` through it) → `extension-persistence-unification`
   (per-process cache + `ShareSaveFlow` **on top of** the resolver; `try?`→`try`
   on attachment) → `link-preview-ssrf-guards` **Task 6** (wrap
   `URLPreviewPolicy.isAllowed` around whichever `addLinkPreview` survives — its
   policy/fetcher/CLI Tasks 1–5 already merged in Wave 2; **only this
   Share-Extension gate remains, deferred here to Wave 6** — see residual #10).
4. **iOS `project.yml` + `pbxproj`** (5 plans) — serialize all: ✅ `store-swap-safety`
   (created the `Lillist-iOSAppHostedTests` target) → ✅ **Wave 4 added 3 sources to
   that target** (`concurrency-stress-tests`' `StoreReconfigureConcurrencyTests.swift`;
   `migration-adjacent-correctness`' `MigrationCoordinatorRestoreTests.swift` +
   `Helpers/FakeUserNotificationCenter.swift`; pbxproj regenerated to match) → ⬜
   `app-layer-test-rehab` (Wave 5 — edits the *separate* `Lillist-iOSTests` target) →
   ⬜ `extension-persistence-unification` (test sources) → ⬜
   `privacy-manifest-export-compliance` (resources; **last editor — owns the final
   authoritative `xcodegen generate`**) → ⬜ `ci-and-build-posture`'s drift gate
   validates the result. **Every Wave-5+ editor must re-Read `project.yml` and NOT
   clobber the 3 Wave-4 app-hosted entries; grep the pbxproj after each regenerate to
   confirm they survive.**
5. **macOS `Apps/project.yml` + `pbxproj`** — `resolve-inert-features`
   (`CommandNotifications.swift`) then `privacy-manifest-export-compliance`
   (resources); one coordinated regenerate.
6. **`Packages/LillistUI/Package.swift` + `.github/workflows/`** —
   `ci-and-build-posture` (whole-file `Package.swift` replace; creates `ci.yml`)
   then `lillistui-localization-a11y` (re-Read, add only `defaultLocalization:
   "en"`; add its localization-lint as a **job in `ci.yml`**, drop the standalone
   yml). _Note: this is the one place where the wave order (CI last) and the
   chain order coincide — land `lillistui-localization-a11y`'s Package.swift +
   string work in wave 7 just before `ci-and-build-posture`._
7. **`Persistence/QuarantineManager.swift`** — `store-swap-safety` (`copyStore`,
   `QuarantinedBackup`, `quarantinedStore(folderName:)`) → `recovery-hardening`
   (`diskSpaceProbe` param + pre-flight guard at the top of `copyStore`).
8. **`Persistence/PersistenceController.swift`** — ✅ `cloudkit-convergence`
   (`transactionAuthor`/`localTransactionAuthor` + merge-policy rationale) → ✅
   `background-context-seam` (**landed Wave 4** — `makeBackgroundContext()` added after
   `localTaskRowCount()`: auto-merge ON, trump policy, and it now also stamps
   `transactionAuthor = localTransactionAuthor`; `viewContext`'s
   `automaticallyMergesChangesFromParent` kept — it's the active CloudKit channel). **No
   Wave-5+ plan edits this file; later plans only USE `makeBackgroundContext()` / the
   `init(configuration:)` they reference is unchanged.**
9. **iOS `AppEnvironment.swift`** (4 plans, distinct regions, serialize) — ✅
   `migration-adjacent-correctness` (**landed Wave 4** — added `preferencesStore:`
   to the `MigrationCoordinator(...)` call) → ✅ `resolve-inert-features` (wired
   AutoPurgeJob into `bootstrap()`) → ✅ `cloudkit-convergence` (reconciler +
   `normalizeSingletons`) → ✅ `background-context-seam` (**landed Wave 4** — wired
   `HistoryPruner(...).sweep()` fire-and-forget into `bootstrap()` right after
   `autoPurgeJob.run()`) → ⬜ `observability-logging` (**Wave 6** — adds
   `metricKitObserver`; the `bootstrap()` tail — `startObservingPauseReason()` last —
   is UNCHANGED by Wave 4; append after it; do NOT disturb the new HistoryPruner /
   preferencesStore wiring). `localStoreRowCount` already wired by wave 1 — don't
   re-add. **Only `observability-logging` remains.**
10. **`Sync/MigrationJournal.swift` + `NotificationSpecStore.swift` +
    `PersistenceHost.swift` + `docs/engineering-notes.md`** — append-only /
    distinct-member edits; sequence by wave, re-Read before each append. The
    `NotificationSpecStore.add` at-most-one-default fix is owned by
    `cloudkit-convergence`; `concurrency-stress-tests` only adds the stress test
    that proves it (✅ Wave 4, green by design). **Wave 4 also: `MigrationJournal`
    gained `isStale(now:threshold:)` + `staleThreshold = 600` (migration-adjacent —
    recovery-hardening consumes it, does not re-add); `NotificationScheduler` gained
    `restoreSteadyState` + morning-summary-preserving `cancelAllPending`; and
    `engineering-notes.md` got TWO new sections (concurrency invariants; single-context
    + background seam) — later append-only editors (`observability-logging`,
    `performance-budgets-and-paging`, `recovery-hardening`) must Read the true EOF, NOT
    assume the SIGSEGV entry is last.**

---

## Two plan defects already fixed (2026-05-29)

The consistency critic caught two issues that were corrected in-place before this
index was written:

- **`background-context-seam` Task 6** previously shipped full method-body
  rewrites of the four `TaskStore` mutators that would have **reverted**
  `breadcrumb-truthfulness`. Now shows rollback-only before→after diffs matching
  breadcrumb-truthfulness's landed shape verbatim, plus a true RED multi-level
  cascade test for `purgeAll` (Task 5).
- **`store-swap-safety` Task 3** now explicitly rebuilds the rollback store
  description via `makeStoreDescription(for:)` so `cloudKitContainerOptions`
  round-trip, with an ungated test asserting the rolled-back description still
  carries the original `containerIdentifier` / `databaseScope` (Roadmap #1's
  "preserving cloudKitContainerOptions" requirement).

## Executor confirm-before-relying callouts

Two plans have honest-but-soft verification the executor must confirm:

- **`background-context-seam` Task 5** — the `purgeAll` `NSBatchDeleteRequest`
  cascade count math on multi-level trees (batch delete skips delete rules);
  verify the explicit `CascadeReaper` reproduces the model's Cascade rules
  (children/journalEntries/attachments/notificationSpecs) for deep trees.
- **`migration-adjacent-correctness` Tasks 2/4/5** — three findings are proven
  only by compile + the app-hosted target (introduced by `store-swap-safety`) +
  CI running the iOS scheme (`ci-and-build-posture`, last wave). Their real
  executing proof is deferred to wave 7 — don't read their green self-review
  checkmarks as "verified under bare `swift test`."

## Known residuals / explicit follow-ups (not silently dropped)

These are out of scope of the 22 plans by deliberate decision; capture as backlog
so coverage isn't overstated:

1. **DNS-rebinding SSRF** (public hostname resolving to a private IP at connect
   time) — `link-preview-ssrf-guards` blocks literal-IP + well-known names only.
   Needs sign-off or a follow-up (connect-time IP re-check).
2. **`mergeByPropertyObjectTrump` last-writer-wins data loss on concurrent
   cross-device edits** — `cloudkit-convergence` documents the policy as a kept
   YAGNI decision and handles CKError quota/rate-limit, but no plan implements a
   per-entity custom `NSMergePolicy`. Decide whether trump is the intended task
   conflict semantic.
3. **Orphaned pending `UNNotificationRequest`s on hard-delete/purge** (notif-7
   residual) — `background-context-seam` reaps `NotificationSpec` rows but no plan
   cancels the OS-level pending requests for purged tasks. ✅ **DOCUMENTED in Wave 4**
   — `background-context-seam` recorded it as an acknowledged limitation in
   `docs/engineering-notes.md` (the 2026-06-04 single-context entry); cancelling the
   OS-level requests is out of the 22-plan scope and stays a named follow-up for a
   future notif-focused micro-fix.
4. **`pause-reason` `.noNetwork` / `.iCloudDriveDisabled`** remain unreachable —
   `resolve-inert-features` drives the classifier but doesn't add an
   `NWPathMonitor`-backed reachability provider. Follow-up.
5. **macOS background purge** — `resolve-inert-features` wires iOS
   `BGProcessingTask` + launch purge; macOS gets launch-time purge only (no
   `NSBackgroundActivityScheduler`). Minor.
6. **App-target string catalogs** — `lillistui-localization-a11y` covers the
   LillistUI catalog only; the iOS app's catalog and the empty macOS app catalog
   are un-owned (localization is intentionally out-of-v1 per design §816/842,
   but the catalogs remain structurally unprepared, per the review).
7. **`predicate-parity` rules-5** — ✅ **RESOLVED** (merged `2ba034c`). The explicit
   `RelativeDate.weeksFromNow` integer-overflow clamp is in
   `RelativeDateResolver.resolve` (`multipliedReportingOverflow(by: 7)` → saturate
   to `Int.max`/`Int.min`), proven by `RelativeDateWeeksOverflowTests` (pre-fix:
   signal-5 trap on `Int.max * 7`; post-fix: no trap). No magnitude/threshold
   guard added (YAGNI). Both evaluators share the one resolver, so the clamp is
   parity-safe.
8. **Non-positive recurrence `count` semantics** (`recurrence-input-hardening`
   audit, LOW) — a present-but-non-positive `count` from a corrupt sync record
   currently yields an **empty/disabled series**, which is the existing *tested*
   behavior (`RecurrenceExpanderLimitTests."count=0 yields no occurrences"`).
   The audit noted this is the same "one corrupt record strips recurrence" class
   the `interval` fix closes, but flipping it to "treat `count <= 0` as unbounded"
   reverses a deliberate prior decision — a **product call left to the user**, not
   silently changed. (An attempted fix was reverted for exactly this reason.)
9. **Recurrence out-of-range field values** (`recurrence-input-hardening` audit,
   INFO — all confirmed **non-crashing**) — untrusted `byMonthDay` outside
   `1...31` and `bySetPos == 0`/out-of-range yield a silently *dead* rule (guarded
   by `range.contains` / `indices.contains`, no trap); a huge-but-finite
   `AfterCompletionRule.interval` (Double) decodes fine (JSONDecoder rejects
   `NaN`/`Inf`) and produces a far-future spawn. None crash; left as abuse-
   resistance hardening if ever prioritized.
10. **`link-preview-ssrf-guards` Task 6 — iOS Share Extension ingest gate**
    (DEFERRED, not dropped) — Tasks 1–5 (policy + fetcher + CLI ingest) merged in
    Wave 2, but Task 6 (wrapping `URLPreviewPolicy.isAllowed` around
    `ShareRootView`'s `addLinkPreview`) is intentionally carried to **Wave 6**: per
    chain #3, `app-layer-test-rehab` (Wave 5) and `extension-persistence-unification`
    (Wave 6) restructure `ShareRootView.swift` first, and Task 6 must wrap whichever
    `addLinkPreview` survives. Until it lands, the iOS Share Extension can still
    persist an SSRF-bait URL as a link attachment (the *fetch* is already blocked by
    the merged fetcher guard, so no request is made — only the row persists). Owner:
    Wave 6, alongside `extension-persistence-unification`.
11. **Intermittent parallel-test instability — rare SIGSEGV + rare timing flakes**
    (investigated 2026-06-04, `cloudkit-convergence` / `resolve-inert-features`
    verification). Two manifestations, one root cause (parallel-test CPU
    contention), one systemic fix. **(a)** `swift test` rarely (~1/15–20 full runs)
    aborts with signal 11 in a `ParitySuiteTests` case — Swift Testing runs ~100+
    parameterized cases in parallel, each creating an in-memory
    `NSPersistentContainer` sharing one cached `NSManagedObjectModel`; concurrent
    `loadPersistentStores` races Core Data's framework-internal lazy
    `NSEntityDescription` setup. **(b)** `SyncQuiesceMonitorTests."Times out when
    events arrive faster than the quiet window"` rarely gets `.quiesced` not
    `.timedOut` — under load the churner/watcher `Task` stalls past the 300ms quiet
    window, so the monitor sees a false quiet gap. Both are **test-only**, **not
    reproducible on demand**, **not product bugs** (production makes one container;
    real CloudKit events aren't "starved"; `SyncQuiesceMonitor` is an explicit
    best-effort heuristic). No source fixes applied (unverifiable for timing-
    dependent failures; a margin tweak/clock-injection would be a symptom band-aid
    or disproportionate). **Owner: Wave 7 `ci-and-build-posture`** — bound test
    parallelism (`--num-workers N` / `--no-parallel` on container-heavy +
    timing-sensitive suites) and/or add a retry for one-off SIGSEGV/timing flakes.
    Full analysis in `docs/engineering-notes.md` (2026-06-04 entry). **Re-run a
    full `swift test` before treating a single SIGSEGV/timing flake as a real
    failure.** **(c) Third manifestation observed during Wave 4:**
    `TaskStoreRecurrenceSpawnTests."After-completion series spawns at completedAt +
    interval"` rarely fails its `abs(spawn.start − (beforeClose + interval)) < 2.0`
    wall-clock assertion (~2.03s) when the full suite runs under heavy parallel
    load — the gap between capturing `beforeClose` and the internal `completedAt`
    stamp exceeded the 2s tolerance. Passes in isolation and on re-run; same
    root cause (CPU contention), same Wave-7 remedy. Not a Wave-4 regression.
12. **`AutoPurgeJob.run` return count is now matched+cascade** (Wave 4
    `background-context-seam`) — the batch-delete rewrite changed `run()`'s return
    from "matched victim rows" to "matched victims + every cascade-reachable
    descendant task." These diverge only when a soft-deleted parent and child have
    `deletedAt` straddling the retention cutoff; the **data outcome is identical**
    (the cascade deleted the child either way) and **both app callers discard the
    return value** (`_ = try? await autoPurgeJob.run()`). `purgeAll`'s count is
    exactly preserved. Documented in `docs/engineering-notes.md`; not a bug, no fix
    owed — captured so the count semantics aren't silently overstated.

## Suggested commit/PR cadence

Solo project → commit directly to `main` (per CLAUDE.md), one small conventional
commit per task as each plan prescribes. Land one wave at a time; run the full
`swift test` for both packages after each plan, and the iOS xcodebuild scheme
after any plan touching app targets, extensions, or the model. `ci-and-build-posture`
(wave 7) makes all of this enforced automatically going forward.
