---
module: "Packages/LillistUI/Sources/LillistUI/Theme (chunk 2)"
summary: "Design tokens: spacing, radius, timing, Plus Jakarta Sans typography, and drag-reorder visual constants"
read_when: "Touching spacing, radius, or timing tokens"
sources:
  - path: Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift
    blob: bb3bb6be974550ee90a1512d23f6aaf5682b65bb
references_modules: [Packages-LillistUI-Sources-LillistUI-DragReorder, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistUI/Sources/LillistUI/Theme (chunk 2)

## Purpose

Tokens.swift is the single source of truth for all shared visual constants in LillistUI: spacing scale, corner-radius scale, gesture-timing constants, Plus Jakarta Sans typography, reusable string tokens, and drag-reorder visual parameters. It exists to prevent magic numbers from spreading across views and to enforce Rainbow Logic design-system semantics at the token level. Without it, callsites would diverge: spacing values would drift, font stacks would mix system and custom faces, and the drag system's visual tuning would scatter across multiple files.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `LillistDragTokens` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift:104` | Static constants governing all drag-reorder visual behavior; read any property for pixel values, timing, and color — no instances, no side effects except indicatorColor's lazy RainbowPalette init. |
| `LillistRadius` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift:29` | Static CGFloat corner-radius scale (s/m/l/xl/cube); pair with .continuous corner style; Capsule shapes use Capsule(), not these tokens. |
| `LillistSpacing` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift:16` | Static CGFloat spacing scale (xs=4 through xxl=40) for padding, stack gaps, and frame insets; read-only, no side effects. |
| `LillistTiming` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift:43` | Single TimeInterval constant: longPress=0.4s for StatusIndicatorView and FloatingAddButton gestures; drag-to-reorder uses LillistDragTokens.longPressDuration=0.3s instead. |
| `LillistTokens` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift:94` | Static string constants shared between iOS and macOS preferences UI; currently exposes defaultTagTintHex to avoid duplication between GeneralSection and GeneralPane. |
| `LillistTypography` | enum | `Packages/LillistUI/Sources/LillistUI/Theme/Tokens.swift:53` | Semantic Font tokens for Plus Jakarta Sans scaled to Dynamic Type styles; token access triggers font registration and falls back to the system style if registration fails — callers need not guard the result. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-2.LillistDragTokens -> Packages-LillistUI-Sources-LillistUI-DragReorder.indicator (calls)`
- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-2.jakarta -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.registerIfNeeded (reads)`

## Type notes

All six enums are caseless namespaces of static let/func members — no instances, no allocation, no actor isolation. LillistTypography's static Font properties are initialized lazily on first access via the private jakarta factory (Tokens.swift:83-90), which calls LillistFonts.registerIfNeeded() on every invocation; the underlying font registration is one-shot (static let registered in LillistFonts). LillistDragTokens.indicatorColor references RainbowPalette.focusBlue.base (Tokens.swift:108), so that palette's static init runs on first drag-reorder use. All other tokens are plain CGFloat/TimeInterval/String literals with no side effects.

## External deps

- Foundation — imported
- SwiftUI — imported

## Gotchas

Two distinct long-press durations coexist: LillistTiming.longPress=0.4s (StatusIndicatorView/FAB) and LillistDragTokens.longPressDuration=0.3s (drag pickup) — editing one does not affect the other (Tokens.swift:44, Tokens.swift:132). LillistTypography.floatingAddGlyph uses the system font (.title.weight(.semibold)), not Plus Jakarta Sans — it is the sole non-Jakarta token in LillistTypography (Tokens.swift:79). LillistDragTokens.phantomLiftedScale=1.0 makes the lift-transition inverse-scale composition effectively identity; the math is retained so reintroducing a shrink animates correctly rather than popping (Tokens.swift:113-115).
