---
module: "Packages/LillistUI/Sources/LillistUI/Theme (chunk 2)"
summary: "Shared design tokens — spacing, radius, timing, semantic typography, and drag-reorder constants"
read_when: "Touching spacing, radius, timing, typography, or drag-reorder visual constants"
sources:
  - path: Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift
    blob: 4641bb3810568f46beec79e5477085395c202892
references_modules: [Packages-LillistUI-Sources-LillistUI-Theme-chunk-1, Packages-LillistUI-Sources-LillistUI-DragReorder, Packages-LillistUI-Sources-LillistUI-iOS-misc, Apps-Lillist-iOS-Sources-Settings, Apps-Lillist-macOS-Sources-Preferences]
generator: cartographer/1
baseline: 34dfea7772679dbabc08fabd6fbba53f6ad5856b
---

# Module: Packages/LillistUI/Sources/LillistUI/Theme (chunk 2)

## Purpose

The single source of truth for Lillist's shared visual constants (Plan 14): every
spacing, corner-radius, gesture-timing, and typography value lives in a token enum
here so callsites use a named token instead of a magic number. The design intent is
that typography is *semantic* and Dynamic-Type-aware — tokens map to SwiftUI text
styles via `relativeTo:`, so user accessibility text-size settings keep scaling
chrome text. If these enums vanished, every UI surface would lose its consistent
metrics and lock font sizes to fixed pixels.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `LillistDragTokens` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift:104` | Namespace of drag-reorder visual constants (indicator/phantom colors, sizes, durations) |
| `LillistRadius` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift:29` | Corner-radius scale (`s`/`m`/`l`/`xl`/`cube`); use with `.continuous` style |
| `LillistSpacing` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift:16` | Spacing scale (`xs`–`xxl`) for padding, stack spacing, frame insets |
| `LillistTiming` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift:43` | Gesture-timing constants; `longPress` is the hold duration before long-press fires |
| `LillistTokens` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift:94` | String constants for app preferences UI; holds `defaultTagTintHex` |
| `LillistTypography` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift:53` | Semantic `Font` tokens (Plus Jakarta Sans) each relative to a Dynamic Type style |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `LillistTypography.jakarta` | func | `Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift:83` | Builds every typography token: custom Jakarta face or system fallback when registration fails |

## Relationships

- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-2.LillistTypography -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.LillistFonts (calls)`
- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-2.LillistDragTokens -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.RainbowPalette (reads)`
- `Packages-LillistUI-Sources-LillistUI-DragReorder.DragOverlay -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-2.LillistDragTokens (reads)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.FloatingAddButton -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-2.LillistTiming (reads)`
- `Apps-Lillist-iOS-Sources-Settings.GeneralSection -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-2.LillistTokens (reads)`
- `Apps-Lillist-macOS-Sources-Preferences.GeneralPane -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-2.LillistTokens (reads)`

## Type notes

All public types are caseless `enum` namespaces of `public static let` constants —
pure value tokens, no instances, no state, no isolation concerns. `LillistTypography`
tokens are evaluated lazily as `static let`; `jakarta` calls
`LillistFonts.registerIfNeeded()` so the first font-token access triggers face
registration and every token degrades to its `fallback` system style if registration
fails (`Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift:87`). `LillistDragTokens`
colors are derived from `RainbowPalette` functional hues — `indicatorColor` is
focus-blue, `rejectionColor` is deep action-orange (Rainbow Logic has no red),
at `Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift:108` and `:112`.

## External deps

- SwiftUI — `Font`, `Color`, `CGFloat`, `TimeInterval` token value types
- Foundation — base value types underlying the token scales
