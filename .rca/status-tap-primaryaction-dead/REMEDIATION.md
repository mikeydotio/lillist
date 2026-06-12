# Remediation Plan (executed 2026-06-12)

## Root Cause (Summary)
The row-wide long-press drag gesture consumed quick taps on the embedded
status control; the failure shipped invisibly because no test exercises real
taps and the action pipeline swallows every failure mode.

## Fix (landed)
1. **2ee2a6d `fix(ios)`** — structural: `TaskRowLabel` extracted from
   `TaskRowView` (macOS pixel-identical); `TaskOutlineRowView` split API hands
   the caller ONLY the inert text label for wrapping (type-enforced
   invariant); `NavigationLink` + new gesture-only `.dragReorderGesture` wrap
   just that label; `.reportRowGeometry` stays row-level so drag-overlay
   geometry is unchanged. Drags start from the text region; the circle's
   long-press belongs to the menu. 7 tour baselines re-recorded (only pixel
   delta: List accessory chevron position).
2. **a8ac881 `test(ios)`** — `StatusCycleUITests` drives the real
   tap→closure→store chain on the localOnly `--ui-test-*` seams: cycle ×2 +
   no-navigation + relaunch persistence + long-press menu + control
   addressability. Shared `UITestHelpers` extracted.
3. **ac7ad90 `feat(diagnostics)+fix(ui)`** — `task.transition` diagnostic
   emit (from/to/noop/spawned/threwError); iOS `try?` → do/catch + transient
   `StatusChangeFailureToast` (generalized `TransientFailureToast`).
4. **1d1f285 `fix(stores)`** — incidental P0 found en route: empty-store
   launch crash in both load-seam normalizers (`1..<count` on empty fetch);
   every fresh install of the next build would have crashed at launch.

## Anti-Pattern Check
| Check | Pass/Fail |
|-------|-----------|
| Not symptom masking | PASS — removes the structural conflict |
| Not a band-aid | PASS — no arbitration tuning / priority hacks |
| Not whack-a-mole | PASS — also fixes chevron taps; type system prevents re-wrapping |
| Strengthens invariants | PASS — closure API + never-silent transitions |

## Process Root Cause ("how was this allowed to happen")
1. **No interaction-layer coverage**: unit tests call closures directly,
   snapshots are static, store tests hit the API — a dead control passed
   every suite. → closed by StatusCycleUITests.
2. **Structure changed under an interaction-opaque control**: the
   `Menu(primaryAction:)` contract was never re-verified when the screen
   gained the NavigationLink wrap + row drag gesture 9–10 days later.
   → closed by the type-enforced label-only wrapping API.
3. **Silent-by-design failure pipeline**: `try?` + equal-status no-op + no
   transition diagnostic + no error surface ⇒ zero signal across 5 deploys.
   → closed by the emit + toast.
4. **No fresh-install smoke at deploy time** (also let the normalize crash
   ship): the deploy flow installs over an existing store. → noted in
   engineering-notes; candidate checklist item for /deployit runs.

## Remaining (manual, Mikey)
- Device pass on build 41: tap-cycle, long-press set, drag-reorder,
  swipe-delete, title-tap navigation, VoiceOver row reading.
- macOS spot-check: click/right-click the status glyph (shared TaskRowView
  recomposition; build verified, behavior unchanged by inspection).
- Pre-existing (NOT from this work): `iOSSnapshotTests`
  `test_floatingAddButton_light` + `test_statusIndicator_menu_button_renders_at_44pt`
  fail on clean main on this host — baselines drifted; decide re-record vs
  investigate.
