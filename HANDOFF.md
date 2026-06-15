# HANDOFF — Rainbow Glass redesign

Evolving the Rainbow Logic design system onto Apple's iOS 26 / macOS
Tahoe **Liquid Glass**. The architecture settled on the Apple-idiomatic
line:

- **Liquid Glass** — the *floating control layer*: the FAB, toasts, the
  filter-header panel, the quick-capture panel, and buttons
  (`RainbowButtonStyle`).
- **Solid tinted** — *in-flow content*: the status chip, task rows
  (Wave 3), and toggles. Faux-3D (drop shadows, top highlights, inset
  wells, hue glows, the isometric cube) is retired everywhere.

References: plan `~/.claude/plans/let-s-perform-an-app-wide-magical-forest.md`;
roadmap + house rules in `CLAUDE.md`; the snapshot gotcha in
`docs/engineering-notes.md` (2026-06-12).

## The seam

`Packages/LillistUI/Sources/LillistUI/Theme/GlassSurface.swift`:
`glassSurface(_:in:)` (glass → solid fill for tints / `.regularMaterial`
for chrome → opaque under Reduce Transparency), `glassGroup()`
(`GlassEffectContainer`), `glassElevation()`.

## Done (committed to main)

- **Wave 0** seam + tests + `GlassRowSpike`.
- **Wave 1** control layer: toasts (iOS+macOS), filter header, quick
  capture.
- **Wave 2** FAB (glass), buttons (glass), toggles (flat native solid).
- **Wave 4** retired `RainbowTopHighlight` + `rainbowGlow` (deleted);
  flattened filter chip, sidebar chip, recurrence picker, sync bar.
- **Status chip** is a solid tinted circle (reverted from glass).
- **Wave 5** chrome: Share Extension (system components → auto-glass) and
  the macOS NSPanel (already non-opaque) need no work; the FAB↔capture
  morph was intentionally skipped.
- **Verification:** `Lillist-iOSAppHostedTests/GlassSnapshotTests` — the
  only place glass can be snapshotted (app-hosted → live key window).
  Covers FAB, buttons, toggles + a capture-path guard. Green.

## Remaining

1. **Wave 3 — task rows.** Replace `rainbowShadow` card elevation with a
   solid tinted surface (NOT glass — content layer). `RainbowCard` /
   `TaskRowView`. No perf gate now (decision: solid).
2. **Wave 6 — snapshot reconciliation (the big one, in progress).**
   The blanking rule (proven; see engineering-notes 2026-06-14):
   *interactive* glass and an always-present `GlassEffectContainer` blank
   the whole offscreen capture; *non-interactive* glass mostly renders
   offscreen with the tour strategy. Already landed: TasksScreen toast
   `glassGroup`→`VStack`, and the FAB overlay removed from the tour's
   `phoneShell` — these un-blank most iOS tours.
   - **Strip remaining interactive glass from offscreen tests:** `test_06`
     (taskDetail) still blanks via `StatusIndicatorView`'s Menu — render
     the display-only `StatusCubeView` in that mock instead, or move
     `test_06` to app-hosted. Same for any screen using the interactive
     status control.
   - **Migrate the lone-glass component tests to app-hosted** (they
     render the glass element by itself, so they blank): the FAB +
     `QuickCaptureDialog` cases in `iOSSnapshotTests`, the iOS
     `QuickCaptureDialogTests`. Delete those blanking baselines from
     `LillistUITests` (FAB already covered app-hosted; add QuickCapture).
   - **macOS gap:** no macOS app-hosted glass target exists. macOS glass
     (`QuickCaptureView` panel, inline toast, glass buttons in
     `MacOSScreenTourTests`) can't be captured in `LillistUITests`. Add a
     `Lillist-macOSAppHostedTests` target (mirror the iOS one) or accept
     manual macOS glass verification.
   - **Then RECORD-rebaseline everything else** (solid, captures fine —
     `StatusCubeSnapshotTests` now a solid circle, the Wave-3 flat cards,
     the Wave-4 flattened surfaces, contrast/reduce-transparency, the
     un-blanked tours): `RECORD_SNAPSHOTS=YES` on
     `xcodebuild test -scheme Lillist-iOS`, then assert green.
   - **Detect stragglers** by size: blank PNGs compress tiny
     (`for f in **/*.png; do echo "$(stat -f%z "$f") $f"; done | sort -n`
     — anything unexpectedly small is still-blanking glass).
3. **Docs:** fold the Rainbow Glass evolution into the design-system doc
   `docs/plans/2026-06-12-rainbow-logic-design-system.md`.

## Verify before pushing

`swift test` both packages; `xcodebuild test -scheme Lillist-iOS` (incl.
`GlassSnapshotTests` and the rebaselined suites); both app builds. The
`make test` pre-push hook will stay red until the Wave 6 reconciliation
is done. Glass dark-mode rendering is only trustworthy on real hardware.
