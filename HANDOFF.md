# HANDOFF — Data & Sync Hardening, Wave 5b complete → Wave 5c

**Worktree:** `/Volumes/Code/mikeyward/Lillist/.claude/worktrees/data-sync-hardening`
**Branch:** `hardening/data-sync-2026-07`
**State:** Wave 0, all of Wave 1 (`1a`-`1d`), all of Wave 2 (`2a`, `2b`), all
of Wave 3 (`3a`, `3b`), all of Wave 4 (`4a`, `4b`, `4c`), and now all of Wave
5's first two plans, `5a` `mutation-scope-discipline` and `5b`
`widget-snapshot-correctness`, are **COMPLETE**. Wave 5's third and final
plan, `5c` `watermark-registry-pruning` (findings `X12 L7`), is next;
Wave 6 not started.

## What landed this wave (plan `5b`)

Both findings closed (`X5 X6` / stories `LIL-18 LIL-37`). Full details, the
per-finding test/commit table, and both in-place plan-doc corrections are in
the ledger's *Wave 5b closing report*
(`docs/superpowers/plans/2026-07-28-data-sync-hardening-index.md`) and the
plan doc
(`docs/superpowers/plans/2026-07-28-plan-5b-widget-snapshot-correctness.md`).

- **`X5`**: `WidgetSnapshotBuilder.regenerate(filterIDs:)` treated an
  empty/incomplete `smartFilterStore.list()` read as ground truth and
  pruned every snapshot not in it — but a same-device cross-process reader
  (widget extension, Share extension, Shortcuts action) can legitimately
  lag another process's very recent write, and Core Data surfaces no error
  for "not caught up yet." Split into two methods: `regenerate(filterIDs:)`
  is now additive-only (never writes the picker index, never prunes — safe
  from any process, unchanged call syntax everywhere it's already called),
  and a new `regenerateAuthoritatively()` is the sole entry point trusted
  with deletion authority, reserved for the app's own process (the one
  place a read is guaranteed current relative to its own writes).
- **`X6`**: both apps registered only `.NSPersistentStoreRemoteChange`,
  which doesn't fire for the app's own local `viewContext` saves — a task
  completed in-app never refreshed the widget until a remote CloudKit
  change happened to land, which never happens at all in `.localOnly`
  mode. New `WidgetRefreshController` (LillistCore, `@MainActor final
  class`) self-registers both `.NSManagedObjectContextDidSave` on
  `viewContext` (the fix — mirrors `LocalBackupCoordinator`'s proven
  mechanism) and `.NSPersistentStoreRemoteChange` (unchanged), debouncing
  either into one `regenerateAuthoritatively()` + one reload behind a new
  `WidgetTimelineReloading` protocol seam (`LillistCore` still never
  imports WidgetKit). Replaces the per-app `WidgetRefreshCoordinator`
  (byte-identical in both targets) this consolidates; each app now owns
  only a four-line `SystemWidgetTimelineReloader` conformance.

Commit range `a4f1b832..4a7502e4` (9 commits). Full `LillistCore` suite
green **twice in a row** with unmasked exit codes and a clean grep for the
failure markers (1419 tests, 257 suites — up from `5a`'s 1408/254
baseline). LillistUI non-snapshot suite green (83/17, unchanged);
`lillist-cli` builds; both apps verified with unsigned `xcodebuild` builds
(BUILD SUCCEEDED, including `LillistWidget`/`ShareExtension-iOS`/
`ShortcutsActions` on iOS and `LillistWidget-macOS` on macOS).

**Two in-place plan-doc corrections, discovered while implementing (full
reasoning in the plan doc's §4/§6 and the ledger's closing report):**
- `WidgetRefreshController`'s sketch changed from an `actor` to a
  `@MainActor final class` — an actor's `deinit` is nonisolated by default
  and can't touch its own non-`Sendable` `NSObjectProtocol` observer
  tokens without `isolated deinit` (SE-0371), which a `@MainActor` class
  can use identically, matching `LocalBackupCoordinator`'s shape more
  closely.
- The `X5` cross-process test's mechanism changed from simulating genuine
  same-device staleness (withholding `refreshAllObjects()` on a second
  `PersistenceController`) to proving the stronger prune-authority
  invariant directly — three throwaway probes showed this harness's
  same-machine SQLite visibility has no reproducible propagation lag for a
  first-time row-existence fetch, confirmed by replaying an existing `1c`
  harness test with its own `refreshAllObjects()` call removed (still
  passed).

**Discovered-during-verification test flakes — both fixed within this
plan:** the new `WidgetRefreshControllerTests` flaked twice under
`swift test --parallel --num-workers 2`'s full-suite contention (isolated
runs were always green) — first from fixed `Task.sleep` margins (the
documented CPU-contention flake class, a new instance of it), fixed with a
bounded polling helper; then from polling on the wrong signal (the
snapshot file's existence, which can be observed mid-`regenerateAuthoritatively()`
before the reload actually runs), fixed by polling on `reloadCount`
instead. See the ledger's closing report for the full mechanism.

## What `5c` needs to know

`5c` (`watermark-registry-pruning`, findings `X12 L7`) is not on any
shared-file chain `5b` touched — its own scope (`HistoryPruner` ordering,
`WatermarkRegistry`) lives in `Persistence/` alongside but separate from the
widget files. Two things worth knowing anyway:

- `WidgetSnapshotBuilder` now has two public regenerate methods with
  different authority levels — if `5c`'s work ever needs to trigger a
  widget-cache refresh as a side effect, route it through
  `WidgetRefreshController` (the app's own instance), never call
  `regenerateAuthoritatively()` from a new call site directly.
- The `waitUntil`-style bounded-polling pattern
  (`Packages/LillistCore/Tests/LillistCoreTests/Widgets/WidgetRefreshControllerTests.swift`)
  is the one to copy for any new wall-clock-sensitive test `5c` writes,
  rather than a fixed `Task.sleep` margin.

**Discovered, out-of-scope residuals — not fixed, all still open**
(carried forward from the `5a` handoff, unchanged this wave):
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
