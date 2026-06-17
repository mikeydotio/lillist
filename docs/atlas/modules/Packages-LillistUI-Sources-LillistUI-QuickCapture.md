---
module: Packages/LillistUI/Sources/LillistUI/QuickCapture
summary: "Quick Capture text parsing, the macOS hotkey panel view, and the canonical date-token list"
read_when: "Quick Capture parsing"
sources:
  - path: Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureDateSuggestions.swift
    blob: 7cf0c3990da9d39095ebc898d37ae926931afcfc
  - path: Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureParser.swift
    blob: 68c8306a5b319e84ca27198e96b7078aa75fd5be
  - path: Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureView.swift
    blob: 52746892ca8e7bf4b3184010c1a64b2d45c29f3a
references_modules: [Packages-LillistUI-Sources-LillistUI-Components, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1, Packages-LillistUI-Sources-LillistUI-Theme-chunk-2, Packages-LillistUI-Sources-LillistUI-iOS-misc, Packages-LillistUI-Sources-LillistUI-Editor]
generator: cartographer/1
baseline: 34dfea7772679dbabc08fabd6fbba53f6ad5856b
---

# Module: Packages/LillistUI/Sources/LillistUI/QuickCapture

## Purpose

The shared Quick Capture primitives behind both platforms' fast task entry.
`QuickCaptureParser` is the single tokenizer for the `#tag` / `^date` mini-syntax
(design Section 7), so the macOS panel, the iOS dialog, and their hosts all derive
title/tags/dateToken the same way. `QuickCaptureView` is the macOS hotkey panel's
pure-SwiftUI body; `QuickCaptureDateSuggestions` is the canonical date-token chip
list. If this module vanished, both capture surfaces would diverge on how raw text
becomes a task and the macOS panel would lose its UI.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `QuickCaptureDateSuggestions` | enum | `Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureDateSuggestions.swift:23` | Namespace for the canonical date-token list; single source of truth for chip tokens |
| `QuickCaptureDateSuggestions.default` | static let | `Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureDateSuggestions.swift:24` | Ordered English date tokens (`today`, `tomorrow`, `+3d`, `+1w`) callers render as `^token` chips |
| `QuickCaptureParser` | enum | `Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureParser.swift:5` | Stateless namespace for the capture-text tokenizer |
| `QuickCaptureParser.Result` | struct | `Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureParser.swift:6` | Value-type DTO: `title`, `tags`, optional `dateToken`; `Equatable`, `Sendable`, explicit public init |
| `QuickCaptureParser.parse(_:)` | static func | `Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureParser.swift:18` | Splits on spaces; `#x`→tag, `^x`→dateToken (last wins), rest→title; never throws |
| `QuickCaptureView` | struct | `Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureView.swift:5` | macOS panel body; `text` binding, `onSubmit(Result)`, `onCancel`; parses inline on each render |

## Load-bearing internals

(none — the module is entirely public surface.)

## Relationships

- `Packages-LillistUI-Sources-LillistUI-QuickCapture.QuickCaptureView -> Packages-LillistUI-Sources-LillistUI-QuickCapture.QuickCaptureParser.parse (calls)`
- `Packages-LillistUI-Sources-LillistUI-QuickCapture.QuickCaptureView -> Packages-LillistUI-Sources-LillistUI-QuickCapture.QuickCaptureDateSuggestions (reads)`
- `Packages-LillistUI-Sources-LillistUI-QuickCapture.QuickCaptureView -> Packages-LillistUI-Sources-LillistUI-Components.TagChipView (calls)`
- `Packages-LillistUI-Sources-LillistUI-QuickCapture.QuickCaptureView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.glassSurface (calls)`
- `Packages-LillistUI-Sources-LillistUI-QuickCapture.QuickCaptureView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.LillistColor (reads)`
- `Packages-LillistUI-Sources-LillistUI-QuickCapture.QuickCaptureView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-2.LillistTypography (reads)`
- `Packages-LillistUI-Sources-LillistUI-QuickCapture.QuickCaptureView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-2.LillistSpacing (reads)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.QuickCaptureDialog -> Packages-LillistUI-Sources-LillistUI-QuickCapture.QuickCaptureParser.parse (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorModel -> Packages-LillistUI-Sources-LillistUI-QuickCapture.QuickCaptureParser.parse (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorView -> Packages-LillistUI-Sources-LillistUI-QuickCapture.QuickCaptureParser.parse (calls)`

## Type notes

`QuickCaptureParser` and `QuickCaptureDateSuggestions` are caseless enums used as
stateless namespaces — no instances, no ownership. `Result` is a pure value DTO
(`Equatable`, `Sendable`) with a hand-written public init so callers outside the
module can construct it; it carries no Core Data type. `QuickCaptureView` recomputes
`QuickCaptureParser.parse(text)` on every `body` render
(`Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureView.swift:21`) rather
than caching — the parse is cheap and keeps the chip/preview row in lockstep with the
field. The view is pure SwiftUI for snapshot testing; the macOS app target wraps it in
an `NSPanel` host. Parsing produces only a `dateToken` string — actual date resolution
is the host/CLI layer's job, not this module's.

## External deps

- SwiftUI — `QuickCaptureView` is a `View`; the parser/suggestions use only Foundation.

## Gotchas

- Every token in `QuickCaptureDateSuggestions.default` must round-trip through
  `LillistCore.RelativeDate.parse(_:)`; adding a token here without extending the
  parser yields a tappable chip the resolver can't resolve
  (`Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureDateSuggestions.swift:12`).
- The iOS surface no longer renders the suggestion chip row (Plan 22 dialog redesign);
  the list is kept only as the source of truth for a future iOS resurrection
  (`Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureDateSuggestions.swift:6`).
- Tokens stay English at the data layer even though chip labels may localize their
  display; label and parser token are presently the same string
  (`Packages/LillistUI/Sources/LillistUI/QuickCapture/QuickCaptureDateSuggestions.swift:17`).
- `QuickCaptureView` is no longer hosted by `QuickCapturePanelController` — that controller
  now hosts `TaskEditorView` from the Editor module. The macOS panel comment in the view
  doc-comment (`QuickCaptureView.swift:3`) is historical; the live host is `TaskEditorView`.
