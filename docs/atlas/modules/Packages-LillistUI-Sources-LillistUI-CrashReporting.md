---
module: Packages/LillistUI/Sources/LillistUI/CrashReporting
summary: "SwiftUI crash-report consent UI: sheet + preview + @Observable view model bridging LillistCore.CrashReporter"
read_when: "Touching crash-report consent UI"
sources:
  - path: Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportPreviewSheet.swift
    blob: 4eebb55707cfa2ee7ad6b6d0657875f5b557db97
  - path: Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportSheet.swift
    blob: cbc6a53679fcec49b0f68ec5be0024cd85e01c7f
  - path: Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportViewModel.swift
    blob: 41a6b325226f75b650b581c4b7d4e843dd87e5a1
references_modules: [Packages-LillistCore-Sources-LillistCore-CrashReporting, Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistUI-Sources-LillistUI-Settings, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1]
generator: cartographer/4
baseline: 8e926f08fd5269de164d25b42880893a604a9d5c
---

# Module: Packages/LillistUI/Sources/LillistUI/CrashReporting

## Purpose

This module is the SwiftUI consent layer for crash reporting: it presents the post-crash opt-in dialog, lets the user inspect exactly what will be sent before deciding, and routes the decision to LillistCore.CrashReporter. The three files form a single unit — view model, main sheet, preview sheet — each with no responsibility outside this flow. Without this module the app has crash detection but no user-facing decision surface, breaking the privacy-first opt-in contract described in design Section 8.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `CrashReportPreviewSheet` | struct | `Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportPreviewSheet.swift:3` | Presents a read-only monospaced scrollable view of a pre-rendered crash report string; caller supplies the fully rendered string, no model or data dependency. |
| `CrashReportSheet` | struct | `Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportSheet.swift:4` | Full crash-report consent form; caller injects a CrashReportViewModel, host metadata (build/OS/device), and an optional contactRecipient; Send/Don't Send toolbar actions delegate to the view model and then dismiss. |
| `CrashReportViewModel` | class | `Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportViewModel.swift:9` | @MainActor @Observable view model; holds user input state (userDescription, includeLogs, includeBreadcrumbs, previewText, isSubmitting) and routes send/dontSend decisions to an injected CrashReporter actor. |
| `dontSend` | func | `Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportViewModel.swift:81` | Records the user's dismissal by forwarding .dontSend to reporter.submit; throws if the reporter call throws, so callers may use try?. |
| `refreshPreview` | func | `Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportViewModel.swift:57` | Re-renders self.previewText using the model's current includeLogs/includeBreadcrumbs flags and caller-supplied metadata; observers of previewText via @Observable see the update. |
| `renderPreview` | func | `Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportViewModel.swift:35` | Returns a plain-text preview string for arbitrary include-flag combinations without touching model state; safe to call for per-toggle previews without disturbing includeLogs/includeBreadcrumbs. |
| `send` | func | `Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportViewModel.swift:68` | Submits the crash report with current model flags via reporter.submit(.send,...); sets isSubmitting for the duration; throws if reporter throws; disables Send button while in-flight. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

- `Packages-LillistUI-Sources-LillistUI-CrashReporting.CrashReportPreviewSheet -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (calls)`
- `Packages-LillistUI-Sources-LillistUI-CrashReporting.CrashReportSheet -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (calls)`
- `Packages-LillistUI-Sources-LillistUI-CrashReporting.CrashReportSheet -> Packages-LillistUI-Sources-LillistUI-Settings.preview (calls)`
- `Packages-LillistUI-Sources-LillistUI-CrashReporting.PreviewPayload -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-CrashReporting.PreviewPayload -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.accessibilityLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-CrashReporting.dontSend -> Packages-LillistCore-Sources-LillistCore-CrashReporting.submit (calls)`
- `Packages-LillistUI-Sources-LillistUI-CrashReporting.renderPreview -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReport (calls)`
- `Packages-LillistUI-Sources-LillistUI-CrashReporting.renderPreview -> Packages-LillistCore-Sources-LillistCore-CrashReporting.renderedAsPlainText (reads)`
- `Packages-LillistUI-Sources-LillistUI-CrashReporting.send -> Packages-LillistCore-Sources-LillistCore-CrashReporting.submit (writes)`

## Type notes

CrashReportViewModel is @MainActor @Observable (not ObservableObject), so CrashReportSheet uses @Bindable — not @StateObject/@ObservedObject (CrashReportViewModel.swift:7-9, CrashReportSheet.swift:6). The nonisolated id UUID satisfies Identifiable from off-actor callers (e.g. .sheet(item:)) without a MainActor hop (CrashReportViewModel.swift:13). CrashReportViewModel holds a private CrashReporter actor reference and a public CrashCanary value; both are injected at init, keeping the view model testable without a live reporter (CrashReportViewModel.swift:22-28). CrashReportSheet carries contactRecipient as a caller-injected init parameter (defaulting to LillistCoreContact.crashReportRecipient) so snapshot tests can supply a deterministic non-personal value (CrashReportSheet.swift:14-19). The three sub-sheet state booleans (showingPreview, showingLogsPreview, showingBreadcrumbsPreview) live on the view, not the view model, since they are pure navigation state (CrashReportSheet.swift:21-25).

## External deps

- Foundation — imported
- LillistCore — imported
- Observation — imported
- SwiftUI — imported

## Gotchas

SwiftUI Text(LocalizedStringKey) auto-link detection fires only on compile-time literals; interpolated email values render as plain text. CrashReportSheet.swift:131-133 spells the mailto link explicitly as [\(contactRecipient)](mailto:\(contactRecipient)) to preserve the clickable affordance — this pattern is also documented in CLAUDE.md's code conventions.
