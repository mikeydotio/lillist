---
module: Packages/LillistUI/Sources/LillistUI/CrashReporting
summary: SwiftUI crash-report consent sheet and its observable view model over LillistCore's CrashReporter
read_when: Touching crash-report consent UI, report preview, or send/don't-send decision flow
sources:
  - path: Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportPreviewSheet.swift
  - path: Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportSheet.swift
  - path: Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportViewModel.swift
references_modules: [Packages-LillistCore-Sources-LillistCore-CrashReporting, Packages-LillistCore-Sources-LillistCore-misc, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1]
generator: cartographer/1 model=claude-sonnet-4-6
---

# Module: Packages/LillistUI/Sources/LillistUI/CrashReporting

## Purpose

The cross-platform UI that asks the user, on next launch after a crash, whether to send a
report. A purely declarative `CrashReportSheet` form is driven by an `@Observable`
`CrashReportViewModel` that owns all report assembly and the send/don't-send decision, so
the view holds only transient SwiftUI sheet state. The honesty guarantee is the design
core: the same `CrashReport.renderedAsPlainText()` that gets sent backs every "preview"
button, so what the user reviews is exactly what leaves the device.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `CrashReportPreviewSheet` | struct | `Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportPreviewSheet.swift:3` | Read-only monospaced sheet showing the rendered report body passed via `init(body:)` |
| `CrashReportSheet` | struct | `Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportSheet.swift:4` | The consent form; binds a `CrashReportViewModel` plus host-supplied build/OS/device strings |
| `CrashReportViewModel` | class | `Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportViewModel.swift:9` | `@MainActor @Observable` backing model; owns include flags, preview text, and submission |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `renderPreview(includeLogs:includeBreadcrumbs:buildVersion:osVersion:deviceModel:)` | func | `Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportViewModel.swift:35` | Pure render for arbitrary flags; does not mutate the model, so per-toggle previews don't disturb state |
| `send()` | func | `Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportViewModel.swift:68` | Sets `isSubmitting`, then submits the report with `.send` and the current flags |
| `dontSend()` | func | `Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportViewModel.swift:81` | Submits a `.dontSend` decision with no description or logs |
| `refreshPreview(buildVersion:osVersion:deviceModel:)` | func | `Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportViewModel.swift:57` | Stores the bulk "View what will be sent" render on `previewText` |

## Relationships

- `Packages-LillistUI-Sources-LillistUI-CrashReporting.CrashReportViewModel -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReporter (calls)`
- `Packages-LillistUI-Sources-LillistUI-CrashReporting.CrashReportViewModel -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReport (calls)`
- `Packages-LillistUI-Sources-LillistUI-CrashReporting.CrashReportViewModel -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashCanary (owns)`
- `Packages-LillistUI-Sources-LillistUI-CrashReporting.CrashReportSheet -> Packages-LillistUI-Sources-LillistUI-CrashReporting.CrashReportViewModel (owns)`
- `Packages-LillistUI-Sources-LillistUI-CrashReporting.CrashReportSheet -> Packages-LillistUI-Sources-LillistUI-CrashReporting.CrashReportPreviewSheet (calls)`
- `Packages-LillistUI-Sources-LillistUI-CrashReporting.CrashReportSheet -> Packages-LillistCore-Sources-LillistCore-misc.LillistCoreContact (reads)`
- `Packages-LillistUI-Sources-LillistUI-CrashReporting.CrashReportSheet -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.RainbowToggleStyle (conforms-to)`

## Type notes

`CrashReportViewModel` is `@MainActor @Observable` (`CrashReportViewModel.swift:7`); its
`id` is `nonisolated` (`CrashReportViewModel.swift:13`) so SwiftUI's `.sheet(item:)` can
read identity off the main actor. The comment there notes the lifecycle invariant: at most
one model is alive per host at a time, so a fresh `UUID` per instance suffices.
`reporter` is a `CrashReporter` actor, so `send`/`dontSend`/`renderPreview` are `async`;
`reporter.submit` is the one awaited boundary that crosses into LillistCore
(`CrashReportViewModel.swift:71`). The view model holds `pending` (a `CrashCanary` value
type) and never sees a `NSManagedObject`. `CrashReportSheet` keeps build/OS/device as
caller-supplied strings (`CrashReportSheet.swift:8-12`) because that metadata comes from
the host process, not LillistUI. `renderPreview` deliberately reads its flag arguments, not
`self.includeLogs`/`self.includeBreadcrumbs`, so the per-toggle "Preview these" buttons
render an isolated slice without mutating the live model (`CrashReportViewModel.swift:30-34`).

## External deps

- SwiftUI — `Form`, `NavigationStack`, `Toggle`, `@Bindable`, and `.sheet` presentation
- Observation — `@Observable` macro backing the view model
- LillistCore — `CrashReporter`, `CrashReport`, `CrashCanary`, `LillistCoreContact`

## Gotchas

- The recipient email is spelled as an explicit markdown `mailto:` link, not a bare address: SwiftUI auto-links emails only in compile-time `LocalizedStringKey` literals, and the interpolated `LillistCoreContact.crashReportRecipient` would otherwise render as plain text (`Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportSheet.swift:109-116`).
