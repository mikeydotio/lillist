---
module: "Packages/LillistUI/Sources/LillistUI/Theme (chunk 1)"
summary: "Rainbow Glass design tokens — colors, hues, gradients, glass seam, button/toggle styles, status/sync/tag palettes"
read_when: "Theme colors & glass tokens"
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
references_modules: [Packages-LillistUI-Sources-LillistUI-Accessibility, Packages-LillistUI-Sources-LillistUI-Theme-chunk-2, Packages-LillistUI-Sources-LillistUI-Components, Packages-LillistUI-Sources-LillistUI-iOS-misc, Packages-LillistUI-Sources-LillistUI-misc, Packages-LillistCore-Sources-LillistCore-Model, Apps-Lillist-macOS-Sources-Preferences]
generator: cartographer/1
baseline: 34dfea7772679dbabc08fabd6fbba53f6ad5856b
---

# Module: Packages/LillistUI/Sources/LillistUI/Theme (chunk 1)

## Purpose

The Rainbow Glass design-token layer: every color, hue, gradient, glass
surface, motion curve, button/toggle style, and status/sync/tag mapping that
both apps and the extensions consume. The unifying idea is that color is
*functional* (tints map to meaning, never decoration) and all OS-26 Liquid
Glass routes through one seam. If this module vanished, components would have
no semantic palette and no availability-gated glass to render against.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `Color.init?(hex:)` | init | `Packages/LillistUI/Sources/LillistUI/Theme/Color+Hex.swift:23` | Parse 6-digit (or 3-digit) hex into a raw `Color`; nil on parse fail |
| `Color.toHex()` | func | `Packages/LillistUI/Sources/LillistUI/Theme/Color+Hex.swift:40` | Render a `Color` as `#RRGGBB`; nil if not sRGB-reducible |
| `GlassSurface` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/GlassSurface.swift:32` | The glass role taxonomy (panel/toast/control/card/statusTinted) |
| `LillistColor` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/LillistColor.swift:11` | Semantic surface/text/border colors; the only color API components reach for |
| `LillistElevation` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/LillistElevation.swift:17` | Two-layer shadow levels; `.xs` is the hard cap for repeating rows |
| `LillistFonts` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/Fonts/LillistFonts.swift:22` | Registers bundled Plus Jakarta Sans for the process |
| `LillistMotion` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/LillistMotion.swift:12` | Motion durations + `squish`/`easeOut` brand curves |
| `RainbowButtonStyle` | struct | `Packages/LillistUI/Sources/LillistUI/Theme/RainbowButtonStyle.swift:16` | Pill button style; pick variant by function via `.rainbow(_:size:)` |
| `RainbowGradient` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/RainbowGradient.swift:8` | The reserved full-spectrum gradients (vertical/horizontal/halo) |
| `RainbowPalette` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/RainbowPalette.swift:22` | Raw hex data layer + `dynamic(...)` factory + functional hues |
| `RainbowToggleStyle` | struct | `Packages/LillistUI/Sources/LillistUI/Theme/RainbowToggleStyle.swift:14` | Flat-track switch style; `.rainbow` token applies it |
| `StatusGlyph` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/StatusGlyph.swift:9` | SF Symbol + localized a11y label per `Status` |
| `StatusPalette` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/StatusPalette.swift:20` | `color`/`ink`/`fill` per `Status`; never use `color` as text |
| `TagTint` | struct | `Packages/LillistUI/Sources/LillistUI/Theme/TagTint.swift:4` | Tag color value; `resolved(in:)` applies dark desaturation + contrast floor |
| `View.glassSurface(_:in:)` | func | `Packages/LillistUI/Sources/LillistUI/Theme/GlassSurface.swift:98` | Apply a glass surface with full pre-26 degradation |
| `View.glassGroup(spacing:)` | func | `Packages/LillistUI/Sources/LillistUI/Theme/GlassSurface.swift:108` | Group overlapping glass so it blends; no-op below OS 26 |
| `View.glassElevation(_:)` | func | `Packages/LillistUI/Sources/LillistUI/Theme/GlassSurface.swift:122` | Yield shadow to glass on OS 26; fall back to `rainbowShadow` below |
| `View.rainbowShadow(_:)` | func | `Packages/LillistUI/Sources/LillistUI/Theme/LillistElevation.swift:45` | Two-layer soft drop shadow at the given elevation |
| `ShapeStyle.rainbowWell` | static var | `Packages/LillistUI/Sources/LillistUI/Theme/LillistElevation.swift:67` | Inset-well fill for sunken fields |
| `SyncIndicator.color` (ext) | var | `Packages/LillistUI/Sources/LillistUI/Theme/SyncPalette.swift:27` | Canonical tint per sync state; recency-gated idle |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `RainbowPalette.dynamic` | func | `Packages/LillistUI/Sources/LillistUI/Theme/RainbowPalette.swift:29` | The (light,dark) → trait-resolving `Color` factory every color is built on |
| `RainbowPalette.Functional` | struct | `Packages/LillistUI/Sources/LillistUI/Theme/RainbowPalette.swift:83` | `base`/`soft`/`ink`/`deep` axis; `base` is never text, `ink` is |
| `RainbowPalette.Spectrum` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/RainbowPalette.swift:54` | Six scheme-invariant spectrum stops feeding `RainbowGradient` |
| `GlassSurfaceModifier` | struct | `Packages/LillistUI/Sources/LillistUI/Theme/GlassSurface.swift:131` | The `#available` gate + degradation logic behind `glassSurface` |
| `TagTint.resolved(in:)` | func | `Packages/LillistUI/Sources/LillistUI/Theme/TagTint.swift:37` | Dark desaturation + 4.5:1 contrast-floor iteration for tag chips |

## Relationships

- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.RainbowButtonStyle -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-2.LillistTypography (reads)`
- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.RainbowButtonStyle -> Packages-LillistUI-Sources-LillistUI-Accessibility.reduceMotionOverride (reads)`
- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.GlassSurfaceModifier -> Packages-LillistUI-Sources-LillistUI-Accessibility.reduceTransparencyOverride (reads)`
- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.TagTint -> Packages-LillistUI-Sources-LillistUI-Accessibility.ContrastMath (calls)`
- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.StatusGlyph -> Packages-LillistCore-Sources-LillistCore-Model.Status (reads)`
- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.StatusPalette -> Packages-LillistCore-Sources-LillistCore-Model.Status (reads)`
- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.SyncPalette -> Packages-LillistUI-Sources-LillistUI-misc.SyncIndicator (extends)`
- `Packages-LillistUI-Sources-LillistUI-Components.StatusIndicatorView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.StatusGlyph (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components.TagChipView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.TagTint (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components.SyncStatusDotView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.SyncIndicator (reads)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.FloatingAddButton -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.glassSurface (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.SyncStatusBadge -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.SyncIndicator (reads)`
- `Apps-Lillist-macOS-Sources-Preferences.PreferencesWindow -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.RainbowToggleStyle (calls)`

## Type notes

`GlassSurface` is `Sendable, Equatable`; `RainbowButtonStyle` and
`RainbowToggleStyle` carry value config (variant/size/onColor) and read
accessibility overrides from the SwiftUI environment, so behavior is
MainActor-bound at render time. `LillistFonts.registered` is a `static let`
one-shot — thread-safe, runs at most once; `registerIfNeeded()` only reads it
(`Packages/LillistUI/Sources/LillistUI/Theme/Fonts/LillistFonts.swift:36`).
Colors are code-defined (not asset-catalog) so `RainbowPaletteTests` can pin
each per scheme and one source serves both apps and both extensions. Invariant:
a functional hue's `base` is an object-fill color and never text — text uses
`ink` (`Packages/LillistUI/Sources/LillistUI/Theme/RainbowPalette.swift:83`);
`StatusPalette.color` carries the same warning
(`Packages/LillistUI/Sources/LillistUI/Theme/StatusPalette.swift:23`).

`SyncIndicator` is defined in `Packages-LillistUI-Sources-LillistUI-misc`
(`Packages/LillistUI/Sources/LillistUI/Status/SyncStatusMonitor.swift`);
`SyncPalette.swift` adds the `color`, `systemImage`, and
`differentiatedSystemImage` properties via extension.

## External deps

- SwiftUI — `Color`, `Material`, `Glass`/`glassEffect`, `ButtonStyle`/`ToggleStyle`
- CoreText — `CTFontManagerRegisterFontURLs` for process font registration
- UIKit / AppKit — `UIColor`/`NSColor` hex initializers and dynamic-color closures

## Gotchas

- OS-26 Liquid Glass self-handles Reduce Transparency; `GlassSurfaceModifier` deliberately does NOT branch on it on OS 26 (`Packages/LillistUI/Sources/LillistUI/Theme/GlassSurface.swift:138`).
- `prefersSolidFallback` keeps tinted fills (FAB, status, card) solid (not translucent) on pre-26 OS (`Packages/LillistUI/Sources/LillistUI/Theme/GlassSurface.swift:53`).
- `Color(hex:)` and `TagTint.init?(hex:)` are intentionally distinct — do not collapse them (`Packages/LillistUI/Sources/LillistUI/Theme/Color+Hex.swift:13`).
- `GlassRowSpike` is a DEBUG-only Wave 0 spike harness, slated for deletion (`Packages/LillistUI/Sources/LillistUI/Theme/GlassRowSpike.swift:4`).
- Repeating list rows must never exceed `.xs` elevation — a scroll-perf rule (`Packages/LillistUI/Sources/LillistUI/Theme/LillistElevation.swift:17`).
