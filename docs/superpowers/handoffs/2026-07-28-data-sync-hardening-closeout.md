# Closeout handoff — Data & Sync Hardening

> **Archived 2026-07-29.** This was the repo-root `HANDOFF.md` while the
> program was in flight. The program branch `hardening/data-sync-2026-07`
> merged to `main` via **PR #77** on 2026-07-29, so this file is now the
> program's closing handoff — historical record, not an active to-do. The
> two standing items in *What still needs Mikey* below are the only live
> content; everything else describes work already landed.

**Branch:** `hardening/data-sync-2026-07` (merged, PR #77)
**State:** All 70 findings from `docs/reviews/2026-07-28-data-sync-review.md`
are closed across Waves 0–6. The program's last wave was `6a`
(`completeness-and-lows` + closeout). **Nothing left to fix.**

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

## How it landed

The branch pushed and opened one PR summarizing the whole program (linking
the review doc + the ledger); Mikey merged it from `main` as **PR #77** on
2026-07-29 — merge commit `8f1b6fc0`, 238 files, ~29.6k insertions. The
post-merge docs tidy (this archive, the CLAUDE.md program entry, the
ledger's status banner) followed in a separate PR, alongside the `v0.19.0`
minor bump and the iOS/macOS deploys.

## If you're picking this up fresh

Read, in order: this file → the ledger's *Current status* banner (reads
PROGRAM COMPLETE) → the *Wave 6 closing report* → the plan doc above. There
is no next wave. If something in production surfaces a NEW defect, it's a
new investigation (or, if it retriggers `LIL-83`/`LIL-90`'s known
limitations specifically, use their existing redesign triggers above), not
a resumption of this program.
