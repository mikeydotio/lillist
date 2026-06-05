# Wave 6 handoff (P2/P3 + blind-spots)
From: Wave 6 executor   To: Wave 7 executor   Date: 2026-06-05

## What landed (35 commits, `d38134d`..`2723769`; all on `main`)

(33 plan commits + 2 post-review hardening commits — see *Adversarial review* below.)

- **extension-persistence-unification** (`d38134d`..`5dcaab1`, 8 commits): closed ext-1…6 +
  residual #10. `SmartFilterStore.evaluate(group:)` gained a limit (later reshaped by the perf
  plan — see below); `IntentSupport.makePersistence()` now wraps `GatedPersistenceResolver` in a
  per-process `PersistenceController` cache (private `actor Cache` keyed on
  `StoreConfiguration.syncMode`); `TaskEntityQuery` routes both `entities`/`suggestedEntities`
  through the gated factory (`limit: 20`, no in-memory prefix); `ShareSaveFlow` pure helper +
  `ShareRootView.save()` now gates the URL through `URLPreviewPolicy.isAllowed` **before**
  `addLinkPreview` (closes the deferred SSRF gate, residual #10), stops `try?`-swallowing the
  attachment error, and reuses `savedTaskID` on retry (no duplicate task); dead
  `OpenTaskInAppIntent`/`OpenAtQuickCaptureIntent` collapsed to `openAppWhenRun`.
  **Plus a fix (`5dcaab1`):** `IntentSupportGateTests` no longer calls the real
  `IntentSupport.makePersistence()` — that stood up a live `NSPersistentCloudKitContainer` whose
  async CloudKit mirroring setup **traps (EXC_BREAKPOINT in `-[PFCloudKitContainerProvider
  containerWithIdentifier:options:]`)** in the headless, un-entitled `Lillist-iOSTests` bundle.
  This was a latent ~25% flake (residual #11); the new per-process cache held the container alive
  across suites and made it **100% deterministic** (TEST FAILED despite 0 assertion failures). The
  test now exercises `resolver.resolveStoreConfiguration()` (a pure value, no container) — the
  bundle went from flaky to **5/5 clean**. Production is unaffected (only ever one container per
  extension process). See *Assumptions invalidated* and residual #11 below.
- **export-import-robustness** (`dca50bc`..`e2cdd34`, 5 commits): closed import-1/2/3, export-1.
  `LillistError.unsupportedExportVersion`; `Importer.apply` guards `document.version` (reject
  newer, accept equal/older) and documents the all-or-nothing single-`save()` contract;
  `JournalEntryDTO`/`AttachmentDTO.taskID` widened `UUID`→`UUID?`; `Exporter` emits `m.task?.id`
  (3 sites, no fabricated UUID); `Importer` skips orphan journal entries (nil/unresolved taskID)
  into `errors` + `journalEntriesSkipped`; `applyEntry` rewritten to take a resolved
  `owner: LillistTask`. **Note:** Task 3 (`3974267`) committed a transient non-compiling Importer
  by design (the DTO widening + the `applyEntry` rewrite are atomically coupled); Task 4
  (`a3e4852`) restored the clean build in the immediately-following commit. (If you `git bisect`
  across Wave 6, `3974267` is the one commit that doesn't build standalone.)
- **cli-robustness** (`ee19b13`..`f4aa02f`, 7 commits): closed cli-2…6. `Resolver.resolveAll`
  (all-or-nothing batch pre-resolution); `BatchTokens` helper de-duplicating the stdin-parse block
  across the 5 destructive commands (Delete/Purge/Move/Status/Restore now pre-resolve before
  mutating); `RestoreHandler.preflight`; deleted dead `resolveExactTitle`/`--exact` and fixed the
  destructive-ambiguity error copy; byte-exact json/ndjson/tsv golden fixtures (regenerated from
  the real renderers); `WatchHandler` rewritten to a serialized `Coalescer` actor + `SnapshotBox`
  actor + `snapshotStep` dedup + `onError` stderr surfacing. **`StoreLocator` was deliberately
  NOT routed through `GatedPersistenceResolver`** (unscoped follow-up, owned by no plan) and
  `PurgeCommand` was NOT "modernized" to batch `purgeAll` (per-resolution `hardDelete` is the
  all-or-nothing CLI path).
- **performance-budgets-and-paging** (`ae18af5`..`8782757`, 6 commits): closed the §761 budget +
  unbounded-fetch findings. First `XCTestCase` files in LillistCore, isolated under
  `Tests/LillistCoreTests/Performance/` (`PerfBudget`, `PerfFixture`, `SmartFilterPerformanceTests`,
  `TaskListFetchPerformanceTests`). `XCTAssertWithinBudget` is the **real** gate (median wall-clock
  hard-assert — `measure()` never fails under `swift test`). `TaskStore.children(of:)` routes
  through a shared `childrenFetchRequest(parentID:in:)` builder with `fetchBatchSize = 100`, plus
  an additive `children(of:limit:offset:)` overload; `fetchBatchSize` added to `evaluate(id:)`,
  `evaluate(group:)`, `pinned()`, `tasks(forTag:)`.
- **observability-logging** (`eef2944`..`32373e4`, 7 commits): closed logs-2 + observability
  blind-spot. `LillistLog` taxonomy (os.Logger categories + shared `OSSignposter`) **pinned to
  `CrashReporting.subsystemIdentifier`** so `OSLogFetcher` finally collects real lines (the crash
  reporter's "Recent app logs" is now honest); `OSLogFetcherRoundTripTests` proves it end-to-end;
  2 macOS `NSLog`→`LillistLog`; additive signpost+log weave into `MigrationCoordinator.runMigration`
  + `restoreFromBackup`; signpost+row-count on `TaskStore.children(of:)`; iOS `MetricKitObserver`
  retained by `AppEnvironment` and registered in `bootstrap()`.

## Shared files I moved (anchor by STRUCTURE — line numbers are as-of-landing)

- **`Stores/TaskStore.swift`** — `children(of:)` (~211) now: signpost interval (observability) wrapping
  a `try await context.perform { let req = try childrenFetchRequest(...); ... }` whose body delegates
  to a new private `childrenFetchRequest(parentID:in:)` builder (perf, `fetchBatchSize=100`), then logs
  `children fetch rows=`. New `children(of:limit:offset:)` overload + `static let listFetchBatchSize = 100`
  (right after `public var breadcrumbs`). `import os` added. The Wave-4 mutator/`purgeAll`/rollback code
  is untouched.
- **`Stores/SmartFilterStore.swift`** — `evaluate(group:)` final signature is
  `(group:sort:ascending:now:calendar:includeArchived:limit:Int=0,offset:Int=0)` with `fetchBatchSize`
  + `fetchLimit/fetchOffset`. **This reshaped the `limit: Int? = nil` the extension plan briefly added;
  all callers pass `limit: 20` (a plain Int) so it's source-compatible, and `0`/non-positive = unbounded
  (parity with the old `nil`).** `evaluate(id:)` got `fetchBatchSize`.
- **`Sync/MigrationCoordinator.swift`** — `import os` added; `runMigration` opens its timed body with
  a signpost `beginInterval`/`defer endInterval` + start `notice` **placed AFTER the two Wave-4
  reentrancy guards and the `isMigrating` defer**, then phase notices (reconfigure/erase/complete/fail);
  `restoreFromBackup` got 3 notices. Additive only — Wave-4 guards, phase order, journal sequence, and
  emitted `MigrationPhase` events are byte-unchanged.
- **`Extensions/ShortcutsActions/IntentSupport.swift`** — now a per-process `actor Cache` over the
  resolver. **`TaskEntityQuery.swift`** deleted its divergent factory. **`Extensions/ShareExtension-iOS/`**
  gained `ShareSaveFlow.swift`; `ShareRootView.save()` rewired.
- **iOS `Apps/Lillist-iOS/project.yml` + pbxproj** — `Lillist-iOSTests` co-compiles
  `SharePayload.swift` + **`ShareSaveFlow.swift`** + `ReportCrashIntent.swift` + `IntentSupport.swift`;
  the app target gained `Sources/App/MetricKitObserver.swift`. The 3 Wave-4 `Lillist-iOSAppHostedTests`
  entries survived every regenerate (verified by grep each time).
- **`Export/Importer.swift` + `Export/Exporter.swift` + `Export/ExportSchema.swift`**, the **5 CLI
  destructive command files** + `Resolver.swift` + `WatchHandler.swift` + `RestoreHandler.swift`,
  the **2 macOS** `IndexingService.swift`/`LillistServicesProvider.swift`, and the iOS
  `AppEnvironment.swift` — all as described above.
- **`docs/engineering-notes.md`** — TWO new EOF entries (35th: perf budgets/paging policy; 36th:
  observability subsystem-pinning contract). The true EOF is now the observability entry — re-Read
  before any further append.

## Assumptions I invalidated for later waves

- **`evaluate(group:)`'s `limit` is now a non-optional `Int = 0` (+ `offset: Int = 0`)**, not
  `Int? = nil`. `0`/negative ⇒ unbounded. Don't reintroduce the optional form.
- **`TaskStore.children(of:)` is now signpost-bracketed and routes through `childrenFetchRequest`.**
  Re-anchor on the builder, not the old inline fetch. There is a new `children(of:limit:offset:)` overload.
- **`LillistLog.subsystem` MUST stay `== CrashReporting.subsystemIdentifier`** — splitting it silently
  re-empties the crash report's logs section (no compile error, no test failure unless the OSLogFetcher
  round-trip runs with log access). `LillistLogTests.subsystemMatchesCrashReporter` is the always-on guard.
- **A headless XCTest bundle must NOT stand up a live `NSPersistentCloudKitContainer`** — the async
  CloudKit mirroring setup traps without iCloud entitlement/account. `IntentSupportGateTests` no longer
  does; do not reintroduce a live-`makePersistence()` call in a standalone bundle.

## Residuals I opened / closed

- **Closed:** ext-1…6, residual #10 (SSRF Share gate), import-1/2/3, export-1, cli-2…6, the §761
  perf budget, the unbounded-fetch finding, logs-2 + the observability blind-spot.
- **Residual #11 (the parallel-test SIGSEGV / timing flakes) — materially improved on iOS, still
  Wave-7's to own on `swift test`.** The iOS-bundle manifestation (the CloudKit-container crash) is
  **eliminated** (`5dcaab1`): the bundle was flaky-to-deterministic-crash and is now 5/5 clean. The
  `swift test` manifestations remain: `SyncQuiesceMonitorTests` quiet-window and
  `TaskStoreRecurrenceSpawnTests` 2s-tolerance flakes still trip ~1/run under parallel CPU load (pass
  in isolation). **`ci-and-build-posture` (Wave 7) still owns bounding `swift test` parallelism /
  adding a flake-retry for those two.** Re-run the full suite before treating either as a real failure.
- **No new residuals opened.**

## Adversarial review (3 dimensions + skeptical per-finding verification)

A 5-agent workflow reviewed all 33 plan commits across three dimensions
(cross-plan composition/regression, spec adherence, correctness/concurrency/
security), then adversarially verified each raw finding against the actual code.
**Result: no prior-wave regression, clean cross-plan composition, every finding
closed as specified — and 2 confirmed findings (both medium, both in code I
authored), which I fixed and re-verified:**

1. **Privacy (`2050142`)** — the two macOS `LillistLog` sites logged the full
   `error.localizedDescription` with `privacy: .public`, violating `LillistLog`'s
   own contract (`.public` only for counts / mode names / error *type* names). A
   Core Data save error's `localizedDescription` can carry attribute values / the
   store path into the crash-collected subsystem (the redactor has no generic-URL
   pass and its key=value pass is single-token). Switched both to
   `String(describing: type(of: error))`, matching every other Wave-6 log site.
2. **Cache double-build race (`2723769`)** — `IntentSupport.Cache.controller(for:)`
   checked the cache, then `await`ed `PersistenceController` init (which suspends),
   then wrote the cache; the actor releases isolation across that await, so two
   concurrent cold callers could both build a container, orphaning one with its
   CloudKit subscription and defeating the cache's single-container invariant. Now
   coalesced via an in-flight `Task` keyed on `syncMode` (registered before the
   first await; mode-guarded clear handles the rare mode-flip-mid-build window).

The review **rejected 0 findings as false positives** (both raw findings were
real). No other issues surfaced. Post-fix: macOS + iOS builds clean, iOS bundle
TEST SUCCEEDED.

## Pre-flight the next executor (Wave 7) should run

- `git log --oneline 643da7a..HEAD | head -35` — confirm the 35 Wave-6 commits are present.
- `swift test --package-path Packages/LillistCore` — expect 858 green except the 2 named residual-#11
  flakes (re-run once; they pass in isolation). The perf suites add a little time (10k seeding).
- `xcodebuild test -scheme Lillist-iOS -only-testing:Lillist-iOSTests` — expect **TEST SUCCEEDED, no
  restart** (the CloudKit-container crash is fixed). macOS + iOS unsigned app builds: `BUILD SUCCEEDED`.
- Re-Read before edits: `MigrationCoordinator.runMigration` (signposts now woven after the Wave-4
  guards — recovery-hardening must still not add a 3rd guard), `TaskStore.children(of:)` (signpost +
  paging — do not re-introduce an unbounded fetch), `docs/engineering-notes.md` true EOF (the
  observability entry).
- Wave 7 plans, in order: `privacy-manifest-export-compliance` (last `project.yml` editor — owns the
  final coordinated `xcodegen generate`), `recovery-hardening`, `lillistui-localization-a11y`, then
  `ci-and-build-posture` **dead last**.
