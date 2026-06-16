---
module: Packages/LillistUI/Sources/LillistUI/Recurrence
summary: "SwiftUI recurrence-rule editor plus a value-type summary it renders to localized text"
read_when: "recurrence editor UI"
sources:
  - path: Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorView.swift
    blob: 0a45e3b6f13912b4cb5c8a1b942759a9af126108
  - path: Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceEditorViewModel.swift
    blob: 222e0124667e98be7e37bdbbe336ae536573639c
  - path: Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceSummary.swift
    blob: 4431a7f040ca523f4e1aad880d5ae5e465d8f2ab
  - path: Packages/LillistUI/Sources/LillistUI/Recurrence/RecurrenceSummaryFormatter.swift
    blob: c6541163a9cf3720b3b08e4e1fd985c4506fc743
references_modules: [Packages-LillistCore-Sources-LillistCore-Recurrence, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1, Apps-Lillist-macOS-Sources-Views-Detail, Apps-Lillist-iOS-Sources-Detail]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
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

- `Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceEditorViewModel -> Packages-LillistCore-Sources-LillistCore-Recurrence.RecurrenceRule (owns)`
- `Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceEditorViewModel -> Packages-LillistCore-Sources-LillistCore-Recurrence.Weekday (reads)`
- `Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceSummary -> Packages-LillistCore-Sources-LillistCore-Recurrence.RecurrenceRule (reads)`
- `Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceEditorView -> Packages-LillistCore-Sources-LillistCore-Recurrence.Weekday (reads)`
- `Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceEditorView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.RainbowPalette (reads)`
- `Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceEditorView -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.LillistColor (reads)`
- `Apps-Lillist-macOS-Sources-Views-Detail.TaskDetailView -> Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceEditorView (calls)`
- `Apps-Lillist-iOS-Sources-Detail.RecurrenceSheet -> Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceEditorView (calls)`
- `Apps-Lillist-macOS-Sources-Views-Detail.TaskDetailView -> Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceSummaryFormatter (calls)`
- `Apps-Lillist-iOS-Sources-Detail.TaskDetailView -> Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceSummaryFormatter (calls)`

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
