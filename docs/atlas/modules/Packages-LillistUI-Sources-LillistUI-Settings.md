---
module: Packages/LillistUI/Sources/LillistUI/Settings
summary: "Shared Settings UI helpers — iCloud sync section, sort-field labels, crash report preview, date picker utility"
read_when: "Touching Settings/Preferences UI shared"
sources:
  - path: Packages/LillistUI/Sources/LillistUI/Settings/CrashReportSample.swift
    blob: 0249e4862ab49f63844aea35f80adcec4dafe388
  - path: Packages/LillistUI/Sources/LillistUI/Settings/HourMinuteDate.swift
    blob: c86f0a9040a23521ff241e157fd83b0e0fcc5e1e
  - path: Packages/LillistUI/Sources/LillistUI/Settings/ICloudSyncSettingsSection.swift
    blob: 42bb0aef222c2b60d6656a085b397148f85ebd71
  - path: "Packages/LillistUI/Sources/LillistUI/Settings/SortField+DisplayName.swift"
    blob: 1ebd38dd6f73717121b152688be85cd73fdbcf1d
references_modules: [Packages-LillistCore-Sources-LillistCore-Model, Packages-LillistCore-Sources-LillistCore-Sync-chunk-1, Packages-LillistUI-Sources-LillistUI-misc]
generator: cartographer/1
baseline: 1a1562b636e43ebbdc35c7939ab6989b387f50e9
verified: true
---

# Module: Packages/LillistUI/Sources/LillistUI/Settings

## Purpose

De-duplication seam for Settings/Preferences UI that the iOS and macOS app targets both render. Each symbol here was once duplicated verbatim across both platform folders (sort-field labels, time-picker date builder, crash-report preview text, the iCloud sync section) and was lifted into LillistUI so the two surfaces cannot silently drift. `ICloudSyncSettingsSection` is the pure-presentation half of a container/presenter split — app targets own `AppEnvironment`-coupled state and inject it via `ViewState` + `Actions`. If this module vanished, every settings surface would revert to private, per-platform forks.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `CrashReportSample` | enum (namespace) | `Packages/LillistUI/Sources/LillistUI/Settings/CrashReportSample.swift:6` | Namespace for the "what would be sent" crash-report preview builder |
| `CrashReportSample.Environment` | struct | `Packages/LillistUI/Sources/LillistUI/Settings/CrashReportSample.swift:7` | `Sendable`/`Equatable` value carrying build/OS/device/recipient/methodSuffix |
| `CrashReportSample.preview(_:)` | static func | `Packages/LillistUI/Sources/LillistUI/Settings/CrashReportSample.swift:33` | Returns the fixed multi-line preview string; callers supply platform `methodSuffix` |
| `HourMinuteDate` | enum (namespace) | `Packages/LillistUI/Sources/LillistUI/Settings/HourMinuteDate.swift:9` | Namespace for building a `Date` from Int hour/minute values |
| `HourMinuteDate.date(hour:minute:calendar:)` | static func | `Packages/LillistUI/Sources/LillistUI/Settings/HourMinuteDate.swift:10` | Builds a `Date` on today with the given hour/minute; bridges `Int16` pref columns to `DatePicker` bindings |
| `ICloudSyncSettingsSection` | struct (View) | `Packages/LillistUI/Sources/LillistUI/Settings/ICloudSyncSettingsSection.swift:13` | Pure-presenter SwiftUI `Section` for sync mode toggle; renders entirely from injected `ViewState` and `Actions` |
| `ICloudSyncSettingsSection.ViewState` | struct | `Packages/LillistUI/Sources/LillistUI/Settings/ICloudSyncSettingsSection.swift:14` | `Equatable`/`Sendable` snapshot: `mode`, `status`, `isToggleDisabled`, `disabledFooter` |
| `ICloudSyncSettingsSection.Actions` | struct | `Packages/LillistUI/Sources/LillistUI/Settings/ICloudSyncSettingsSection.swift:33` | Closure bundle: `onToggle`, `onSyncNow`, `onOpenSystemSettings`, `onPausedTap` |
| `SortField.displayName` | computed var (extension) | `Packages/LillistUI/Sources/LillistUI/Settings/SortField+DisplayName.swift:9` | Human-readable label for each `SortField` case used in Preferences pickers |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `ICloudSyncSettingsSection.statusLine` | private var | `Packages/LillistUI/Sources/LillistUI/Settings/ICloudSyncSettingsSection.swift:102` | Sole place `SyncIndicator` cases are translated to the caption shown under the sync toggle |
| `ICloudSyncSettingsSection.relativeFormatter` | private static let | `Packages/LillistUI/Sources/LillistUI/Settings/ICloudSyncSettingsSection.swift:126` | Singleton `RelativeDateTimeFormatter` for last-synced timestamp; shared to avoid per-render allocation |

## Relationships

- `Packages-LillistUI-Sources-LillistUI-Settings.SortField.displayName -> Packages-LillistCore-Sources-LillistCore-Model.SortField (extends)`
- `Packages-LillistUI-Sources-LillistUI-Settings.ICloudSyncSettingsSection.ViewState -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.SyncMode (owns)`
- `Packages-LillistUI-Sources-LillistUI-Settings.ICloudSyncSettingsSection.ViewState -> Packages-LillistUI-Sources-LillistUI-misc.SyncIndicator (owns)`

## Type notes

`ICloudSyncSettingsSection` holds no `@State` and runs no `.task` — it is the presenter half of the Plan 21 container/presenter split documented at `Packages/LillistUI/Sources/LillistUI/Settings/ICloudSyncSettingsSection.swift:7`. The owning app views (iOS `ICloudSyncSection`, macOS `ICloudSyncPane`) hold `AppEnvironment`-coupled state and pass it in, so snapshot tests render canned `ViewState`s with no live container required.

`ViewState` and `CrashReportSample.Environment` are `Equatable`/`Sendable` value types and can be produced from a background actor. `Actions` carries `@escaping` closures and is not `Sendable`; it is expected to be constructed on `@MainActor`. Localized strings inside `ICloudSyncSettingsSection` resolve against `bundle: .module` (`Packages/LillistUI/Sources/LillistUI/Settings/ICloudSyncSettingsSection.swift:106`).

`HourMinuteDate.date` routes its math through `Calendar.dateComponents` and `Calendar.date(from:)` — consistent with the project rule against `addingTimeInterval` for preference-driven date construction.

## External deps

- SwiftUI — `ICloudSyncSettingsSection` is a `View`; uses `Section`, `Toggle`, `Button`, `Text`, `VStack`, `Binding`, `Color`
- Foundation — `RelativeDateTimeFormatter`, `Calendar`, `DateComponents`, `Date`, `String(localized:bundle:)`
