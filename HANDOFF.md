# HANDOFF — Diagnostic Logging implementation (+ pending reorder bug fix)

**Date:** 2026-06-06 · **Branch:** `feat/diagnostic-logging` (off `main`)

## Start here (primary task: execute the plan)

Open a fresh session on this branch and use the **superpowers:executing-plans** skill to
execute, task-by-task with checkpoints:

> Execute `docs/plans/2026-06-06-diagnostic-logging.md` using superpowers:executing-plans.
> Read the "Pre-flight" section first; follow the TDD steps in order; commit per task.

- **Approved design:** `docs/plans/2026-06-06-diagnostic-logging-design.md`
- **Implementation plan (20 tasks / 8 phases):** `docs/plans/2026-06-06-diagnostic-logging.md`

## What the feature is
On-by-default (off-at-ship via `#if DEBUG`) file-based diagnostic logging for macOS + iOS:
per-process JSONL in `App-Group/Lillist/Diagnostics/diag-<day>-<process>.jsonl`, 30-day
rolling; data events from a persistent-history observer (attributed by `transactionAuthor`),
plus explicit reorder/create/reparent/drag emits; a "Prepare diagnostic package" Settings flow
(include-toggles → consistent `VACUUM INTO` SQLite snapshot + merged logs + manifest → zip →
`.fileExporter`). Full-content logging; logs never auto-transmit.

## Must-not-forget prerequisites (recon-verified; details in the plan's Pre-flight)
1. **Per-process `transactionAuthor` is net-new.** Today all processes write `"Lillist.app"`
   (`PersistenceController.swift:33`). Attribution depends on Phase 2 threading a per-process
   author (keep the app's default classified "local" in `RemoteChangeReconciler.affectedTaskIDs`).
2. **Own history watermark.** `DiagnosticHistoryObserver` must use a distinct
   `PersistentHistoryTokenStore` key, not the reconciler's. macOS has NO reconciler — observer
   wiring is net-new on both platforms.
3. **Toggle actor → cached bool.** `DevicePreferencesStore` is an actor; `DiagnosticLog` holds a
   cached `enabled` flag (no `await` per event); Settings hydrates `@State` in `.task`.
4. **Snapshot via `VACUUM INTO`** (`import SQLite3`, read-only) — the live store can't be closed.
5. **Zip via `NSFileCoordinator(.forUploading)`** — no SPM zip dependency.
6. After new **app-target** files: regenerate **both** pbxprojs (CI drift gate); 3
   `Localizable.xcstrings` stay aligned + `Tools/CI/check-lillistui-localization.sh`.

## Test commands
- `swift test --package-path Packages/LillistCore --parallel --num-workers 2` (re-run once on a
  one-off SIGSEGV/timing flake).
- `swift test --package-path Packages/LillistUI --skip Snapshot --skip Tour`.
- `xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'`
  (snapshot/app-hosted/live-attribution tests are signed-Mac-only; not CI).
- Regen: `(cd Apps/Lillist-iOS && xcodegen generate --spec project.yml --project .)` then `(cd Apps && xcodegen generate --spec project.yml --project .)`.

## Second, independent thread: the reorder bug FIX (not yet done)
The "anchors out of order" bug is **root-caused but unfixed**. The logging feature only
*instruments* it. Investigation artifacts (untracked, on disk): `.rca/reorder-anchors-out-of-order/`
(`VERIFICATION.md` has the verified root cause + remediation direction).
- **Root cause:** non-atomic `nextPosition = max+1` raced across the separate-process
  Share/App-Intents extensions (+ CloudKit imports) mints equal-position bottom rows; the reorder
  guard rejects them before the self-heal runs; surfaced as "Could not load tasks."
- **Remediation (design when picked up):** (1) collision-tolerant/coordinated position allocation;
  (2) self-healing reorder — recompact-then-re-check when *data* is degenerate, still rejecting a
  genuinely inverted *request* (respace in presentation order); (3) load-time normalization;
  (4) R2 — give reorder failures a transient surface, not the full-screen load error.
- Decide whether to commit/keep/delete `.rca/` (RCA skill Phase 5) when this thread resumes.

## Conventions
Solo repo; conventional commits; small focused commits; rebase-and-merge to `main` (no PR review);
HTTPS push override; never force-push. Treat warnings as errors; strict concurrency on LillistCore
source; read files before editing.
