---
module: "Packages/LillistUI/Sources/LillistUI/Theme (chunk 2)"
summary: "Design tokens — spacing, radius, timing, semantic typography, drag-reorder constants, and tag tint default"
read_when: "Touching spacing, radius, timing, typography, drag-reorder visual constants, or tag tint defaults"
sources:
  - path: Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift
references_modules: [Packages-LillistUI-Sources-LillistUI-Theme-chunk-1, Packages-LillistUI-Sources-LillistUI-DragReorder, Packages-LillistUI-Sources-LillistUI-iOS-misc, Apps-Lillist-iOS-Sources-Settings, Apps-Lillist-macOS-Sources-Preferences]
generator: cartographer/1 model=claude-sonnet-4-6
---

# Module: Packages/LillistUI/Sources/LillistUI/Theme (chunk 2)

## Purpose

The single source of truth for Lillist's shared visual constants (Plan 14): every
spacing, corner-radius, gesture-timing, typography, drag-reorder, and shared string
value lives in a token enum here so callsites use a named token instead of a magic
number. Typography is *semantic* and Dynamic-Type-aware — tokens map to SwiftUI text
styles via `relativeTo:`, so user accessibility text-size settings keep scaling chrome
text. If these enums vanished, every UI surface would lose its consistent metrics and
lock font sizes to fixed pixels.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `LillistDragTokens` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift:104` | Namespace of drag-reorder visual constants (indicator/phantom colors, sizes, durations); callers must not hardcode any of these values |
| `LillistRadius` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift:29` | Corner-radius scale (`s`/`m`/`l`/`xl`/`cube`); use with `.continuous` corner style at callsites |
| `LillistSpacing` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift:16` | Spacing scale (`xs`–`xxl`) for padding, stack spacing, and frame insets; replace all raw CGFloat padding literals |
| `LillistTiming` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift:43` | Gesture-timing constants; `longPress` (0.4 s) used by status indicator and FAB |
| `LillistTokens` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift:94` | Shared string constants; `defaultTagTintHex` is the canonical default tag-tint colour |
| `LillistTypography` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift:53` | Semantic `Font` tokens (Plus Jakarta Sans) each relative to a Dynamic Type style; never use `.system(size:)` for app chrome |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `LillistTypography.jakarta` | func | `Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift:83` | Builds every typography token: calls `LillistFonts.registerIfNeeded()` and falls back to the system style when registration fails — all typography correctness flows through here |

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

## Gotchas

- `LillistDragTokens.longPressDuration` (0.3 s at `Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift:148`) differs from `LillistTiming.longPress` (0.4 s at `Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift:44`); the drag system uses the shorter threshold to distinguish drag pickup from a status-indicator long-press — do not unify them without updating both consumers.
