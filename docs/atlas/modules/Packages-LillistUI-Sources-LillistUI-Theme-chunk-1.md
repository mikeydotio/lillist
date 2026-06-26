---
module: "Packages/LillistUI/Sources/LillistUI/Theme (chunk 1)"
summary: "Rainbow Glass design tokens: palette, glass seam, motion, elevation, status/sync/tag coloring."
read_when: "Touching theme colors or glass surfaces"
sources:
  - path: "Packages/LillistUI/Sources/LillistUI/Theme/Color+Hex.swift"
    blob: 71bd769cdd3d9632ef4353f22cc0df0ebaa246cc
  - path: Packages/LillistUI/Sources/LillistUI/Theme/Fonts/LillistFonts.swift
    blob: ec07c427560d4df7f0fd2eb1e8fdd17afd2482aa
  - path: Packages/LillistUI/Sources/LillistUI/Theme/GlassRowSpike.swift
    blob: 83db647bca06e91ed8d75a86aa52d6bacc7d3260
  - path: Packages/LillistUI/Sources/LillistUI/Theme/GlassSurface.swift
    blob: 8eb677573dc0a43fd12098c04266c98d132b30b2
  - path: Packages/LillistUI/Sources/LillistUI/Theme/LillistColor.swift
    blob: 3cd18bceeb600d9bd002b349487badcea99916d5
  - path: Packages/LillistUI/Sources/LillistUI/Theme/LillistElevation.swift
    blob: 0cd223bcb1c64678fe88d554fb2e80bc97b3b0bc
  - path: Packages/LillistUI/Sources/LillistUI/Theme/LillistMotion.swift
    blob: ac5368821890aa6ebe93adfa19aaf8117f523f07
  - path: Packages/LillistUI/Sources/LillistUI/Theme/RainbowButtonStyle.swift
    blob: a860c62c603894f4bfffd4e04eec801a32f684d5
  - path: Packages/LillistUI/Sources/LillistUI/Theme/RainbowGradient.swift
    blob: 1c4d99c9e29cf55bb45ae3a0b6b28debd79cc01c
  - path: Packages/LillistUI/Sources/LillistUI/Theme/RainbowPalette.swift
    blob: 392014d98fcc0542054d7d5101c3f228c3aadcae
  - path: Packages/LillistUI/Sources/LillistUI/Theme/RainbowToggleStyle.swift
    blob: eeae0732604ccdc2cd2c867eea5124f531472196
  - path: Packages/LillistUI/Sources/LillistUI/Theme/StatusGlyph.swift
    blob: 0f338cb0549bf8f37f9a807b607e8ea280d4b594
  - path: Packages/LillistUI/Sources/LillistUI/Theme/StatusPalette.swift
    blob: 4f9ac797b8389bd64e0f31de8c8406c150b041d9
  - path: Packages/LillistUI/Sources/LillistUI/Theme/SyncPalette.swift
    blob: ae2ada13fd769e9731c0efaabbf4ca9c3f750857
  - path: Packages/LillistUI/Sources/LillistUI/Theme/TagTint.swift
    blob: ef5e3e2cdc62a9a405f12d0f0f5b70933ef34c89
references_modules: [Apps-Lillist-macOS-Sources-Hotkey, Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2, Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistUI-Sources-LillistUI-Accessibility, Packages-LillistUI-Sources-LillistUI-Recurrence, Packages-LillistUI-Sources-LillistUI-Settings]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistUI/Sources/LillistUI/Theme (chunk 1)

## Purpose

This module is the Rainbow Glass design system's token and seam layer for LillistUI: it defines every color, motion, elevation, and glass-surface primitive that components consume, and it is the single integration point for Apple's Liquid Glass material with full OS-version degradation. The whimsical rainbow palette survives here as functional glass tints (status, sync, tag) that carry semantic meaning rather than decoration. Without this module every LillistUI component would lose its visual identity, accessibility-respecting motion/contrast behavior, and the centralized #available gate that keeps macOS Sequoia on the pre-glass Material path.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `ButtonStyle` | extension | `Packages/LillistUI/Sources/LillistUI/Theme/RainbowButtonStyle.swift:103` | Adds `.rainbow(_ variant:size:)` static shorthand so callers write `.buttonStyle(.rainbow(.lavender))` instead of constructing `RainbowButtonStyle` directly. |
| `Color` | extension | `Packages/LillistUI/Sources/LillistUI/Theme/Color+Hex.swift:19` | Adds `init?(hex:)` (6- or 3-digit RGB string → Color) and `toHex()` (Color → #RRGGBB); distinct from TagTint.init?(hex:) which also applies dark-mode desaturation. |
| `Functional` | struct | `Packages/LillistUI/Sources/LillistUI/Theme/RainbowPalette.swift:83` | One functional hue with base/soft/ink/deep axes; `base` is never a text color — use `ink` for text/glyphs; WCAG AA for (ink, soft) and (ink, card) is enforced by RainbowContrastTests. |
| `GlassRowSpike` | struct | `Packages/LillistUI/Sources/LillistUI/Theme/GlassRowSpike.swift:27` | DEBUG-only Wave 0 spike view for evaluating full-glass vs accent-glass task row treatments; not a production component and has no callers outside its own previews. |
| `GlassSurface` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/GlassSurface.swift:32` | Discriminated union describing a glass surface's role and fallback behavior; callers pass a case to `glassSurface(_:in:)` to receive the correct OS-adaptive treatment. |
| `LillistColor` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/LillistColor.swift:11` | Catalog of semantic surface, text, and border color tokens backed by `RainbowPalette.dynamic`; the only color API components should reach for structural roles — all values are scheme-pinned by tests. |
| `LillistElevation` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/LillistElevation.swift:17` | Five elevation levels for the pre-26 two-layer drop shadow system; callers must not exceed `.xs` for repeating list-row cells. |
| `LillistFonts` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/Fonts/LillistFonts.swift:22` | Namespace for bundled Plus Jakarta Sans registration; callers use `registerIfNeeded()` and fall back to system fonts if it returns false. |
| `LillistMotion` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/LillistMotion.swift:12` | Duration constants (`fast`/`base`/`slow`) and `Animation` factories (`squish`, `easeOut`) for the Rainbow Logic motion system; all decorative animations must route through `accessibleAnimation` to respect Reduce Motion. |
| `NSColor` | extension | `Packages/LillistUI/Sources/LillistUI/Theme/RainbowPalette.swift:158` | Convenience `init(hex:UInt32, alpha:Double)` for `NSColor`; used internally by `RainbowPalette.dynamic()` on macOS to construct appearance-resolving colors. |
| `RainbowButtonStyle` | struct | `Packages/LillistUI/Sources/LillistUI/Theme/RainbowButtonStyle.swift:16` | Rainbow Glass pill button; variant must be chosen by function (see doc comment); applies tinted glass or gradient per variant, squish-on-press with Reduce Motion gating. |
| `RainbowGradient` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/RainbowGradient.swift:8` | Three sanctioned gradient presets (vertical/horizontal/halo) reserved for headers, heroes, and success moments; callers must not use them as ambient decoration. |
| `RainbowPalette` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/RainbowPalette.swift:22` | Color data layer: provides `dynamic(light:dark:)` factory, the six `Spectrum` stops, and five named `Functional` hues; components must not read hex values directly — go through `LillistColor` or named hues. |
| `RainbowToggleStyle` | struct | `Packages/LillistUI/Sources/LillistUI/Theme/RainbowToggleStyle.swift:14` | Custom toggle with flat track, solid white thumb, squish animation; honors `reduceMotionOverride`/`increaseContrastOverride`; used on both platforms. |
| `Resolved` | struct | `Packages/LillistUI/Sources/LillistUI/Theme/TagTint.swift:5` | The fully resolved (dark-mode-adjusted, contrast-floored) tag tint as HSB + opacity; `color` property produces the SwiftUI Color ready for rendering. |
| `ShapeStyle` | extension | `Packages/LillistUI/Sources/LillistUI/Theme/LillistElevation.swift:63` | Adds `.rainbowWell` — the inset-well fill (LillistColor.sunken + two inner shadows) for search bars and text fields. |
| `Size` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/RainbowButtonStyle.swift:21` | Encodes the sm/md size tiers with their height, horizontal padding, and font; callers construct via `RainbowButtonStyle.Size.sm` or `.md`. |
| `Spectrum` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/RainbowPalette.swift:54` | Six scheme-invariant sRGB stops (purple→orange) from the app icon; used only for gradient construction and confetti — not for everyday UI color. |
| `StatusGlyph` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/StatusGlyph.swift:9` | Maps each `Status` to an SF Symbol name and a localized accessibility label; single source of truth for glyph choice across all status surfaces. |
| `StatusPalette` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/StatusPalette.swift:20` | Maps each Status to a functional hue role; single source of truth for status coloring — callers must use `ink(for:)` for text, `color(for:)` only for object fills. |
| `SyncIndicator` | extension | `Packages/LillistUI/Sources/LillistUI/Theme/SyncPalette.swift:14` | Extends `SyncIndicator` with `color`, `systemImage`, and `differentiatedSystemImage`; single source of truth for sync state → visual representation across macOS `SyncStatusDotView` and iOS `SyncStatusBadge`. |
| `TagTint` | struct | `Packages/LillistUI/Sources/LillistUI/Theme/TagTint.swift:4` | Stores an RGB tag tint from a hex string; `resolved(in:)` applies dark-mode desaturation and iterates brightness to meet the WCAG 4.5:1 contrast floor against the chip background. |
| `ToggleStyle` | extension | `Packages/LillistUI/Sources/LillistUI/Theme/RainbowToggleStyle.swift:75` | Adds `.rainbow` static property enabling `.toggleStyle(.rainbow)` shorthand. |
| `UIColor` | extension | `Packages/LillistUI/Sources/LillistUI/Theme/RainbowPalette.swift:146` | Convenience `init(hex:UInt32, alpha:Double)` for `UIColor`; used internally by `RainbowPalette.dynamic()` on iOS to construct trait-resolving colors. |
| `Variant` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/GlassRowSpike.swift:28` | Spike-internal enum for the two row treatment modes (fullGlass / accentGlass); only meaningful inside the DEBUG GlassRowSpike harness. |
| `Variant` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/RainbowButtonStyle.swift:17` | Discriminates the button's functional role; callers must pick by semantic meaning, never by aesthetics. |
| `View` | extension | `Packages/LillistUI/Sources/LillistUI/Theme/GlassSurface.swift:90` | Adds `glassSurface(_:in:)`, `glassGroup(spacing:)`, and `glassElevation(_:)` — the only three call-sites for Liquid Glass and the Rainbow Logic shadow retirement path. |
| `View` | extension | `Packages/LillistUI/Sources/LillistUI/Theme/LillistElevation.swift:41` | Adds `rainbowShadow(_:)` modifier; wraps content in `compositingGroup()` then applies two layered shadows from `level.layers` so the whole hierarchy casts one shadow. |
| `accessibilityLabel` | func | `Packages/LillistUI/Sources/LillistUI/Theme/StatusGlyph.swift:19` | Returns a localized accessibility label for a Status value; strings are fetched from the LillistUI module bundle. |
| `body` | func | `Packages/LillistUI/Sources/LillistUI/Theme/GlassSurface.swift:137` | Applies real Liquid Glass on OS 26 without branching on Reduce Transparency (the glass renderer handles it); on pre-26 falls back to `.regularMaterial` or opaque color depending on `surface.prefersSolidFallback`. |
| `body` | func | `Packages/LillistUI/Sources/LillistUI/Theme/RainbowButtonStyle.swift:77` | Dispatches each `Variant` to the correct glass tint, gradient, or flat surface treatment; private ViewModifier used only by `RainbowButtonStyle.makeBody`. |
| `color` | func | `Packages/LillistUI/Sources/LillistUI/Theme/StatusPalette.swift:23` | Returns the object-fill color for a status; must NOT be used as text color — that is `ink(for:)`. |
| `dynamic` | func | `Packages/LillistUI/Sources/LillistUI/Theme/RainbowPalette.swift:29` | Returns a trait-adapting SwiftUI Color from a (light, dark) hex pair and optional alpha values; the only correct way to produce adaptive colors in this design system. |
| `easeOut` | func | `Packages/LillistUI/Sources/LillistUI/Theme/LillistMotion.swift:26` | Returns `.timingCurve(0.22, 0.61, 0.36, 1.0, duration:)` — standard deceleration; defaults to `LillistMotion.base` duration. |
| `faceIsUsable` | func | `Packages/LillistUI/Sources/LillistUI/Theme/Fonts/LillistFonts.swift:56` | Returns true when a PostScript font name resolves to a real font (not a fallback) in the current process; used only as a registration probe. |
| `fill` | func | `Packages/LillistUI/Sources/LillistUI/Theme/StatusPalette.swift:47` | Returns a tinted fill at 16% opacity (30% under Increase Contrast) for status backgrounds such as capsules, badges, and the blocked cube. |
| `glassElevation` | func | `Packages/LillistUI/Sources/LillistUI/Theme/GlassSurface.swift:122` | No-op on OS 26 (glass carries its own shadow); delegates to `rainbowShadow(_:)` on pre-26, preserving Sequoia elevation fidelity without stacking shadow on glass. |
| `glassGroup` | func | `Packages/LillistUI/Sources/LillistUI/Theme/GlassSurface.swift:108` | Wraps siblings in `GlassEffectContainer` on OS 26 so they blend correctly; is a complete passthrough (returns `self`) on pre-26 — callers must not rely on it for layout on older OS. |
| `glassSurface` | func | `Packages/LillistUI/Sources/LillistUI/Theme/GlassSurface.swift:98` | Primary glass entry point: applies GlassSurfaceModifier with the given surface role; default shape is Capsule per system convention. |
| `ink` | func | `Packages/LillistUI/Sources/LillistUI/Theme/StatusPalette.swift:34` | Returns the WCAG AA-compliant text/glyph color for a status; safe on soft fills and cards in both schemes. |
| `makeBody` | func | `Packages/LillistUI/Sources/LillistUI/Theme/RainbowButtonStyle.swift:40` | Builds the full pill button with press-scale squish and opacity; reads `reduceMotionOverride ?? accessibilityReduceMotion` to gate animation. |
| `makeBody` | func | `Packages/LillistUI/Sources/LillistUI/Theme/RainbowToggleStyle.swift:29` | Renders the track+thumb toggle with squish animation; reads `reduceMotionOverride ?? accessibilityReduceMotion` and `increaseContrastOverride ?? accessibilityShouldIncreaseContrast` from Environment. |
| `rainbow` | func | `Packages/LillistUI/Sources/LillistUI/Theme/RainbowButtonStyle.swift:105` | Factory shorthand on `ButtonStyle`; returns a configured `RainbowButtonStyle` — the canonical call-site is `.buttonStyle(.rainbow(.lavender))`. |
| `rainbowShadow` | func | `Packages/LillistUI/Sources/LillistUI/Theme/LillistElevation.swift:45` | Applies a two-layer soft drop shadow at the specified elevation; uses `compositingGroup()` to prevent per-subview shadow duplication. |
| `registerIfNeeded` | func | `Packages/LillistUI/Sources/LillistUI/Theme/Fonts/LillistFonts.swift:36` | Thread-safe one-shot registration of bundled Plus Jakarta Sans; idempotent — multiple callers are safe; returns false only on resource/sandbox failure. |
| `resolved` | func | `Packages/LillistUI/Sources/LillistUI/Theme/TagTint.swift:37` | Returns a `Resolved` value with dark-mode saturation reduction applied and brightness clamped to pass WCAG 4.5:1 against the chip's 16%-opacity background. |
| `squish` | func | `Packages/LillistUI/Sources/LillistUI/Theme/LillistMotion.swift:21` | Returns the signature overshoot spring animation (y > 1 control point); defaults to `LillistMotion.base` duration. |
| `symbol` | func | `Packages/LillistUI/Sources/LillistUI/Theme/StatusGlyph.swift:10` | Returns the SF Symbol name for a Status; guaranteed non-nil for all Status cases. |
| `toHex` | func | `Packages/LillistUI/Sources/LillistUI/Theme/Color+Hex.swift:40` | Converts a SwiftUI Color to a 6-digit sRGB hex string with `#` prefix; returns nil when the color cannot be expressed in sRGB. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `solid` | func | `Packages/LillistUI/Sources/LillistUI/Theme/RainbowPalette.swift:66` | Sole factory for all six `Spectrum` color constants (purple, blue, cyan, green, lime, orange) at RainbowPalette.swift:55–63; every `RainbowGradient` preset, the confetti palette, and the `.rainbow` button gradient trace back here. A wrong bit-shift or channel ordering would corrupt the entire spectrum silently. |

## Relationships

- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.Color -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.GlassSurfaceModifier -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (calls)`
- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.RainbowToggleStyle -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (calls)`
- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.Size -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (calls)`
- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.accessibilityLabel -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.body -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.tint (calls)`
- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.clampBrightnessForContrastFloor -> Packages-LillistUI-Sources-LillistUI-Accessibility.hsbToRGB (calls)`
- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.clampBrightnessForContrastFloor -> Packages-LillistUI-Sources-LillistUI-Accessibility.relativeLuminance (calls)`
- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.clampBrightnessForContrastFloor -> Packages-LillistUI-Sources-LillistUI-Accessibility.wcagRatio (calls)`
- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.makeBody -> Apps-Lillist-macOS-Sources-Hotkey.toggle (calls)`
- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.registerIfNeeded -> Apps-Lillist-macOS-Sources-Hotkey.present (calls)`
- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.toHex -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`

## Type notes

All exported types are value types (enums and structs); no actor isolation is required at the type level. `GlassSurface` and `TagTint`/`TagTint.Resolved` are `Sendable` and `Equatable` — safe to cross actor boundaries and compare in tests (GlassSurface.swift:32, TagTint.swift:4–5).

`LillistFonts.registerIfNeeded()` is backed by `private static let registered` (LillistFonts.swift:38–52); Swift's lazy static initialization is thread-safe, so concurrent first-callers cannot double-register.

`RainbowPalette.dynamic(light:dark:)` (RainbowPalette.swift:29–47) produces a SwiftUI `Color` whose appearance resolution is deferred to a platform closure (`UIColor`/`NSColor` initializer with a traits/appearance callback); the `Color` value itself is safe to store and pass around without concern for scheme state at creation time.

`GlassSurfaceModifier` reads two `@Environment` keys — `\.accessibilityReduceTransparency` (system) and `\.reduceTransparencyOverride` (custom) — at SwiftUI body evaluation time on the main actor (GlassSurface.swift:132–133). The modifier is private; callers never interact with it directly.

`TagTint.resolved(in:)` (TagTint.swift:37–55) is a pure computation: no stored mutable state is mutated, no async work is done. It can safely be called on any actor, including from a background `Task` preparing display data.

## External deps

- AppKit — imported
- CoreText — imported
- LillistCore — imported
- SwiftUI — imported
- UIKit — imported

## Gotchas

GlassSurface.swift:141–151: On OS 26 the glass renderer self-handles Reduce Transparency; the modifier must NOT branch on `systemReduceTransparency` inside the `#available(iOS 26, macOS 26)` arm — double-handling fights the tuned system behavior. Only the pre-26 arm applies the reduce flag.

GlassSurface.swift:108–113: `glassGroup(spacing:)` is a complete no-op on pre-26 OS (the `else` branch returns `self` unchanged). Do not rely on it for layout spacing on older platforms.

Color+Hex.swift:9–18: `Color(hex:)` and `TagTint.init?(hex:)` both parse hex strings but are intentionally separate — `Color(hex:)` produces a raw SwiftUI Color for ColorPicker bindings; `TagTint.init?(hex:)` stores RGB for subsequent dark-mode desaturation and WCAG contrast-floor adjustment. Collapsing them would silently lose the tag tint logic.

GlassRowSpike.swift:1: The entire file is `#if DEBUG`. `GlassRowSpike` is a Wave 0 perf/legibility spike, not a production view. Its fan-in count reflects loop-generated body calls, not cross-file references.

LillistElevation.swift:13–15: The `.xs` level is a hard performance cap for repeating list-row cells; using `.sm` or above inside a `LazyVStack`/`LazyVGrid` is an explicit scroll-perf hazard documented in the spec.
