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
2. **Wave 6 — snapshot reconciliation (the big one).** Glass blanks in
   the standalone `LillistUITests`, so:
   - **Migrate to app-hosted:** the FAB + `QuickCaptureDialog` cases in
     `iOSSnapshotTests`, and any `IOSScreenTourTests` variant showing
     glass (expanded filter header, toasts, glass buttons in empty
     states). Delete the blanking baselines from `LillistUITests`.
   - **macOS gap:** there is **no macOS app-hosted glass target**. The
     macOS glass surfaces (quick-capture panel, inline toast) can't be
     snapshotted in `LillistUITests`. Either add a
     `Lillist-macOSAppHostedTests` target (mirror the iOS one) or accept
     manual macOS glass verification.
   - **Rebaseline the rest (solid, captures fine):**
     `StatusCubeSnapshotTests` (now a solid circle), and the Wave-4
     flattened surfaces (recurrence/sidebar/sync, filter chip),
     `ContrastSnapshotTests`, `ReduceTransparencySnapshotTests`.
     `RECORD_SNAPSHOTS=YES` on `xcodebuild test -scheme Lillist-iOS`.
3. **Docs:** fold the Rainbow Glass evolution into the design-system doc
   `docs/plans/2026-06-12-rainbow-logic-design-system.md`.

## Verify before pushing

`swift test` both packages; `xcodebuild test -scheme Lillist-iOS` (incl.
`GlassSnapshotTests` and the rebaselined suites); both app builds. The
`make test` pre-push hook will stay red until the Wave 6 reconciliation
is done. Glass dark-mode rendering is only trustworthy on real hardware.
