---
module: Packages/LillistUI/Sources/LillistUI/Settings
summary: "Shared Settings/Preferences presentation helpers lifted out of the two app targets"
read_when: "Shared Settings helpers"
sources:
  - path: Packages/LillistUI/Sources/LillistUI/Settings/CrashReportSample.swift
    blob: 0249e4862ab49f63844aea35f80adcec4dafe388
  - path: Packages/LillistUI/Sources/LillistUI/Settings/HourMinuteDate.swift
    blob: c86f0a9040a23521ff241e157fd83b0e0fcc5e1e
  - path: Packages/LillistUI/Sources/LillistUI/Settings/ICloudSyncSettingsSection.swift
    blob: 42bb0aef222c2b60d6656a085b397148f85ebd71
  - path: "Packages/LillistUI/Sources/LillistUI/Settings/SortField+DisplayName.swift"
    blob: 1ebd38dd6f73717121b152688be85cd73fdbcf1d
references_modules: [Packages-LillistCore-Sources-LillistCore-Model, Packages-LillistCore-Sources-LillistCore-Sync-chunk-1, Packages-LillistUI-Sources-LillistUI-misc, Apps-Lillist-iOS-Sources-Settings, Apps-Lillist-macOS-Sources-Preferences]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
---

# Module: Packages/LillistUI/Sources/LillistUI/Settings

## Purpose

De-duplication seam for Settings/Preferences UI that the iOS app and macOS app
both render. Each symbol here was once duplicated verbatim across both target
folders (sort labels, time-picker date builder, crash-report preview text, the
iCloud sync section) and was lifted into LillistUI so the two surfaces cannot
drift. `ICloudSyncSettingsSection` is the pure-presentation half of a
container/presenter split — the app targets own state and inject it.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `CrashReportSample` | enum | `Packages/LillistUI/Sources/LillistUI/Settings/CrashReportSample.swift:6` | Namespace for the "what would be sent" crash-report preview builder |
| `CrashReportSample.Environment` | struct | `Packages/LillistUI/Sources/LillistUI/Settings/CrashReportSample.swift:7` | Sendable value carrying build/OS/device/recipient/method for the preview |
| `CrashReportSample.preview(_:)` | static func | `Packages/LillistUI/Sources/LillistUI/Settings/CrashReportSample.swift:33` | Returns the multi-line preview string; callers supply platform `methodSuffix` |
| `HourMinuteDate` | enum | `Packages/LillistUI/Sources/LillistUI/Settings/HourMinuteDate.swift:9` | Namespace for the time-picker date helper |
| `HourMinuteDate.date(hour:minute:calendar:)` | static func | `Packages/LillistUI/Sources/LillistUI/Settings/HourMinuteDate.swift:10` | Builds a `Date` on today's day with the given hour/minute for DatePicker binds |
| `ICloudSyncSettingsSection` | struct (View) | `Packages/LillistUI/Sources/LillistUI/Settings/ICloudSyncSettingsSection.swift:13` | Pure-presentation Settings `Section` for sync mode; renders from injected state |
| `ICloudSyncSettingsSection.ViewState` | struct | `Packages/LillistUI/Sources/LillistUI/Settings/ICloudSyncSettingsSection.swift:14` | Equatable/Sendable snapshot: mode, status, toggle-disabled, disabled footer |
| `ICloudSyncSettingsSection.Actions` | struct | `Packages/LillistUI/Sources/LillistUI/Settings/ICloudSyncSettingsSection.swift:33` | Callback bundle: onToggle, onSyncNow, onOpenSystemSettings, onPausedTap |
| `SortField.displayName` | computed var (extension) | `Packages/LillistUI/Sources/LillistUI/Settings/SortField+DisplayName.swift:9` | Human label for each `SortField` case used in Preferences pickers |

## Load-bearing internals

(none — the module is entirely public-surface helpers; private members are
view-local computed strings/colors and a formatter.)

## Relationships

- `Packages-LillistUI-Sources-LillistUI-Settings.SortField -> Packages-LillistCore-Sources-LillistCore-Model.SortField (extends)`
- `Packages-LillistUI-Sources-LillistUI-Settings.ICloudSyncSettingsSection.ViewState -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.SyncMode (owns)`
- `Packages-LillistUI-Sources-LillistUI-Settings.ICloudSyncSettingsSection.ViewState -> Packages-LillistUI-Sources-LillistUI-misc.SyncIndicator (owns)`
- `Apps-Lillist-iOS-Sources-Settings.ICloudSyncSection -> Packages-LillistUI-Sources-LillistUI-Settings.ICloudSyncSettingsSection (calls)`
- `Apps-Lillist-macOS-Sources-Preferences.ICloudSyncPane -> Packages-LillistUI-Sources-LillistUI-Settings.ICloudSyncSettingsSection (calls)`
- `Apps-Lillist-iOS-Sources-Settings.NotificationsSection -> Packages-LillistUI-Sources-LillistUI-Settings.HourMinuteDate (calls)`
- `Apps-Lillist-macOS-Sources-Preferences.NotificationsPane -> Packages-LillistUI-Sources-LillistUI-Settings.HourMinuteDate (calls)`
- `Apps-Lillist-iOS-Sources-Settings.CrashReportingSection -> Packages-LillistUI-Sources-LillistUI-Settings.CrashReportSample (calls)`
- `Apps-Lillist-macOS-Sources-Preferences.CrashReportingPane -> Packages-LillistUI-Sources-LillistUI-Settings.CrashReportSample (calls)`

## Type notes

`ICloudSyncSettingsSection` holds no `@State` and runs no `.task` — it is the
presenter half of the Plan 21 container/presenter split (documented at
`Packages/LillistUI/Sources/LillistUI/Settings/ICloudSyncSettingsSection.swift:7`).
The owning app views (iOS `ICloudSyncSection`, macOS `ICloudSyncPane`) hold the
`AppEnvironment`-coupled state and pass it in via `ViewState` + `Actions`, so
snapshot tests can render canned states with no live container.
`ViewState` and `Environment` are `Equatable`/`Sendable` value types; `Actions`
carries `@escaping` closures and is not `Sendable`. Localized strings in the
sync section resolve against `bundle: .module`
(`Packages/LillistUI/Sources/LillistUI/Settings/ICloudSyncSettingsSection.swift:106`).
`HourMinuteDate.date` defaults to `Calendar.current` and routes its math through
`Calendar.dateComponents`/`Calendar.date(from:)` rather than interval arithmetic.

## External deps

- SwiftUI — `ICloudSyncSettingsSection` is a `View` building a `Section`/`Toggle`
- Foundation — `RelativeDateTimeFormatter`, `Calendar`, `Date`, `String(localized:)`
