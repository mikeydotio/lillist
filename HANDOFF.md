# HANDOFF — Data & Sync Hardening: PROGRAM COMPLETE, PR not yet opened

**Worktree:** `/Volumes/Code/mikeyward/Lillist/.claude/worktrees/data-sync-hardening`
**Branch:** `hardening/data-sync-2026-07`
**State:** All 70 findings from `docs/reviews/2026-07-28-data-sync-review.md`
are closed across Waves 0–6. This was the program's last wave (`6a`
`completeness-and-lows` + closeout). **Nothing left to fix.** The only
remaining step is opening the one program PR — see below.

## What landed in Wave 6

Full per-item design: `docs/superpowers/plans/2026-07-28-plan-6a-completeness-and-lows.md`.
Full commit table + verification transcript: the ledger's *Wave 6 closing
report* (`docs/superpowers/plans/2026-07-28-data-sync-hardening-index.md`).

- `L1`/`L2`/`L6` (the program's three remaining lows) — closed.
- Six residuals flagged across earlier waves' closing reports, folded into
  this wave's scope — closed: `LIL-77` (crash-prompt toggle bound to the
  wrong preference store), `LIL-80`/`LIL-81` (`restoreFromBackup`'s missing
  backup-package resync and account-changed guard), `LIL-82`
  (`TaskDuplicateReconciler.diagnosticLog` wiring), `LIL-84` (three named
  timing-flake tests hardened, each with a shape-appropriate fix), `LIL-87`
  (`LocalBackupCoordinator`'s missing launch-time history catch-up).
- Two **genuinely new** defects this wave's own completeness-proof tests
  surfaced — found and fixed in the same session: `LIL-88` (`Importer.apply`
  never restored `document.preferences` at all — every export/import cycle
  silently reverted every account-level preference to its default) and
  `LIL-89` (`recoverInterruptedReseed()` never broadcast to peers, found via
  the ledger residual sweep, not a test).
- `LIL-90` (a latent `NotificationSpec` in-place-edit reconcile gap) —
  reconfirmed still correctly deferred, not fixed (unreachable in production
  today; fixing it now would be speculative code).
- Two new completeness-proof test suites the wave brief called for
  directly: export/import round-trip equality (the suite that caught
  `LIL-88`), and an `X20` flip-flop stress test across two real
  cross-process controllers.

**Verification:** full `LillistCore` suite green twice at the final commit
(1451 tests, 262 suites, unmasked exit codes, clean failure-marker grep; one
SIGSEGV worker-crash flake between the two runs, matching the documented
class, cleared on retry). LillistUI non-snapshot suite green (87/18).
`lillist-cli` builds. Both apps verified with unsigned `xcodebuild` builds.
`xcodegen generate` — zero drift for both `project.yml` specs.

## What still needs Mikey (not gates on anything — tracked, not blocking)

Both are named, with a redesign trigger, in the ledger's *Decisions
awaiting Mikey* section:

- **`LIL-83`** — `X10`'s all-day-notification timezone-dedup posture needs
  a new synced `AppPreferences` home-timezone field, which needs a
  Development→Production CloudKit schema deploy in the Console — explicitly
  deferred out of this program (near its end, not worth expanding the
  zero-schema-change posture this program held throughout). Redesign
  trigger: a real user report of a cross-timezone duplicate notification,
  or Mikey scheduling the field work directly.
- **`LIL-90`** — the latent `NotificationSpec` in-place-edit gap. Redesign
  trigger: any new `NotificationSpecStore.update` caller reachable from a
  different device/process than the one that created the spec (e.g. a
  future cross-device snooze feature).

Plus the full **manual-verification checklist** in the ledger (CloudKit
Console purge-record audit, macOS store-location migration, live sync-mode
switches, a second-Apple-ID account switch, two-device reset propagation,
real-widget checks) — none of it gates anything; it's for Mikey to run at
leisure with real devices/accounts.

## Next step — open the one program PR, then stop

Per this worktree's standing rule (deploys/merges only run from `main`,
never from a linked worktree): push this branch, open one PR summarizing
the whole program (link the review doc + the ledger), and **stop** — no
merge, no version bump, no deploy from here. The orchestrator/Mikey reviews
and merges from `main`.

## If you're picking this up fresh

Read, in order: this file → the ledger's *Current status* banner (now reads
PROGRAM COMPLETE) → the *Wave 6 closing report* → the plan doc above. There
is no next wave. If something in production surfaces a NEW defect, it's a
new investigation (or, if it retriggers `LIL-83`/`LIL-90`'s known
limitations specifically, use their existing redesign triggers above), not
a resumption of this program.
