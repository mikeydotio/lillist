# HANDOFF — Diagnostic Logging (DONE) + pending reorder fix

**Date:** 2026-06-06 · **Branch:** `feat/diagnostic-logging` (off `main`)

## Diagnostic logging plan: COMPLETE ✅

All 20 tasks / 8 phases of `docs/plans/2026-06-06-diagnostic-logging.md` are
implemented, tested, and committed, followed by an adversarial review pass whose
15 confirmed-real findings were fixed. What shipped (all in `LillistCore/Diagnostics/`
+ app Settings surfaces):

- `DiagnosticEvent`/`DiagValue` JSONL model → `DiagnosticLog` actor (rolling
  30-day per-process files; stamps the authoritative process + per-file seq).
- Per-process Core Data `transactionAuthor` (app/macApp/shareExtension/appIntents/cli,
  all now wired) → `DiagnosticHistoryObserver` (own watermark key; attributes every
  writer; **reentrancy-safe** via a `DrainGate`). The reorder-tie the RCA flagged is
  captured as equal `position` with **distinct authors**.
- Explicit emits: `task.create/reorder/reparent` (incl. the throwing "anchors out of
  order" path), `filter.reorder`, `drag.start/over/drop`.
- `DiagnosticPackageBuilder`: merge logs (line-by-line resilient) + `VACUUM INTO`
  store snapshot + `NSFileCoordinator` zip; store-snapshot failure degrades to
  logs-only with a manifest note.
- iOS Settings `DiagnosticsSection` + macOS `DiagnosticsPane` + LillistUI
  `DiagnosticsIncludeSheet` presenter + `.fileExporter`; full AppEnvironment +
  extension wiring.

**Verified locally:** `swift test` LillistCore (868) + LillistUI (non-snapshot) green;
iOS + macOS schemes build unsigned; tour snapshot `test_11` recorded + passes;
LillistUI loc lint OK; pbxproj drift gate clean. **Pending on your signed Mac**
(per the repo's CI scope, not blockers): the full host-pinned snapshot suite and the
`Lillist-iOSAppHostedTests` live-swap / UI tests (need iCloud) — run the
`xcodebuild test -scheme Lillist-iOS` recipe to confirm.

**Deferred follow-ups (non-blocking):**
- Delete events resolve a nil `objectUUID` until `LillistTask.id` is flagged
  `preserveValueInHistoryOnDeletion` (a CloudKit-store model change). Documented in
  `DiagnosticHistoryObserver.flatten`. Not RCA-critical (the tie is a create-time signal).
- The review left **13 low + 3 nit** polish items unaddressed (style/minor robustness);
  available on request — they were not adversarially confirmed, only the 15 medium/high were.

Engineering gotchas captured in `docs/engineering-notes.md` (2026-06-06 entry).

## Remaining work: the reorder bug FIX (second, independent thread)

The "anchors out of order" bug is **root-caused but unfixed** — diagnostic logging only
*instruments* it. Investigation artifacts (untracked, on disk):
`.rca/reorder-anchors-out-of-order/` (`VERIFICATION.md` has the verified root cause).
- **Root cause:** non-atomic `nextPosition = max+1` raced across the separate-process
  Share/App-Intents extensions (+ CloudKit imports) mints equal-position bottom rows;
  the reorder guard rejects them before the self-heal runs; surfaced as "Could not load tasks."
- **Remediation (design when picked up):** (1) collision-tolerant/coordinated position
  allocation; (2) self-healing reorder — recompact-then-re-check when *data* is degenerate,
  still rejecting a genuinely inverted *request*; (3) load-time normalization; (4) give
  reorder failures a transient surface, not the full-screen load error.
- The logs now make this diagnosable from real captured data (per-create `observedMaxPosition`
  + per-writer attribution).

## Untracked files
`.rca/reorder-anchors-out-of-order/` remains untracked by your call (the reorder-fix
thread owns that decision per the RCA skill's Phase 5).

## Conventions
Solo repo; conventional commits; rebase-and-merge to `main` (no PR review); HTTPS push;
never force-push; warnings-as-errors; strict concurrency on LillistCore source.
