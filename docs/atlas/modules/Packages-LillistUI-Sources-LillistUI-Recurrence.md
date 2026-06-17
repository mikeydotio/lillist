---
module: Packages/LillistUI/Sources/LillistUI/Recurrence
summary: SwiftUI recurrence-rule editor plus a value-type summary it renders to localized text
read_when: Touching recurrence editing UI, recurrence summary display, or RecurrenceRule binding
sources:
  - path: Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift
  - path: Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorViewModel.swift
  - path: Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceSummary.swift
  - path: Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceSummaryFormatter.swift
references_modules:
  - Packages-LillistCore-Sources-LillistCore-Model
  - Packages-LillistUI-Sources-LillistUI-Theme-chunk-1
  - Packages-LillistUI-Sources-LillistUI-Editor
generator: cartographer/1 model=claude-sonnet-4-6
---

# Module: Packages/LillistUI/Sources/LillistUI/Recurrence

## Purpose

The cross-platform UI for editing a LillistCore `RecurrenceRule`. A mutable
`RecurrenceEditorViewModel` adapts the optional immutable rule into the many
mutable fields SwiftUI form controls bind to, and `build()` re-synthesizes the
rule on commit. Display follows a deliberate data/wording split: the view-model
emits a non-localized `RecurrenceSummary` value, which `RecurrenceSummaryFormatter`
turns into localized, correctly-pluralized text at the View layer — so the value
types never embed English or pluralization rules.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `RecurrenceEditorView` | struct | `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift:10` | Form editor bound to a view-model; `onCommit` receives the synthesized `RecurrenceRule?` |
| `RecurrenceEditorViewModel` | struct | `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorViewModel.swift:10` | Mutable `@State`-friendly mirror of a rule; `init(rule:taskAnchorDate:)`, `build()`, `summary` |
| `RecurrenceEditorViewModel.Mode` | enum | `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorViewModel.swift:11` | `.calendar` / `.afterCompletion` schedule-style selector |
| `RecurrenceSummary` | enum | `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceSummary.swift:10` | Non-localized recurrence description: `.never` / `.calendar` / `.afterCompletion` |
| `RecurrenceSummaryFormatter` | enum | `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceSummaryFormatter.swift:22` | Namespace for `string(for:locale:)` |
| `RecurrenceSummaryFormatter.string(for:locale:)` | func | `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceSummaryFormatter.swift:24` | Renders a `RecurrenceSummary` to localized, pluralized text via `bundle: .module` |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `RecurrenceEditorViewModel.build()` | func | `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorViewModel.swift:75` | The commit path; converts editor state back to a `RecurrenceRule?`, preserving Mon→Sun `byDay` order |
| `RecurrenceEditorViewModel.summary` | var | `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorViewModel.swift:103` | The single producer of `RecurrenceSummary`, paired with the formatter |
| `defaultUntil()` | func | `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift:210` | Frequency-scaled, anchor-relative default end-date so "End by date" isn't 30 days from today |
| `label(for:)` | func | `Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift:145` | Weekday toggle titles from `Calendar.standaloneWeekdaySymbols`, with English fallback |

## Relationships

- `Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceEditorViewModel -> Packages-LillistCore-Sources-LillistCore-Model.RecurrenceRule (owns)`
- `Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceEditorViewModel -> Packages-LillistCore-Sources-LillistCore-Model.Weekday (reads)`
- `Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceSummary -> Packages-LillistCore-Sources-LillistCore-Model.RecurrenceRule (reads)`
- `Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceEditorView -> Packages-LillistCore-Sources-LillistCore-Model.Weekday (reads)`
- `Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceEditorView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.RainbowPalette (reads)`
- `Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceEditorView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.LillistColor (reads)`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorView -> Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceEditorView (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorModel -> Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceEditorViewModel (owns)`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorView -> Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceSummaryFormatter (calls)`

## Type notes

`RecurrenceEditorViewModel` is a value type meant to be held in `@State`; the
View binds to it via `@Binding` (`Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift:11`).
`init(rule:)` flattens the rule's three cases into independent fields, so
state for one mode survives switching to another and back. `build()` is the
inverse and is the only place the inverse mapping lives — including the
`max(1, interval)` clamp and the `byMonthDay`/`bySetPos` empty-set→nil
normalization. The `.afterCompletion` summary divides seconds by 86,400 to
report whole days; `defaultUntil()` and the rest of the editor route all date
math through `Calendar`, never `addingTimeInterval`.

## External deps

- SwiftUI — `Form`, `Picker`, `Toggle`, `DatePicker`, `LazyVGrid`, `@Binding`
- Foundation — `Calendar`, `Locale`, `Date`, `TimeInterval`, `String(localized:bundle:)`

## Gotchas

- `RecurrenceSummaryFormatter` avoids `.xcstrings` plural-variation keys: SwiftPM copies `.xcstrings` verbatim without running `xcstringstool`, so plural variants are inert under `swift test`. Singular vs. plural is resolved by branching on `interval == 1` / `days == 1` with separate literal keys. (`Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceSummaryFormatter.swift:14`)
- `build()` preserves Monday-first ordering for `byDay` by filtering `Weekday.allCases` rather than sorting the set. (`Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorViewModel.swift:83`)
- `defaultUntil()` anchors on `taskAnchorDate` (not `Date()`) so tasks scheduled far in the future receive a proportionate end-date default. (`Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift:211`)
