---
module: Packages/LillistUI/Sources/LillistUI/QuickCapture
summary: "#tag/^date parser + macOS NSPanel view for single-field fast task capture"
read_when: "Touching Quick Capture or #tag/^date parser"
sources:
  - path: Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureDateSuggestions.swift
    blob: 7cf0c3990da9d39095ebc898d37ae926931afcfc
  - path: Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureParser.swift
    blob: 68c8306a5b319e84ca27198e96b7078aa75fd5be
  - path: Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureView.swift
    blob: 52746892ca8e7bf4b3184010c1a64b2d45c29f3a
references_modules: [Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistUI-Sources-LillistUI-Components-chunk-1, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistUI/Sources/LillistUI/QuickCapture

## Purpose

Quick Capture is the lightweight task-input subsystem: a stateless parser that splits free-text into a title, zero-or-more `#tag` tokens, and an optional `^date` token, plus a pure-SwiftUI panel view that surfaces the parse result live as the user types. The parser (`QuickCaptureParser.parse`) is the authoritative decoder of Lillist's `#tag ^date` mini-syntax and is called from the macOS hotkey panel, App Intents, and the CLI alike. Removing this module would break all fast-add entry points across the system.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `QuickCaptureDateSuggestions` | enum | `Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureDateSuggestions.swift:23` | Provides the canonical list of `^date` chip tokens; every entry must round-trip through `LillistCore.RelativeDate.parse` or it produces an unresolvable chip. |
| `QuickCaptureParser` | enum | `Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureParser.swift:5` | Stateless namespace; cannot be instantiated; exposes only `parse` and the `Result` type; no side effects. |
| `QuickCaptureView` | struct | `Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureView.swift:5` | Pure-presenter SwiftUI view; caller owns the `@Binding` text state; `onSubmit` delivers the parsed Result; `onCancel` handles dismissal; no @State or side effects inside. |
| `Result` | struct | `Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureParser.swift:6` | Equatable, Sendable value type; callers may compare instances and pass across actor boundaries without bridging. |
| `parse` | func | `Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureParser.swift:18` | Always returns a Result; never throws or returns nil; `#word` → tag, `^word` → dateToken (last occurrence wins), remaining words joined as title. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

- `Packages-LillistUI-Sources-LillistUI-QuickCapture.QuickCaptureView -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-QuickCapture.QuickCaptureView -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1.TagChipView (calls)`
- `Packages-LillistUI-Sources-LillistUI-QuickCapture.QuickCaptureView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.accessibilityLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-QuickCapture.QuickCaptureView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.fill (calls)`
- `Packages-LillistUI-Sources-LillistUI-QuickCapture.QuickCaptureView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.glassSurface (calls)`
- `Packages-LillistUI-Sources-LillistUI-QuickCapture.QuickCaptureView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.rainbow (calls)`
- `Packages-LillistUI-Sources-LillistUI-QuickCapture.parse -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`

## Type notes

`QuickCaptureParser` is a caseless enum used as a namespace — it cannot be instantiated (`Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureParser.swift:5`). `QuickCaptureParser.Result` is `Equatable` and `Sendable`, so parse results may be compared and safely crossed into non-MainActor contexts (`Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureParser.swift:6`). `QuickCaptureView` is `@MainActor`-isolated via its `View` conformance; it holds a `@Binding` whose state is owned by the caller (the macOS app target's panel controller), not the view itself (`Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureView.swift:5-8`). `QuickCaptureDateSuggestions` is also a caseless enum namespace; the `default` array is the sole source of truth for chip tokens on both platforms (`Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureDateSuggestions.swift:23-29`).

## External deps

- Foundation — imported
- SwiftUI — imported

## Gotchas

iOS dropped the date-suggestion chip row in Plan 22; `QuickCaptureDateSuggestions.default` survives as the sole source of truth for macOS chip rendering and for any future iOS revival — adding a token there without extending `LillistCore.RelativeDate.parse` produces a tappable chip the parser cannot resolve (`Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureDateSuggestions.swift:15`). The `.glassSurface(.panel, ...)` call requires the hosting NSPanel to be non-opaque; that responsibility is noted in a comment pointing to `QuickCapturePanelController` (`Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureView.swift:86-88`).
