# HANDOFF — Data & Sync Hardening, Wave 4 complete → Wave 5a

**Worktree:** `/Volumes/Code/mikeyward/Lillist/.claude/worktrees/data-sync-hardening`
**Branch:** `hardening/data-sync-2026-07`
**State:** Wave 0, all of Wave 1 (`1a`-`1d`), all of Wave 2 (`2a`, `2b`), all
of Wave 3 (`3a`, `3b`), and now **all of Wave 4** (`4a`
`history-consumer-discipline`, `4b` `notification-truthfulness`, `4c`
`recurrence-correctness`) are **COMPLETE**. Wave 5's first plan, `5a`
`mutation-scope-discipline` (findings `H5 M4 M6 M7 L3 L4 L5 X19 X20`), is
next; `5b`/`5c`/Wave 6 not started.

## What landed this wave (plan `4c`)

All four findings closed (`H1`, `X7`, `X16`, `X17` / stories `LIL-19`,
`LIL-38`, `LIL-65`, `LIL-66`). Full details, the per-finding test/commit
table, the H1 placement-decision reasoning, and the X7 end-to-end merge
proof are in the ledger's *Wave 4c closing report*
(`docs/superpowers/plans/2026-07-28-data-sync-hardening-index.md`) and the
plan doc
(`docs/superpowers/plans/2026-07-28-plan-4c-recurrence-correctness.md`).

- **`H1`**: `RecurrenceSpawner` anchored every spawn at
  `series.seedTask.position + 0.5` — `seedTask` never changes across a
  series' lifetime, so every spawn after the first collided at the
  identical position. New `Ordering/SiblingPositioning.swift` extracts the
  live sibling-position fetch `TaskStore.create` already used;
  `RecurrenceSpawner` now delegates to it (bottom placement — decided
  directly, no council; reuses tested machinery and never silently
  reshuffles a manually curated list). `TaskStore.nextPositionDetail`
  becomes a thin wrapper over the same core.
- **`X7`**: recurrence spawns had no idempotency key — a concurrent
  widget/app or two-device race could double-spawn the same occurrence
  under distinct random UUIDs that `TaskDuplicateReconciler` couldn't
  collapse. New `DeterministicUUID.v5` (RFC 4122 name-based UUID) derives
  `spawn.id = v5(namespace: series.id, name: <occurrence date>)` and
  deep-copied children get `v5(namespace: <parent copy's id>, name:
  <source child's stable id>)` — the whole spawned subtree is now
  deterministic to arbitrary depth. Proven end-to-end that `1a`'s existing
  `TaskDuplicateReconciler` actually merges the resulting same-id
  duplicate rows.
- **`X16`**: `AfterCompletionRule.interval` had no clamp, unlike its
  `CalendarRule` sibling — a 0/negative interval spawned a
  permanently-overdue task on every close. Mirrors `CalendarRule`'s exact
  shape (init + decode-boundary normalization into `1 second...10 years`)
  plus point-of-use defense-in-depth. Two pre-existing tests that
  documented the bug as intended behavior were rewritten in the same
  commit.
- **`X17`**: weekly `byDay` expansion hardcoded a Sunday week boundary,
  ignoring `calendar.firstWeekday` — a biweekly Saturday/Sunday rule under
  a Monday-first calendar fired one week early. Re-based the arithmetic
  onto "days since `calendar.firstWeekday`"; added locale-parameterized
  tests across Sunday-first, Monday-first, and Saturday-first calendars.

Commit range `47953dee..3b377f58` (6 commits: 1 docs (plan), 1
`chore(stories)` in-progress, 4 fix/feat, 1 `chore(stories)` done). Full
`LillistCore` suite green **twice** with unmasked exit codes and a clean
grep for the failure markers (1376 tests, 241 suites — up from `4b`'s
1354/237 baseline); one signal-11 (SIGSEGV) worker-crash flake hit between
the two clean runs, matching the documented `CLAUDE.md` parallel-test-flake
class exactly, cleared on immediate retry. **Pure `LillistCore` change — no
app-target files touched**, so no `xcodebuild` builds were needed this wave.

## What `5a` needs to know

`5a` (`mutation-scope-discipline`, findings `H5 M4 M6 M7 L3 L4 L5 X19 X20`)
is the **fourth and final plan in the `TaskStore.swift` serial chain**
(`1a` → `1b` → `4b` → `5a` — see the ledger's *Shared-file serial chains*
section). Re-Read `TaskStore.swift` fully before touching it; `4c` added:

- `TaskStore.nextPositionDetail(forParent:placement:)` is now a one-line
  wrapper delegating to `Ordering/SiblingPositioning
  .nextPositionDetail(forParent:placement:in:)` — the actual fetch +
  `FractionalPosition` logic moved there so `RecurrenceSpawner` (no
  `TaskStore` instance available) can share it. Any `withMutationRollback`
  helper wrapped around `TaskStore.create`/`reorder` needs to account for
  this one extra layer of indirection; the `throws` contract is unchanged.
- `RecurrenceSpawner.spawnIfNeeded(forClosedTask:in:)` is now `throws`
  (previously non-throwing). Its one call site, `TaskStore.transition`'s
  `newStatus == .closed` branch, already runs inside a throwing
  `context.perform` block with the existing rollback-on-catch structure —
  composed cleanly. If `5a`'s mutation-rollback helper wraps `transition`,
  make sure `spawnIfNeeded`'s throw still propagates to that same rollback
  path rather than getting swallowed.
- New file `Recurrence/DeterministicUUID.swift` (RFC 4122 v5 UUID,
  `CryptoKit.Insecure.SHA1`) — not part of `5a`'s scope, but reusable if
  any future mutation needs a deterministic/idempotent id for the same
  cross-process race shape `X7` closed.
- `RecurrenceSpawner.deepCopy` now assigns child ids via
  `DeterministicUUID.v5(...)` instead of a bare `UUID()` — don't assume
  every `LillistTask` copy site still mints a purely random id if `5a`
  touches cascade/subtree-copy logic (it shouldn't need to, per its
  finding list).

**Discovered, out-of-scope residuals — not fixed, all still open** (carried
forward unchanged from the `4b` handoff):
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

## Standing worktree rules (unchanged)

No merge, no `/semver bump`, no `/deployit deploy` from this worktree.
One PR opens at the very end of Wave 6 — this session stops after
opening it, per policy.
