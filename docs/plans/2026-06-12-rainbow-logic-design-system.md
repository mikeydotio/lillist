# Rainbow Logic — Lillist Visual Design System

**Status:** Canonical visual spec, 2026-06-12. Supersedes the implicit
flat/system-color aesthetic. Product behavior remains specced by
`2026-05-12-lillist-design.md`; this document owns *how it looks*.

Rainbow Logic ("Structured Whimsy") was authored in Claude Design by
Mikey; the exported source of truth (CSS tokens + JSX component specs)
is archived at the design project
`claude.ai/design/p/4e163e50-5bf7-4803-a660-70813c213342`. This
document is its **SwiftUI translation**: Things-like refined
simplicity, colorful whimsy, tactile 3D depth, compact density. The
app icon (glossy 3D rainbow `{✓}` braces on a dot grid) is the north
star — the UI matches the icon, not vice versa.

## Principles

1. **Color is functional, never decorative.** Every hue means
   something (status, urgency, category). The full rainbow gradient is
   reserved for headers, heroes, and success moments.
2. **Volumetric, squishy, tactile.** Raised surfaces carry a soft
   two-layer shadow plus a top light highlight; inputs are inset
   wells; controls squish when pressed (overshoot easing).
3. **Compact and calm.** Whimsy lives in the details; layout stays
   tight and quiet (Things-density, not marketing-page density).
4. **Accessibility is a gate, not a goal.** Dynamic Type everywhere,
   shape axes alongside color, WCAG ≥ 4.5:1 enforced by unit tests,
   Reduce Motion / Transparency / Increase Contrast all honored.

## Tokens

### Rainbow spectrum (scheme-invariant)

| Stop | Hex |
|---|---|
| purple | `#8B45E8` |
| blue | `#2E90FA` |
| cyan | `#1FC3E0` |
| green | `#34C25A` |
| lime | `#B6D63A` |
| orange | `#FF7A1A` |

Gradients (`RainbowGradient`): `vertical` (purple→orange, matches the
icon braces), `horizontal` (95°, headline text + header bars + the
migration progress fill), `halo` (conic, hover/drag-lift edge only).

### Semantic surfaces & text (`LillistColor`, light | dark)

| Token | Light | Dark | Use |
|---|---|---|---|
| `workspace` | `#EEF0F6` | `#14151A` | Screen/list background |
| `card` | `#FFFFFF` | `#1F2128` | Task cards, form rows, sheets |
| `raised` | `#FFFFFF` | `#262833` | Popovers, drag phantom |
| `sunken` | `#F2F3F8` | `#191A20` | Search/input wells |
| `lavender` | `#F1ECFB` | `#2A2438` | Signature add-task surfaces |
| `textStrong` | `#1B1C22` | `#F4F5F9` | Titles |
| `textBody` | `#3C3F49` | `#C9CCD6` | Body |
| `textMuted` | `#71757F` | `#9A9EA9` | Secondary/meta |
| `textFaint` | `#969AA6` | `#70747F` | Tertiary, todo status |
| `borderSoft` | `#DFE1E9` | `#3A3D47` | Standard borders |
| `borderHair` | `#E9EBF1` | `#2B2D36` | Card hairlines |
| `borderStrong` | `#C0C3CD` | `#4A4E59` | Increase-contrast borders |

Dark values are a derived extension (the exported system is
light-only): surfaces from the ink ramp, hues lifted/desaturated in
the spirit of `TagTint`'s existing dark handling.

### Functional palette (`RainbowPalette.Functional`: base / soft / ink / deep)

| Hue (meaning) | base L | base D | soft L | soft D | ink L | ink D | deep L |
|---|---|---|---|---|---|---|---|
| `actionOrange` (urgent/blocked/error) | `#FF7A1A` | `#FF8A3B` | `#FFEAD7` | base @ 0.16 | `#C2530A` | `#FFB068` | `#E5650C` |
| `growthGreen` (routine/done) | `#2FB457` | `#46C26A` | `#D9F3E0` | base @ 0.16 | `#1B8540` | `#79DDA0` | `#25A04C` |
| `focusBlue` (work/in-progress) | `#2E90FA` | `#4D9FFB` | `#DBEAFE` | base @ 0.16 | `#1568CC` | `#7FB6FF` | `#1E7FE6` |
| `scriptPurple` (system/brand) | `#8B45E8` | `#9D63EE` | `#EADBFB` | base @ 0.18 | `#6A28C0` | `#C09BF5` | `#7A35DA` |
| `cautionAmber` (stale/paused — Lillist extension) | `#F2A60D` | `#F5B53A` | `#FCF0D4` | base @ 0.16 | `#8F6500` | `#FFD37A` | `#D98F06` |

Rules: **base is never text.** Text/glyphs on soft or card use `ink`.
Dark `soft` = base at low opacity over `card`. `cautionAmber` is a
Lillist-added hue (the exported system has no warning yellow); it
follows the same base/soft/ink/deep grammar and the same contrast
gates. Ink values may be darkened by the `RainbowContrastTests` sweep
if any (ink, soft) pair falls under 4.5:1 — the test is the authority.

### Status mapping (`StatusPalette`)

| Status | Color | Cube rendering (shape axis) |
|---|---|---|
| todo | `textFaint` | raised empty cube, top highlight |
| started | `focusBlue` | blue fill, white left-half glyph |
| blocked | `actionOrange` (ink for text/glyphs) | orange soft fill, dashed ink border, pause bars |
| closed | `growthGreen` | green fill, white check (squish snap-in) |

This replaces the Plan-17 red for blocked. Contrast is preserved by
the ink-not-base text rule; the cube's shape axis keeps status legible
without color. Soft fill opacity 0.16 → 0.30 under Increase Contrast.

### Sync mapping (`SyncPalette`)

idle-recent → `growthGreen` · idle-stale → `cautionAmber` · never
synced → `borderStrong` · in-progress → `focusBlue` · error →
`actionOrange.deep` · paused → `cautionAmber.ink`. The
differentiate-without-color glyph axis is unchanged.

### Elevation (`LillistElevation`)

Two stacked soft shadows (ink `#1B1C22` base), radius/y/opacity:

| Level | Layer 1 | Layer 2 | Use |
|---|---|---|---|
| `xs` | 2 / 1 / .05 | 1 / 1 / .04 | **List rows (hard cap)**, chips |
| `sm` | 3 / 1 / .06 | 8 / 4 / .05 | Hover lift, active sidebar chip |
| `card` | 2 / 1 / .04 | 16 / 6 / .07 | Standalone cards, wells' parents |
| `lift` | 6 / 2 / .06 | 32 / 14 / .13 | Toasts, floating bars |
| `pop` | 18 / 8 / .10 | 60 / 24 / .18 | Drag phantom, modals |

Plus: `rainbowGlow(hue)` = base @ .32 (light) / .38 (dark), r6 y6 —
filled controls only. Inset wells via `ShapeStyle.shadow(.inner)`
(r2 y1 + r0.5 y0.5). Raised controls add an inset top white highlight
(linear, white .7 → clear). Dark scheme: shadows ×0.9 alpha — surface
value separation does the work. **Perf rule: repeating list rows never
exceed `xs`; `compositingGroup()` before every card shadow.**

### Motion (`LillistMotion`)

`squish` = `timingCurve(0.34, 1.56, 0.64, 1.0)` (overshoot), `easeOut`
= `timingCurve(0.22, 0.61, 0.36, 1.0)`; durations 0.12 / 0.20 / 0.36 s.
All decorative motion routes through `accessibleAnimation` (Reduce
Motion = none). Confetti additionally gates on `ConfettiPolicy`.

### Typography (`LillistTypography`, Plus Jakarta Sans)

Static TTFs (Regular/Medium/SemiBold/Bold/ExtraBold, OFL) bundled in
LillistUI resources, registered process-scoped via `CTFontManager` on
first use (`LillistFonts.registerIfNeeded()`), falling back to system
fonts if registration fails. Every token is `relativeTo:` a Dynamic
Type style — user text-size settings keep working:

| Token | Weight | pt | relativeTo |
|---|---|---|---|
| `largeTitle` | ExtraBold | 30 | `.largeTitle` |
| `title` | Bold | 24 | `.title` |
| `title2` | Bold | 20 | `.title2` |
| `title3` | SemiBold | 17 | `.title3` |
| `headline` | SemiBold | 15 | `.headline` |
| `body` | Regular | 15 | `.body` |
| `subheadline` | Medium | 13 | `.subheadline` |
| `caption` | SemiBold | 11.5 | `.caption` |
| `caption2` | Medium | 11 | `.caption2` |
| `quickCaptureField` | SemiBold | 17 | `.title3` |

No JetBrains Mono: `.monospaced()` system styles cover version labels
and crash payloads (YAGNI until a script-editor surface exists).
Eyebrow/section labels: `caption` + 0.08 em kerning, uppercase.

### Spacing & radii

Spacing scale unchanged (4/8/12/16/24/40). Radii: `s 8`, `m 12`
(cards), `l 16`, `xl 22`, cube `8`; capsules via `Capsule`. Continuous
corner style on all rounded rects.

## Density (compact spec)

| Measure | Value |
|---|---|
| List row insets | 3 / 12 / 3 / 12 (6 pt inter-card gap) |
| Card internal padding | 9 pt vertical, 12 pt horizontal |
| Status cube | 24 pt visual in 44 pt hit target (`@ScaledMetric`) |
| Accent stripe | 3 pt capsule, inset 8 pt vertically |
| Single-line row | ≈ 46 pt; with meta line ≈ 62 pt |
| Card radius | 12 pt |
| Buttons | sm 32 pt / md 40 pt height |
| Search well | 36 pt height |
| FAB | 52 pt circle |
| Toggle | 44 × 26 track, 20 pt thumb |

## Signature components (web → SwiftUI)

- **TaskCard → `RainbowCard` + `TaskRowView`**: `card` fill, hairline
  border, `xs` shadow, status-colored stripe; done = opacity 0.62,
  strikethrough, no shadow; hover (pointer platforms only) = `sm`
  lift + rainbow halo stroke.
- **Cube checkbox → `StatusCubeView`** inside the existing
  `StatusIndicatorView` `Menu(primaryAction:)` (tap-to-cycle contract,
  identifier, 44 pt target all unchanged). Confetti
  (`ConfettiBurstView`, TimelineView+Canvas, seeded RNG, 600 ms,
  10 quads cycling the 6 spectrum stops) fires **only** on a
  transition *into* closed and never under Reduce Motion
  (`ConfettiPolicy.shouldBurst`).
- **Button → `RainbowButtonStyle`**: capsule, top highlight, hue glow,
  pressed squish. Variants lavender (signature add) / functional hues /
  rainbow (hero CTAs only) / secondary / ghost.
- **SearchBar/Input → sunken wells** (`rainbowInsetField()`), focus
  ring `focusBlue @ 0.35`.
- **Switch → `RainbowToggleStyle`**: sunken track, raised squishy
  thumb. Used on **both** platforms' settings (full-whimsy decision).
- **Tag → `TagChipView`** `.meta` (8 pt swatch + muted label, in rows)
  and `.pill` (white capsule, detail surfaces). The `TagTint`
  engine — user hex, dark desaturation, WCAG clamp — is unchanged.
- **SidebarItem → `SidebarRowView`**: 22 pt icon chip, tint-filled
  with white glyph when selected; tabular count.
- **Empty states → `RainbowEmptyStateView`**: dot-grid Canvas backdrop
  (22 pt grid, 1.3 pt dots, ink @ 7% / white @ 6%), rainbow-masked SF
  icon, CTA slot. Dot grid appears **only** on heroes/empty states.
- **Toasts**: existing `accessibleMaterial` frost, `card` fallback,
  `lift` shadow.

## Themeable vs system (macOS boundary)

Themed: task list + rows, detail header pill, sidebar row internals,
menu-bar popover, preferences controls (full whimsy: RainbowToggle +
inset fields + Jakarta), quick-capture panel content, empty states.
Left system deliberately: window chrome/toolbar, sidebar material and
selection pill, menus, segmented pickers. We do not fight AppKit.

## Brand accent

Both apps' `AccentColor` = `scriptPurple` (`#8B45E8` / `#9D63EE`).
"Started" stays `focusBlue`, so selection tint and status never blur.

## Test contracts

- All snapshot baselines re-recorded per wave on the pinned Mac
  (recipe in CLAUDE.md); new suites: status cube states,
  rainbow controls gallery, empty state, compact task cards.
- `RainbowPaletteTests` pins every hex above per scheme;
  `StatusPaletteTests` pins the status mapping;
  `RainbowContrastTests` sweeps (ink, soft) and ink-on-card pairs
  ≥ 4.5:1 both schemes; `LillistFontsTests` covers registration
  idempotence + fallback; `ConfettiPolicyTests` covers the
  transition × Reduce Motion matrix.
- `StatusCycleUITests`, a11y suites, and the localization lint must
  pass untouched — the redesign adds zero user-visible strings.
