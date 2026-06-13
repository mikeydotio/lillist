# HANDOFF — Rainbow Glass redesign

Evolving the Rainbow Logic design system onto Apple's iOS 26 / macOS
Tahoe **Liquid Glass**: the whimsical rainbow palette becomes functional
*glass tints*, and the hand-rolled faux-depth (two-layer drop shadows,
top highlights, inset wells, the isometric status cube) is retired for
native glass depth.

- **Plan:** `~/.claude/plans/let-s-perform-an-app-wide-magical-forest.md`
- **Roadmap + house rules:** the "Rainbow Glass redesign — IN PROGRESS"
  section of `CLAUDE.md`.
- **Gotcha that shaped the approach:** `docs/engineering-notes.md`
  2026-06-12 (Liquid Glass blanks offscreen snapshots).

## The seam (use this for all glass)

`Packages/LillistUI/Sources/LillistUI/Theme/GlassSurface.swift`:
- `glassSurface(_ role:in:)` — glass on OS 26; below 26 falls back to a
  solid color for tinted **fills** (`primaryAction`, `statusTinted`,
  `card`, `control`) and to `.regularMaterial` for **chrome**
  (`panel`, `toast`); opaque under Reduce Transparency. All `#available`
  and accessibility handling is centralized here.
- `glassGroup(spacing:)` — wrap co-visible/overlapping glass
  (`GlassEffectContainer`); glass can't sample glass.
- `glassElevation(_:)` — yields to glass on 26, falls back to
  `rainbowShadow` below.

## Done (committed to main, Waves 0–2)

- Control layer: toasts (iOS + macOS), filter header, quick capture.
- FAB: prominent tinted glass (`.primaryAction`).
- `StatusCubeView`: circular glass **chip** (user pick), shape-axis +
  confetti preserved, to-do keeps a stroke. NB: glass-per-row.
- `RainbowButtonStyle` / `RainbowToggleStyle`: glass / native-toggle.
- Verification: `Lillist-iOSAppHostedTests/GlassSnapshotTests` (9 tests,
  green) — the **only** place glass can be snapshotted.

## Remaining

1. **Wave 3 — content rows (GATED).** `RainbowCard` / task rows: replace
   `rainbowShadow` elevation with glass. **Blocked on an on-device
   per-row-glass perf test** (Instruments, 200+ tasks). `StatusCubeView`
   is *already* glass-per-row, so this perf result is retroactive — if it
   janks, fall back to a solid tinted chip/card (still retires faux-3D).
   Spike harness: `Theme/GlassRowSpike.swift` (`#Preview`).
2. **Wave 4** — retire now-unused `LillistElevation` shadow paths;
   `RainbowEmptyStateView` glass; reconcile `RainbowGradient` heroes.
3. **Wave 5** — FAB↔quick-capture `glassEffectID` morph; scroll-edge
   effects; `ToolbarSpacer` grouping; **fix macOS NSPanel backing**
   (`QuickCapturePanelController` must be non-opaque for glass); Share
   Extension chrome.
4. **Wave 6** — tinted-glass contrast hardening (extend
   `RainbowContrastTests`); full snapshot rebaseline (non-glass via
   `LillistUITests`, glass via the app-hosted suite); update the design
   doc to "Rainbow Glass".

## Verify before pushing

`swift test` both packages; `xcodebuild test -scheme Lillist-iOS`
(incl. `GlassSnapshotTests`); both app builds. Glass dark-mode rendering
is only trustworthy on real hardware. Re-record glass baselines with
`RECORD_SNAPSHOTS=YES` on the app-hosted suite after intentional changes.
