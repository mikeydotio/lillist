---
module: Packages/LillistUI/Sources/LillistUI/Recurrence
summary: "Form-based recurrence editor: SwiftUI view, value-type view model, and localized formatter for repeat rules."
read_when: "Touching recurrence editing UI"
sources:
  - path: Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift
    blob: 0a45e3b6f13912b4cb5c8a1b942759a9af126108
  - path: Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorViewModel.swift
    blob: 222e0124667e98be7e37bdbbe336ae536573639c
  - path: Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceSummary.swift
    blob: 4431a7f040ca523f4e1aad880d5ae5e465d8f2ab
  - path: Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceSummaryFormatter.swift
    blob: c6541163a9cf3720b3b08e4e1fd985c4506fc743
references_modules: [Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistCore-Sources-LillistCore-Recurrence, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistUI/Sources/LillistUI/Recurrence

## Purpose

Provides the complete recurrence editing surface for LillistUI: a form-based SwiftUI view, a value-type view model that holds all transient editor state, a structured intermediate summary type, and a localized string formatter. The central design decision is a clean separation between the mutable editor state (RecurrenceEditorViewModel) and the immutable core domain type (RecurrenceRule) — build() is the single gate converting form state into a storable rule. Without this module, tasks have no UI for configuring repeat schedules.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `Mode` | enum | `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorViewModel.swift:11` | Discriminates .calendar (fixed-interval RRULE-style) from .afterCompletion (relative to task completion); Hashable, Sendable, CaseIterable. |
| `RecurrenceEditorView` | struct | `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift:10` | Callers bind a RecurrenceEditorViewModel and optional onCommit/onCancel closures; Save invokes onCommit(viewModel.build()), Cancel invokes onCancel. |
| `RecurrenceEditorViewModel` | struct | `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorViewModel.swift:10` | Initialize from an optional RecurrenceRule (round-trip fidelity); mutate public fields via SwiftUI bindings; call build() to recover a RecurrenceRule? on commit. |
| `RecurrenceSummary` | enum | `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceSummary.swift:10` | Three-case Sendable enum (.never, .calendar, .afterCompletion) representing all view-model states; pass to RecurrenceSummaryFormatter.string(for:) for display. |
| `RecurrenceSummaryFormatter` | enum | `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceSummaryFormatter.swift:22` | Caseless namespace enum; callers invoke only string(for:locale:) — no instantiation expected or possible. |
| `build` | func | `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorViewModel.swift:75` | Returns nil when repeats==false; otherwise yields a CalendarRule or AfterCompletionRule, clamping interval to >=1 and emitting byDay in Mon-Sun order. |
| `string` | func | `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceSummaryFormatter.swift:24` | Returns a localized string for any RecurrenceSummary; interval==1 always yields singular form ("Every day"), >=2 yields pluralized form with the count. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `index` | func | `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift:157` | Maps Weekday enum cases to 0-based Sunday-first indices matching Calendar.standaloneWeekdaySymbols (which is always Sunday-first regardless of locale). Called by label(for:) — the highest-fan-in private function. Wrong indices silently produce mismatched localized day names with no compile-time signal. (Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift:157-167) |
| `label` | func | `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift:145` | Bridges Weekday enum cases to system-localized day names via Calendar.standaloneWeekdaySymbols, with fallback to English for unexpected calendar configurations. Used in the weekly-day toggle ForEach; incorrect output here would silently mislabel every weekday toggle in the editor. (Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift:145-155) |

## Relationships

- `Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceEditorView -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceEditorView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.accessibilityLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-Recurrence.build -> Packages-LillistCore-Sources-LillistCore-Recurrence.AfterCompletionRule (calls)`
- `Packages-LillistUI-Sources-LillistUI-Recurrence.build -> Packages-LillistCore-Sources-LillistCore-Recurrence.CalendarRule (calls)`
- `Packages-LillistUI-Sources-LillistUI-Recurrence.dayCell -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-Recurrence.dayCell -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.accessibilityLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-Recurrence.dayCell -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.fill (calls)`
- `Packages-LillistUI-Sources-LillistUI-Recurrence.label -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-Recurrence.string -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`

## Type notes

RecurrenceEditorViewModel is a plain Equatable struct with all public var fields — no actor isolation, designed for @State and @Binding use (Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorViewModel.swift:10). RecurrenceSummary is Equatable+Sendable, safe to cross actor boundaries (Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceSummary.swift:10). RecurrenceSummaryFormatter is a caseless enum used purely as a namespace (Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceSummaryFormatter.swift:22). RecurrenceEditorView is @MainActor-isolated via View conformance and holds only a @Binding — no @State, no async calls (Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift:10-23). The taskAnchorDate field on the view model propagates the task's own start/deadline into the editor so the default end-date for the 'End by date' toggle is anchored to the task, not today (Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorViewModel.swift:27-32).

## External deps

- Foundation — imported
- LillistCore — imported
- SwiftUI — imported

## Gotchas

Pluralization in RecurrenceSummaryFormatter is done by explicit interval==1 branching, not .xcstrings plural variations. SwiftPM copies .xcstrings verbatim without running xcstringstool, so compiled plural-variation rules are inert under `swift test`; the branching keeps English grammatically correct in both SPM and Xcode builds. (Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceSummaryFormatter.swift:13-21)
