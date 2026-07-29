# HANDOFF — Data & Sync Hardening, Wave 5a complete → Wave 5b

**Worktree:** `/Volumes/Code/mikeyward/Lillist/.claude/worktrees/data-sync-hardening`
**Branch:** `hardening/data-sync-2026-07`
**State:** Wave 0, all of Wave 1 (`1a`-`1d`), all of Wave 2 (`2a`, `2b`), all
of Wave 3 (`3a`, `3b`), all of Wave 4 (`4a`, `4b`, `4c`), and now **Wave 5's
first plan, `5a` `mutation-scope-discipline`**, are **COMPLETE**. Wave 5's
second plan, `5b` `widget-snapshot-correctness` (findings `X5 X6`), is next;
`5c`/Wave 6 not started.

## What landed this wave (plan `5a`)

All nine findings closed (`H5 M4 M6 M7 L3 L4 L5 X19 X20` / stories `LIL-23
LIL-48 LIL-50 LIL-51 LIL-68 LIL-69 LIL-72 LIL-73 LIL-74`). Full details, the
per-finding test/commit table, the class-kill demonstration, and both
in-place plan-doc corrections are in the ledger's *Wave 5a closing report*
(`docs/superpowers/plans/2026-07-28-data-sync-hardening-index.md`) and the
plan doc
(`docs/superpowers/plans/2026-07-28-plan-5a-mutation-scope-discipline.md`).

- **`H5`**: new shared `withMutationRollback` helper
  (`Persistence/MutationRollback.swift`) generalizes `TaskStore`'s
  mutate-then-save-or-rollback pattern; adopted across every public
  mutating method of all eight `LillistCore` stores plus
  `TaskDuplicateReconciler.reconcileDuplicates`. Five stores
  (`Tag`/`SmartFilter`/`Journal`/`Attachment`/`Series`) had zero rollback
  discipline before this. `TaskStore.create`'s own wart (validation outside
  `context.perform`, unconditional rollback in catch) is fixed structurally
  by moving validation inside the helper's atomic body. **Class-killer:**
  `MutationRollbackConformanceTests` — a source-text scan (no runtime
  `Mirror` enumeration exists for plain Swift classes) proving zero raw
  `context.save()`/`.rollback()` calls outside the helper, plus a
  whole-tree walker catching any undocumented future bypass; demonstrated
  locally (bypassed the helper in one method, watched the walker fail
  pinpointing the exact line, reverted).
- **`M4`**: `PreferencesStore.read()` no longer creates the singleton row
  as a side effect — genuinely read-only now, falling back to in-memory
  defaults on an empty store. Creation moved to `normalizeSingletons()`
  (now handling the empty-store case) and `update(_:)`'s own
  `ensureSingleton`. **Found while implementing:** macOS's `bootstrap()`
  had no `normalizeSingletons()` call at all (only iOS did) — fixed by
  adding it in the same relative position iOS already had.
- **`X20`**: `normalizeSingletons`'s tie-break no longer sorts by raw `id`
  bytes — canonical-id-first, then a content-key built from every settings
  field. **Found while implementing:** the plan doc's original
  `createdAt`-based design assumed a field that doesn't exist on
  `AppPreferences` — adding one is a real CloudKit schema change out of
  scope (same constraint `4b` hit for `LIL-83`); the content-key design
  needs no schema change.
- **`M6`**: `TaskStore.reorder`'s both-anchors parent-mismatch guard now
  also covers the single-anchor `.explicit(parent)` case.
- **`M7`**: `AttachmentStore.delete` now also deletes its auto-created
  `JournalEntry` (`Nullify` relationship) instead of orphaning it.
- **`L3`**: `TaskStore.syncCounts()` moved off the main-queue `viewContext`
  onto a background context.
- **`L4`**: `unassignTag` now mirrors `assignTag`'s no-op guard.
- **`L5`**: `archive`/`unarchive` return a new `TaskStore.BatchIDOutcome
  {flipped, skipped}` instead of failing the whole batch on one missing id;
  both app call sites (iOS `TasksView`, macOS `MacTasksView`) updated.
- **`X19`**: `NotificationSpecStore.add`'s dedup branch dropped its
  redundant manual `if hasChanges { save() }`;
  `TaskDuplicateReconciler.reconcileDuplicates` gained rollback-on-failure
  it never had (a second, previously-unnamed `H5` instance).

Commit range `84dd7a39..6b84143f` (20 commits). Full `LillistCore` suite
green **twice in a row** with unmasked exit codes and a clean grep for the
failure markers (1406 tests, 253 suites — up from `4c`'s 1376/241 baseline),
**explicitly `--skip`ping one pre-existing, unrelated failing test** (see
below) — no other exclusions. LillistUI non-snapshot suite green (83/17,
unchanged); `lillist-cli` builds; both apps verified with unsigned
`xcodebuild` builds after the one app-touching commit (`L5`'s call-site
updates) and after the `M4`/`X20` commit (macOS `AppEnvironment.swift`
wiring).

**Discovered, out-of-scope defect — filed as `LIL-86`, not fixed:**
`X10TimezoneDedupKnownLimitationTests.differingTimeZoneDevicesBothFire` (a
`4b`-owned test) fails deterministically as of this writing — confirmed via
a temporary `git worktree` at `6cc5fa4c` (tip of `4c`, before any `5a` work)
that it fails identically there too, proving it predates `5a` entirely.
Suspected cause: the test computes fire dates from the live `Date()` at run
time rather than an injected fixed `now`, making it wall-clock-time
dependent. Filed for `6a`'s completeness sweep.

## What `5b` needs to know

`5b` (`widget-snapshot-correctness`, findings `X5 X6`) is **not** on the
`TaskStore.swift` serial chain — that chain closed permanently with `5a`
(four plans: `1a` → `1b` → `4b` → `5a`, no more scheduled touches). Still
relevant:

- Any new `LillistCore` store or maintenance-path mutation must route
  through `withMutationRollback` (`Persistence/MutationRollback.swift`) —
  `MutationRollbackConformanceTests`'s whole-tree walker fails the build
  immediately on a raw `context.save()`/`.rollback()` call anywhere under
  `Stores/`, `Notifications/`, or
  `Persistence/TaskDuplicateReconciler.swift` not already in its
  `migratedFiles` list.
- `TaskStore.archive`/`unarchive` now return `TaskStore.BatchIDOutcome
  {flipped, skipped}`, not `[UUID]`/`Void`.
- `PreferencesStore.read()` is genuinely read-only now — don't add a call
  site expecting it to create the singleton row.
- `TaskStore.syncCounts()` opens its own `persistence
  .makeBackgroundContext()` rather than using the injected `context`
  property — the pattern to copy for any widget-snapshot aggregate that
  needs the same off-`viewContext` treatment.

**Discovered, out-of-scope residuals — not fixed, all still open** (carried
forward from the `4c` handoff, plus one new item this wave):
- `TaskDuplicateReconciler.diagnosticLog` unwired in both apps (`1a`'s M5,
  flagged in `4a`) — `6a` completeness sweep.
- `recoverInterruptedReseed()`'s crash-recovery path never broadcasts
  (`3b`); `LIL-81` (`3a`); `LIL-77` (`1d`) — all still open.
- A remote `NotificationSpec.snoozedUntil`/`.offsetMinutes` in-place edit is
  still invisible to `RemoteChangeReconciler`'s diff (X9's scope note) —
  latent, not reachable today; flagged for whichever future plan touches
  `NotificationSpecStore.update`'s callers.
- `LIL-83` (X10's timezone-posture schema change) — **explicitly deferred
  out of this program** (orchestrator decision, 2026-07-29). Not
  program-scheduled work; don't pick it up in `6a`.
- `LIL-86` (this wave's discovery, above) — `6a` completeness sweep.

## Standing worktree rules (unchanged)

No merge, no `/semver bump`, no `/deployit deploy` from this worktree.
One PR opens at the very end of Wave 6 — this session stops after
opening it, per policy.
