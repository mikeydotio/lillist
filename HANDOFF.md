# HANDOFF — Data & Sync Hardening, Wave 4a → Wave 4b

**Worktree:** `/Volumes/Code/mikeyward/Lillist/.claude/worktrees/data-sync-hardening`
**Branch:** `hardening/data-sync-2026-07`
**State:** Wave 0, all of Wave 1 (`1a`-`1d`), all of Wave 2 (`2a`, `2b`), all
of Wave 3 (`3a`, `3b`), and now Wave 4's first plan, `4a`
`history-consumer-discipline` (findings `H6 M3`), are **COMPLETE**. Wave 4's
second plan, `4b` `notification-truthfulness` (findings `H2 X8 X9 X10`), is
next; `4c` and Waves 5-6 not started.

## What landed this wave (plan `4a`)

Both findings closed (`H6`, `M3` / stories `LIL-24`, `LIL-47`). Full details,
the per-finding test/commit table, the watermark-ordering sequence diagram,
and the `transactionAuthor` decision writeup are in the ledger's *Wave 4a
closing report* (`docs/superpowers/plans/2026-07-28-data-sync-hardening-index.md`)
and the plan doc
(`docs/superpowers/plans/2026-07-28-plan-4a-history-consumer-discipline.md`).

- **`H6`**: `RemoteChangeReconciler.processPendingHistory` (now split into a
  `private func drainOnce()` body) advances `tokenStore.lastToken` only
  after `affectedTaskIDs` **and** `onAffectedTasks` have both completed —
  mirrors `LocalBackupCoordinator.processRemoteChange`'s verified-correct
  pattern. The old `try? ... ?? []` swallow became a real `do`/`catch` that
  fails loud (new `public var diagnosticLog: DiagnosticSink?`, same shape as
  `TaskDuplicateReconciler`'s M5 property) and leaves the watermark
  untouched on failure. Also fixed the hardcoded `localAuthor:
  PersistenceController.localTransactionAuthor` comparison to
  `persistence.transactionAuthor` — this specific controller's own stamped
  value, not a global default (decided directly, no council: extension
  writes stay classified as foreign; only "this instance's own writes vs. a
  hardcoded default" changed).
- **`M3`**: `DiagnosticHistoryObserver`'s private nested `DrainGate` actor
  extracted into a public `Persistence/DrainGate.swift` type (pure refactor,
  zero behavior change) and adopted in both `RemoteChangeReconciler`
  (`processPendingHistory()` → acquire/loop wrapper around `drainOnce()`)
  and `TaskDuplicateReconciler` (`reconcileNow()`/`reconcileNow(mirrorIdentifier:)`
  both route through the same gate, wrapping a new private `reconcileOnce`).
  For `RemoteChangeReconciler` this closes a genuine correctness race
  (watermark regression under concurrent notification bursts); for
  `TaskDuplicateReconciler` it's a non-functional thrash-reduction fix only
  (each full scan is individually atomic via `ctx.perform`'s per-context
  serialization — verified by source-level reasoning in the plan doc, not
  assumed).

Commit range `40bd3895..a809d74b` (4 commits: 1 fix H6, 1 refactor DrainGate
extraction, 1 fix M3 adoption, 1 `chore(stories)`). Full `LillistCore` suite
green **twice in a row** with unmasked exit codes and a clean grep for the
failure markers (1324 tests, 233 suites — up from `3b`'s 1314/232 baseline;
one documented-parallel-flake SIGSEGV cleared on retry after the DrainGate
refactor commit). Unsigned `xcodebuild` build for `Lillist-iOS` (BUILD
SUCCEEDED) — the only app-target file touched (`AppEnvironment.swift`'s
one-line `diagnosticLog` wiring). macOS was not touched — it has no
`RemoteChangeReconciler` instance yet.

Both M3 regression tests were verified genuinely red before the fix, not
assumed: `RemoteChangeReconcilerTests`'s concurrent test was run against the
actual pre-M3 source (temporarily reverted via `git checkout HEAD --
<file>`, confirmed 192 = 24×8 duplicate reconciles, then the fix
re-applied); `TaskDuplicateReconcilerTests`'s concurrent test ran directly
against the pre-fix source (confirmed 24 calls → 24 full-table passes, no
coalescing).

## What `4b` needs to know

`4b` continues chain #4 (`RemoteChangeReconciler.swift`) — read the ledger's
*Shared-file serial chains* section before touching the file; line numbers
have moved since `4a`.

- `processPendingHistory()`'s body is now `private func drainOnce()`. `4b`'s
  widened diffing (spec inserts/deletes, task soft-deletes per `X9`) belongs
  **inside** `drainOnce()`, not as a parallel code path — it only inherits
  the watermark-after-success ordering and the `DrainGate` serialization if
  it stays inside that function.
- `affectedTaskIDs`'s `localAuthor` parameter is now called with
  `persistence.transactionAuthor` at the one production callsite. Any new
  callsite must do the same — never reintroduce the hardcoded
  `PersistenceController.localTransactionAuthor` default.
- `RemoteChangeReconciler` has a `public var diagnosticLog: DiagnosticSink?`,
  wired in iOS `AppEnvironment.swift` only. Per `X8`/`X9`, `4b` is expected
  to give macOS its first `RemoteChangeReconciler` instance — wire the same
  property there too, mirroring the iOS wiring right after `diagnosticLog`'s
  own construction (see iOS `AppEnvironment.swift` for the exact spot).
- `Persistence/DrainGate.swift` is the shared serialization primitive for
  *any* `NSPersistentStoreRemoteChange` consumer — one instance per consumer
  instance, never shared across unrelated consumers. A macOS
  `RemoteChangeReconciler` `4b` constructs needs its own.
- `TaskDuplicateReconciler.reconcileNow()`/`reconcileNow(mirrorIdentifier:)`
  both route through the same `DrainGate` now. Don't add a new entry point
  that bypasses it.

**Discovered, out-of-scope residual — not fixed**:
`TaskDuplicateReconciler.diagnosticLog` (added by `1a`'s M5 fix) is never
wired in either `AppEnvironment.swift` — flagged for the `6a` completeness
sweep. `recoverInterruptedReseed()`'s crash-recovery path still never
broadcasts (flagged in `3b`); `LIL-81`/`LIL-77` (flagged in `3a`/`1d`) are
also still open.

## Standing worktree rules (unchanged)

No merge, no `/semver bump`, no `/deployit deploy` from this worktree.
One PR opens at the very end of Wave 6 — this session stops after
opening it, per policy.
