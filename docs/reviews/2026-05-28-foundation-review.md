# Lillist Foundation Review — 2026-05-28

**Verdict: `solid-with-gaps`.** Lillist is genuinely well-architected for a
solo project. The happy paths are sound; the cracks all live on the *failure
surface* and at *trust boundaries* — exactly where the next phase will lean
hardest.

## Methodology

Multi-agent review: 16 focused lanes (each grounded in the real code, not
guesses), every medium-and-above finding handed to an **independent adversarial
verifier** that re-read the cited code and defaulted to "refuted" unless it
could confirm the issue itself, then two synthesis passes (a prioritization
roadmap + a completeness critic that named blind spots no lane owned).

- **132 findings** raised, **1 refuted**, **131 survived** verification.
- Corrected-severity mix: **11 high · 37 medium · 82 low · 1 info**.
- Verifier verdicts: 45 confirmed · 44 partial · 42 unverified (low/info passed through).
- Raw data: workflow run `wf_b3d93644-8b5` (108 agents, ~6M tokens).

## Executive summary

The DTO boundary is airtight (no `NSManagedObject` escapes `LillistCore`), actor
isolation is principled, date math is correctly `Calendar`-based, and the
`AsyncStream` pre-subscription race was root-caused and fixed properly. Three
through-lines dominate the gaps:

1. **The Plan-21 store swap + zone erase is both structurally unsafe in spots
   AND effectively untested** — a live SQLite file is moved out from under an
   open container; there's no in-process rollback on a failed reconfigure; and
   the load-bearing migration tests *silently skip* under `swift test`. A
   data-loss regression would ship green.
2. **Cross-device CloudKit correctness is assumed but unbuilt** — no
   deduplication, no remote-change-driven reconcile, and an `AppPreferences`
   "singleton" that duplicates across devices. Single-device tests can't see any
   of it.
3. **Several shipped features are inert** (sync pause-reason, `AutoPurgeJob`,
   dead menu commands, crash-reporter logs/breadcrumbs, the CLI `time_zone`
   knob) while some suites that should catch this re-implement production logic
   or assert tautologies.

Layered on top: real trust-boundary defects — `interval == 0` crashes the
recurrence expander on synced/imported data; breadcrumbs record false-success on
half the mutators (poisoning crash forensics); the predicate engine's two
evaluators silently diverge on four shipped operators; and the link-preview
pipeline does zero SSRF/scheme validation on pasted URLs. None block current
single-device use, but each undermines the "rock-solid foundation" bar.

## Top risks

| Sev | Risk |
|-----|------|
| **CRITICAL** | Destructive sync-mode swap can corrupt/strand the store, and its safety net is untested (`persist-3`, `sync-4`, `sync-1`, `test-1`, `test-2`). |
| **HIGH** | `interval == 0`/negative crashes the recurrence expander on untrusted (synced/imported/CLI) data (`rec-1`). |
| **HIGH** | No CloudKit dedup or remote-change convergence; `AppPreferences` flip-flops across devices (`persist-2`, `notif-2`). |
| **HIGH** | Breadcrumb crash-forensics record false success on failed mutations (`conc-1`, `stores-2`, `persist-8`). |
| **MEDIUM** | Predicate engine's two evaluators silently diverge on four shipped operators; parity suite is one-example-per-behavior (`rules-1..4`, `rules-6`). |
| **MEDIUM** | Link-preview pipeline does zero SSRF/scheme/redirect validation on user URLs (`linkpreview-1..3`). |
| **MEDIUM** | Multiple shipped features wired but inert, masked by tautological tests (`persist-6`, `ios-1`, `macos-2`, `cli-1`). |

---

## Prioritized roadmap

### P0 — foundation (must fix before building more on top)

**1. Make the destructive store-swap transactional and crash-safe** _(data-integrity, medium)_
- Reorder `runMigration` so the store is flushed/removed (connection closed) **before** the file is touched, and quarantine by **copy** not move (delete original only after a clean remove).
- Make `flushAndSwap` transactional: capture the original `NSPersistentStoreDescription` (preserving `cloudKitContainerOptions`) before remove, wrap remove+add in do/catch, re-add the original on add-failure, surface `LillistError.storeUnavailable` if rollback also throws.
- Wrap coordinator remove+add inside the **same** `viewContext.perform` that does the flush — one atomic main-queue critical section.
- Tie journal `quarantineBackupID` to the actual on-disk folder name; precondition that the local store exists and is non-empty before `replaceICloudWithLocal`'s irreversible erase.
- _Findings: persist-3, sync-4, conc-4, sync-7._

**2. Give the migration state machine real, executing test coverage with failure injection** _(testing, large)_
- Add a `PersistenceReconfiguring` protocol seam + fake so `runMigration` runs end-to-end under `swift test`; assert exact `MigrationPhase` order, journal-state sequence, eraser `callCount` (0 for `disableNow`, 1 only for `replaceICloudWithLocal`), and `cancelAllPending` before any destructive step.
- Add a throwing `FakeCloudKitZoneEraser` + throwing journal-store decorator; inject failure per phase boundary; assert `.failed` journal with correct `previousMode`/`quarantineBackupID`, rethrow, and that a secondary catch-write failure doesn't mask the original.
- Test `QuarantineManager.restore`/`latestQuarantinedStore`/`quarantineStore` directly, then two **ungated** `restoreFromBackup` tests (happy path + no-backup `storeUnavailable`).
- Wire `LillistCore` tests into an app-hosted unit-test target (real `CFBundleIdentifier`), document the command in CLAUDE.md, add a host-gated meta-test asserting `liveSwapAllowed == true` so a misconfigured host can't masquerade as green.
- _Findings: sync-1, sync-3, test-1, test-2._

**3. Harden the recurrence engine against untrusted interval/count input** _(data-integrity, small)_
- Normalize `interval = max(1, interval)` at the `CalendarRule` trust boundary in **both** `init` and `init(from:)`, logging a warning rather than throwing (which would drop recurrence on sync corruption).
- Defense-in-depth `let n = max(1, rule.interval)` at the expander modulo sites.
- Filter soft-deleted instances out of `RecurrenceSpawner.countReached` (or add a monotonic `spawnedCount` on `Series`).
- Add expander + JSON-decode tests for `interval ∈ {0, -1}` across all four frequencies, and a spawner test trashing an instance of a `count = N` series.
- _Findings: rec-1, rec-2, stores-7._

### P1 — high

**4. Fix breadcrumb false-success across all mutators and the migration coordinator** _(maintainability, small)_ — replace the nine `defer { Task { recordCrumb(success: true) } }` sites with inline do/catch that records the true flag in operation order; add a test forcing a failing mutation that asserts `success: false`. (`conc-1`, `stores-2`, `persist-8`)

**5. Build CloudKit cross-device convergence** _(sync, large)_ — stable well-known `AppPreferences` UUID + one-time normalization pass; `NSPersistentStoreRemoteChange` observer with history-token diffing that enqueues `reconcile(taskID:)` on import; set `viewContext.transactionAuthor`/`.name`; enforce at-most-one default spec per `(taskID, kind)`; two-store integration tests asserting convergence. (`persist-2`, `conc-3`, `notif-2`, `persist-5`)

**6. Add SSRF/scheme/redirect/size guards to the link-preview pipeline** _(security-privacy, medium)_ — shared `URLPreviewPolicy` (http/https only; reject localhost/`*.local`/loopback/link-local/RFC1918); `URLSessionTaskDelegate` re-applying policy on redirect + hop cap; streaming 5MB cap with early abort; apply at the `LinkHandler`/ShareExtension ingest boundary; `StubURLProtocol` negative tests. (`linkpreview-1..3`, `test-1`)

**7. Make the predicate-engine parity suite matrix-driven and align the four divergent operators** _(ux-correctness, medium)_ — unify ancestor depth into one `maxAncestorDepth`; align `equals` to diacritic+case-insensitive matching `==[cd]`; single source of truth for recurrence/`hasNudges`; symmetric `isAncestorOf`; generalize parity to a `Field × Op × Value` matrix (incl. nil/empty/diacritic/case) driving **both** evaluators against a DST-straddling non-UTC fixture; guard `RelativeDate.weeksFromNow` overflow. (`rules-1..7`)

**8. Resolve inert/dead features: wire them up or remove them honestly** _(ux-correctness, medium)_ — wire `AutoPurgeJob` into `AppEnvironment.bootstrap()` + iOS `BGProcessingTask`; drive (or delete) the iOS pause-reason classifier; remove the dead iOS `CommandMenu` block + the four unobserved macOS Indent/Outdent/Find items; decide crash-reporter logs/breadcrumbs scope (real on-disk buffer or remove the toggles); centralize CLI `time_zone` into a `Config.resolvedCalendar()` or remove it. (`persist-6`, `ios-1`, `ios-4`, `macos-2`, `logs-2`, `crumbs-3`, `cli-1`)

**9. Wire compaction into the fractional-ordering reorder path** _(data-integrity, small)_ — in `TaskStore.reorder`/`SmartFilterStore.reorder`, recompact when the midpoint isn't strictly between neighbors (fetch siblings, recompact, persist all in one `perform`, recompute target); add the missing out-of-order anchor guard; integration test of 60+ same-region inserts. (`stores-1`, `stores-3`)

**10. Add the mandated concurrency stress tests for actor-crossing code** _(concurrency, medium)_ — concurrent `reconcile(taskID:)` stress (TaskGroup, high iterations) asserting final pending set + one default spec; N-concurrent-subscriber AsyncStream tests; stress `TaskStore.create`/`fetch` during a reconfigure (under xcodebuild); a real second-context tripwire for find-or-create + consider a `Tag(parent,name)` unique constraint. (`conc-2`, `conc-3`, `stores-4`, `notif-3`, `notif-9`, `test-3`)

### P2 — medium

**11. Fix migration-adjacent correctness** — post-migration morning-summary restore + per-task notification re-install; implement `MigrationJournal.isStale` (main-app recovery only; keep `MigrationGate` aborting headless callers); correct the `PauseReason` docstring + optional account-identity pre-flight; coordinator reentrancy guard. (`notif-1`, `sync-2`, `sync-5`, `sync-6`, `sync-8`)

**12. Fix crash-reporter privacy leaks and add adversarial redaction tests** — `.caseInsensitive` key=value passes, stop emitting PII in key=value form; case-insensitive container hex + App-Group subtree + temp-path pass; adversarial golden fixtures (multi-word/quoted/mixed-case values, lowercase container UUIDs, temp + app-group paths); canary self-PID disambiguation via `startedAt`. (`redact-1`, `redact-5`, `canary-4`, `test-6`)

**13. Move bulk Core Data work off the main-queue viewContext via a targeted background-context seam** — `Exporter`/`Importer` on a dedicated `newBackgroundContext`; `NSBatchDeleteRequest` (reproducing cascade rules explicitly) for `purgeAll`/`AutoPurgeJob`; `context.rollback()` in every mutating `perform` catch; keep the single-context-on-main default and document it. (`threading-1`, `persist-4`, `conc-5`, `notif-7`, `persist-1`)

**14. Replace test-substitution and tautological app-layer tests with real wiring coverage** — direct test of the MigrationGate-gated persistence resolution; extract `submit()`/`save()` parse-persist bodies + macOS `applyDrop` mapping + focus-gating predicate into pure helpers and unit-test those (share drag mapping with iOS); delete the tautological tests; rename misleading composition tests. (`ios-2`, `ios-3`, `macos-4`, `ext-6`)

**15. Unify the extension persistence factory through the gate and fix Share/Intent correctness** — route `TaskEntityQuery.makePersistence()` through `IntentSupport.makePersistence()`; cache one per-process `PersistenceController` behind the gate; limit-aware `suggestedEntities` (20); propagate link-attachment failure in `ShareRootView.save()`; implement (or remove) `OpenTaskIntent`/`QuickCaptureLockScreenIntent`. (`ext-1..6`)

**16. Establish CI and align the build posture** — GitHub Actions macOS workflow: `swift test` for both packages, the iOS xcodebuild test scheme, `xcodegen generate` + `git diff --exit-code` for pbxproj drift, a Release archive smoke build (note deployit hardcodes `-configuration Debug`); bump LillistUI to swift-tools 6.2 + `.treatAllWarnings(as: .error)`; make `CompileCoreDataModel` declare the inner `contents`/`.xccurrentversion` as `inputFiles`. (`build-1..5`, `ui-warn-1`, `ui-snap-1`, `test-5`)

### P3 — nice-to-have

**17. Make export/import robust to malformed and forward-incompatible bundles** — guard `document.version` before `apply()`; skip orphan journal entries; decide+document the import transaction contract; deterministic malformed-HTML test. (`import-1..3`, `export-1`, `test-2`)

**18. Close CLI/rendering robustness gaps** — pre-resolve batch tokens before any mutation (all-or-nothing destructive stdin batches); byte-exact golden tests for json/ndjson/tsv; remove the dead `--exact` mention + `resolveExactTitle`; adopt `NSFetchedResultsController` for `watch`. (`cli-2..6`)

**19. Address LillistUI localization-readiness and accessibility correctness** — add `defaultLocalization: en`; `.module`-pinned localized strings + catalog extraction + CI lint; move `RecurrenceEditorViewModel.humanSummary` to localized strings with plural rules; gate each reorder `accessibilityAction` on its non-nil closure; replace the tautological reorder-action test. (`ui-loc-1`, `ui-loc-2`, `ui-a11y-1`, `ui-test-1`)

---

## Blind spots (named by the completeness critic — no lane owned these)

These are things a rock-solid foundation needs that the per-lane review didn't
cover, verified absent by direct search:

1. **No CI/CD at all** — no `.github/workflows`. Design doc §767/841 promises
   "Xcode Cloud CI." Every quality gate (warnings-as-errors, 649+28 tests,
   snapshots, the runtime-skipped migration tests) is enforced only by what the
   dev remembers to run locally — and `test-1`/`test-2` prove the most
   safety-critical tests already silently skip with nothing to catch it.
2. **Performance budgets entirely unverified** — design §761 promises an
   assertion-tested "< 100ms against 10,000 tasks" smart-filter budget. Zero
   `measure()`/`XCTMetric`/perf tests exist; the largest dataset any test builds
   is ~501 rows. Also: the **main task-list fetch (`TaskStore.swift:205`) is
   unbounded** — no `fetchBatchSize`/`fetchLimit`/paging — and faults+projects
   every row on the main-queue `viewContext` on every reload.
3. **App Store / TestFlight submission readiness** — no `PrivacyInfo.xcprivacy`
   anywhere, yet the app uses required-reason APIs (`UserDefaults` reason CA92.1,
   file-timestamp reason C617.1). No `ITSAppUsesNonExemptEncryption` in any
   Info.plist, so every submission stalls on the export-compliance prompt. A
   hard blocker for the OTA goal.
4. **No observability** — no MetricKit, no signposts, no structured `os.Logger`
   in production paths (only 43 `print()` calls); `OSLog` appears only in the
   crash-reporting `OSLogFetcher`, which the crash lane found non-functional.
   For an OTA app, there's effectively no field-diagnostics capability.
5. **Data-loss / recovery story is thinner than any lane conveyed** — the only
   backup is the migration-time quarantine copy; no pre-destructive-op
   disk-space check; the only user-facing export is manual; `restoreFromBackup`
   is untested. Combined with `persist-3` the recovery posture is weak.
6. **CloudKit-at-scale failure modes unmodeled** — a `LillistError.quotaExceeded`
   case exists but there's no handling of `CKError` quota/rate-limit/server
   rejection, and the only conflict policy is the blunt store-wide
   `mergeByPropertyObjectTrump` (which silently discards a concurrent device's
   edit). Steady-state sync resilience (vs. the migration state machine) was
   never examined.

_Note: localization being out-of-v1 (design §816/842) is **intentional**, not a
defect — but the empty catalogs are structurally unprepared for when it's turned
on._

## Strengths to preserve (don't refactor these away)

- **Airtight DTO boundary** — every public store returns Sendable value types via a single `record(from:)`; no `NSManagedObject` escapes `LillistCore` anywhere. The single most valuable structural property.
- **Synchronous same-actor AsyncStream continuation-registration** (CloudKitEventBridge/AccountStateMonitor/SyncStatusMonitor) closing the pre-subscription drop race, with the `preSubscriptionEventBuffering` regression test. **Do not revert to deferred-Task registration.**
- **Calendar-based date math throughout** — DST/month-length/leap-year correct by construction; the one `addingTimeInterval` is correctly isolated to `afterCompletion`.
- **Principled actor isolation** — all in-memory mutable state actor-guarded; `@unchecked Sendable` confined to context-backed types where threading is delegated to `NSManagedObjectContext.perform`.
- **Injection-safe NSPredicate construction** — every value parameterized via `%@`/`%K`/`%d`, zero interpolation; stable discriminator-keyed Codable with unknown-discriminator-throws tests.
- **Container/presenter split** — pure presentation Screens (no `@State`/`.task`) letting `IOSScreenTourTests` render real screens with frozen mock data.
- **Static-factory persistence design** (`makeContainer`/`makeStoreDescription`) testing the CloudKit option contract without a live container; cached `sharedModel()`; clock-injected `QuarantineManager` that re-quarantines before overwriting.
- **Disciplined composition roots** (`AppEnvironment` = explicit constructor injection, not a service locator) + well-extracted pure helpers (hotkey encode/parse, placement math, selection advance, `DragController` state machine).
- **Build hygiene** — consistent dependency pinning, clean idempotent signing xcconfig indirection, monotonic tracked build-number counter, strict concurrency + warnings-as-errors on LillistCore and both apps.

## Per-lane health

| Lane | Health |
|------|--------|
| Persistence & Core Data | Disciplined structure; gaps in history pruning, dedup, store-swap file ordering, main-queue funnel. |
| **CloudKit Sync & Migration** | Well-decomposed seams; failure surface untested + partly unhandled. **Highest risk.** |
| Concurrency | More disciplined than typical; breadcrumb false-success + reconcile reentrancy + zero stress tests. |
| Stores | Well-factored; dead compaction valve, breadcrumb defer, no stress tests. |
| Rules / Predicate | Strong types + injection-safe; two evaluators diverge on 4 ops; parity suite one-example-per-behavior. |
| Recurrence | Strongest-tested lane; trusts public API → `interval==0` crash on synced data. |
| Notifications | Well-layered, not a God object; morning-summary loss + dedup no-op + reconcile TOCTOU. |
| Crash Reporting | Well-layered; redactor leaks under dirty input; logs+breadcrumbs non-functional in prod. |
| CLI | Clean command/handler split; dead `time_zone`, dead `--exact`, unbounded `watch` Tasks. |
| Export/Import & Link Preview | Clean seams; zero SSRF validation; no schema-version check; heavy work on viewContext. |
| LillistUI | Good container/presenter + DragController; localization broken; brittle exact-pixel snapshots. |
| iOS App | Faithful thin-wrapper; dead pause-reason feature; test-substitution suite. |
| macOS App | Competent shell; hotkey reverts on relaunch; 4 dead menu commands; reindex-per-save amplification. |
| Extensions | Reuses Core well; `TaskEntityQuery` bypasses the gate + syncMode; two no-op "open app" intents. |
| Test Architecture | Strong unit foundation (649 pass clean); migration tests silently skip; `restoreFromBackup` untested. |
| Build/Tooling | Disciplined pinning + signing; Debug-only OTA, inconsistent warnings posture, no CI. |

---

## Appendix A — High-severity findings (with evidence)

> All confirmed by an independent verifier that re-read the cited code.

- **`persist-3`** Migration quarantine moves the live SQLite file out from under the still-open container before the store is removed — `MigrationCoordinator.swift:168`, `QuarantineManager.swift:34`, `PersistenceHost.swift:105`. Undefined behavior on an open SQLite connection (stranded WAL/-shm; possible corruption). The only swap test (`StoreLevelModeSwapSpike`) swaps *without* moving the file, so it never reproduces this ordering. _Fix: remove store / copy-not-move quarantine before touching the file._
- **`sync-1`** Core migration state machine has zero executing coverage under `swift test` (tests runtime-skipped) — `MigrationCoordinatorTests.swift:8,46,57`. A refactor breaking phase ordering / journal clearing / eraser-only-on-replaceICloud would pass green.
- **`sync-3`** No failure-injection anywhere: `.failed` journal path, partial rollback, error propagation never exercised — `CloudKitZoneEraserTests.swift:9`, `MigrationJournalStore.swift:70`, `MigrationCoordinator.swift:216`.
- **`sync-4`** Partial reconfigure failure detaches the only persistent store with no in-process rollback — `PersistenceHost.swift:105,116`, `MigrationCoordinator.swift:194`. After a failed swap, every store operates against a store-less coordinator until relaunch. _Fix: make `flushAndSwap` transactional, re-add the captured original on add-failure._
- **`test-1`** Plan-21 sync-swap & migration tests silently skip under every documented test command — `MigrationCoordinatorTests.swift:8,46`, `StoreLevelModeSwapSpike.swift:50,117,209`, `PersistenceHostTests.swift:40`. The gate converts "cannot run here" into a false "passed". _Fix: app-hosted test target + a meta-test asserting `liveSwapAllowed == true`._
- **`test-2`** `restoreFromBackup` (crash-recovery rollback) has zero test coverage — `MigrationCoordinator.swift:127`. _Fix: seed in-flight journal + quarantined backup, assert contents/mode/cleared-journal; cover missing-backup `storeUnavailable`._
- **`rec-1`** `interval == 0` crashes the monthly expander (÷0) and loop-traps daily/weekly — `RecurrenceExpander.swift:104,131,79`, `RecurrenceRule.swift:30`. The UI clamp at `RecurrenceEditorViewModel.swift:87` is the only guard; CloudKit decode / Importer / CLI all bypass it.
- **`rules-6`** Parity suite is one-example-per-behavior: no negative/empty-set cases, no non-UTC/DST, divergent ops uncovered — `ParityFixtures.swift:67-471`, `ParitySuiteTests.swift:8-114`. Passes today despite four real divergences.
- **`stores-1`** Fractional-ordering compaction is dead code; positions can underflow and collide silently — `FractionalPosition.swift:27`, `PositionCompactor.swift:9`, `TaskStore.swift:268`. Trivially reproducible by a power user dragging one row into the same gap repeatedly.
- **`ext-1`** `TaskEntityQuery` bypasses `MigrationGate` and ignores user `syncMode` — `TaskEntityQuery.swift:35-43`, `IntentSupport.swift:15-23`. Opens the shared store with CloudKit mirroring attached even in LocalOnly, and can race a half-swapped store mid-migration.
- **`macos-2`** Four menu commands with keyboard shortcuts have no observers (dead Indent/Outdent/Find) — `LillistCommands.swift:52-76`, `TaskListView.swift:169-178`. ⌘F does nothing. _(Verifier flagged this as severity-questionable: a UX gap, not a data hazard — treat as P1 polish, not a P0 risk.)_

## Appendix B — Verifier calibration note

The adversarial verifiers were honest about which HIGH claims rest on **code
reading alone** vs. a reproducing test. Because the migration suite doesn't
execute, several high-severity data-loss claims (`persist-3`, `sync-4`, `rec-1`,
`ext-1`, `stores-1`) are *plausible from the code* but their real-world blast
radius is **unverified by any running test** — which is itself the argument for
P0 item #2 (give the state machine executing coverage). Fixing the test gap and
the code defect should land together so the fix is actually verified.
