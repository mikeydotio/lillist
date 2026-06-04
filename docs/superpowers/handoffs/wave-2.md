# Wave 2 handoff (P1, no hard deps)
From: Wave 2 executor   To: Wave 3 executor   Date: 2026-05-30 (backfilled 2026-06-04)

## What landed
- **breadcrumb-truthfulness**: commits `97ed3a8`..`7c2ebcd` (+ a `collectPhases`
  determinism fix); 705 LillistCore tests green ×3. Closed conc-1, stores-2,
  persist-8.
- **fractional-ordering-compaction**: commits `3ecd71d`..`20f4126`; 712 tests
  green. Closed stores-1, stores-3.
- **predicate-parity**: commits `0be04fa`..`2f7dc3e`; 716 tests green ×3. Closed
  rules-1…7 (incl. residual #7 `weeksFromNow` overflow — **resolved**).
- **link-preview-ssrf-guards**: Tasks 1–5, commits `356ed97`..`4bb6154`; 738
  tests green. Closed linkpreview-1/2 + policy/fetcher/CLI halves of
  linkpreview-3. **Task 6 (ShareRootView gate) DEFERRED to Wave 6** (residual #10).

## Shared files I moved (anchor by structure — line numbers as-of-landing)
- `Stores/TaskStore.swift`: the four formerly-`defer { Task { recordCrumb(true) } }`
  mutators (`hardDelete`/`reparent`/`softDelete`/`restore`) now use **inline
  `do/catch` with a true success flag**. This is the canonical shape later plans
  build on — do NOT revert to `defer`.
- `Sync/MigrationCoordinator.swift`: `breadcrumb(_:success:)` is now **async and
  awaited inline** (~lines 80–83; call sites ~165/257/264).
- `Stores/TaskStore.swift` + `Stores/SmartFilterStore.swift`: `reorder` now calls
  `PositionCompactor.recompact` on gap underflow (recompact-in-same-perform) and
  shares an anchor-order guard — gap underflow now throws "anchors out of order".
- `Ordering/FractionalPosition.swift` + `PositionCompactor.swift`: added
  `anchorsAreOutOfOrder`, `needsCompaction`, wired `recompact`.
- Rules evaluators unified (one source of truth for ancestor-depth, diacritic
  equals, recurrence/`hasNudges`, symmetric `isAncestorOf`); parity suite is now
  matrix-driven under UTC + a DST `America/New_York` calendar.
- LinkPreview: added `URLPreviewPolicy` (value type), enforced in
  `URLSessionLinkPreviewFetcher` (+ `RedirectGuard`) and `CLIBridge.LinkHandler`.

## Assumptions I invalidated for later waves
- **`background-context-seam` adds ONLY `context.rollback()` into the existing
  `catch` blocks — it must NOT rewrite the four mutator bodies** (that would
  revert breadcrumb-truthfulness).
- `MigrationCoordinator.breadcrumb` is already `async`/awaited — no later plan
  "prepends await".
- `URLPreviewPolicy` exists and is enforced in fetcher + CLI, but **NOT** in
  `ShareRootView` yet — that's residual #10 (Wave 6).

## Residuals I opened / closed
- Closed: #7 (`weeksFromNow` overflow).
- Carried: #10 (link-preview Task 6 Share-Extension gate → Wave 6).

## Pre-flight the next executor should run
- `git log --oneline main | head -25` — confirm the four Wave-2 plan ranges present.
- Re-Read `TaskStore.swift` (note the inline `do/catch`), `MigrationCoordinator.swift`
  (async breadcrumb), `NotificationSpecStore.swift` before edits.
