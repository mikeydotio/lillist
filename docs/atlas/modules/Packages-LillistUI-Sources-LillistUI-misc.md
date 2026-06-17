---
module: "Packages/LillistUI/Sources/LillistUI (misc)"
summary: "LillistUI package root — landing namespace, status-cycle state machine, and UI-facing sync indicator protocol"
read_when: "LillistUI status seam"
sources:
  - path: Packages/LillistUI/Sources/LillistUI/LillistUI.swift
    blob: 6c093e3ce4c0bfbbd190533a80b07af79b36b648
  - path: Packages/LillistUI/Sources/LillistUI/Resources/Fonts/OFL.txt
    blob: ea69b0ca12a02556c436680ea0a159efb7a748fa
  - path: Packages/LillistUI/Sources/LillistUI/Resources/Localizable.xcstrings
    blob: 857508cf8735ef743c4e6b32dc4bddeab083123b
  - path: Packages/LillistUI/Sources/LillistUI/Status/StatusCycler.swift
    blob: 83cae2f8fa475b9e58f9b7cd0893ceea380ac5c9
  - path: Packages/LillistUI/Sources/LillistUI/Status/SyncStatusMonitor.swift
    blob: 86767bf3ab935f3c12fd21b488de7a4bccfb2377
references_modules: [Packages-LillistCore-Sources-LillistCore-Model, Packages-LillistCore-Sources-LillistCore-Sync-chunk-1, Packages-LillistUI-Sources-LillistUI-Components, Apps-Lillist-iOS-Sources-App, Apps-Lillist-macOS-Sources-Views]
generator: cartographer/1
baseline: 1a1562b636e43ebbdc35c7939ab6989b387f50e9
verified: true
---

# Module: Packages/LillistUI/Sources/LillistUI (misc)

## Purpose

The catch-all root of the cross-platform LillistUI library: the `LillistUI`
namespace enum (a documentation landing page plus the package SemVer), the
bundled Plus Jakarta Sans font license, the shared string catalog, and the
`Status/` seam. The `Status/` files hold two small but load-bearing contracts —
the pure status-transition state machine both app shells call on a tap, and the
UI-facing sync-indicator protocol that decouples LillistUI from LillistCore's
concrete CloudKit sync actor.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `IdleSyncIndicatorMonitor` | class | `Packages/LillistUI/Sources/LillistUI/Status/SyncStatusMonitor.swift:35` | `@MainActor @Observable` stub conforming to `SyncIndicatorMonitor`; always reports `.idle` |
| `LillistUI` | enum | `Packages/LillistUI/Sources/LillistUI/LillistUI.swift:42` | Library namespace + landing doc; `version` static holds package SemVer |
| `StatusCycler` | enum | `Packages/LillistUI/Sources/LillistUI/Status/StatusCycler.swift:9` | Pure status-transition state machine for tap/space gestures (design Section 7) |
| `SyncIndicator` | enum | `Packages/LillistUI/Sources/LillistUI/Status/SyncStatusMonitor.swift:7` | `Sendable` value model of sync state: `idle`/`inProgress`/`error`/`paused` |
| `SyncIndicatorMonitor` | protocol | `Packages/LillistUI/Sources/LillistUI/Status/SyncStatusMonitor.swift:26` | `@MainActor` UI read source: `indicator` property + `retry()` |
| `nextOnClick(from:)` | func | `Packages/LillistUI/Sources/LillistUI/Status/StatusCycler.swift:10` | Cycles todo→started→closed→todo; `.blocked` is unreachable by click |
| `nextOnSpace(from:)` | func | `Packages/LillistUI/Sources/LillistUI/Status/StatusCycler.swift:19` | Toggles to/from `.started` from any state |
| `version` | static let | `Packages/LillistUI/Sources/LillistUI/LillistUI.swift:45` | LillistUI SemVer string; bump on public-API changes |

## Load-bearing internals

(none — the module's symbols are all public surface)

## Relationships

- `Packages-LillistUI-Sources-LillistUI-misc.StatusCycler -> Packages-LillistCore-Sources-LillistCore-Model.Status (reads)`
- `Packages-LillistUI-Sources-LillistUI-misc.SyncIndicator -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.PauseReason (owns)`
- `Apps-Lillist-macOS-Sources-Views.TaskListView -> Packages-LillistUI-Sources-LillistUI-misc.StatusCycler (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components.SyncStatusDotView -> Packages-LillistUI-Sources-LillistUI-misc.SyncIndicator (reads)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistUI-Sources-LillistUI-misc.IdleSyncIndicatorMonitor (owns)`

## Type notes

`StatusCycler` and `LillistUI` are caseless enums used purely as namespaces; all
their members are `static`, so they hold no state and need no instance.
`StatusCycler.nextOnClick`/`nextOnSpace` are pure functions of the input
`Status` — the same input always yields the same output, which is what lets both
app shells share one cycle contract.

`SyncIndicatorMonitor` is deliberately named differently from
`LillistCore.SyncStatusMonitor` (the concrete CloudKit actor) to avoid a name
collision; this UI protocol is the seam a future `CloudKitSyncStatusAdapter`
bridges into (`Packages/LillistUI/Sources/LillistUI/Status/SyncStatusMonitor.swift:18`).
`SyncIndicatorMonitor` and `IdleSyncIndicatorMonitor` are both `@MainActor`;
`IdleSyncIndicatorMonitor` is `@Observable`, so SwiftUI views observing its
`indicator` re-render on change. `IdleSyncIndicatorMonitor.retry()` is a no-op
until the live monitor is bridged in.

`Localizable.xcstrings` is the LillistUI string catalog (resource, no symbol
callers) and must stay aligned with the iOS and macOS app catalogs per the
project's cross-platform-string rule.

## External deps

- Foundation — `Date` in `SyncIndicator` timestamps
- Observation — `@Observable` macro on `IdleSyncIndicatorMonitor`
- Plus Jakarta Sans — bundled font; `OFL.txt` is its SIL Open Font License
