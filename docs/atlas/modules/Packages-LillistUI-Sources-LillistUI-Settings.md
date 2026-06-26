---
module: Packages/LillistUI/Sources/LillistUI/Settings
summary: "Shared Settings primitives: iCloud sync section, crash-report preview, sort labels, time-picker."
read_when: "Touching shared Settings/Preferences UI"
sources:
  - path: Packages/LillistUI/Sources/LillistUI/Settings/CrashReportSample.swift
    blob: 566946982c5485974455f1215cb951669c357dd0
  - path: Packages/LillistUI/Sources/LillistUI/Settings/HourMinuteDate.swift
    blob: c86f0a9040a23521ff241e157fd83b0e0fcc5e1e
  - path: Packages/LillistUI/Sources/LillistUI/Settings/ICloudSyncSettingsSection.swift
    blob: 2b3b0a8c45734528426074bc4ece98d9950f81d9
  - path: Packages/LillistUI/Sources/LillistUI/Settings/SettingsDetailScreen.swift
    blob: 82fc43eabbdb7fb0d28f5f9fc7758f652777bf2c
  - path: Packages/LillistUI/Sources/LillistUI/Settings/SettingsRowIcon.swift
    blob: fcc7f3bbc4dde451e0d4c93fb1a3fed7355bc030
  - path: "Packages/LillistUI/Sources/LillistUI/Settings/SortField+DisplayName.swift"
    blob: 1ebd38dd6f73717121b152688be85cd73fdbcf1d
references_modules: [Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistUI-Sources-LillistUI-iOS-misc]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistUI/Sources/LillistUI/Settings

## Purpose

Shared Settings/Preferences primitives that were previously duplicated verbatim in both app targets and lifted into LillistUI (Plan 14) to keep the two targets in parity. The module contains stateless building blocks — the iCloud sync section, crash-report preview builder, notification time-picker helper, sort-field display names, and iOS row-icon tile — each designed as pure-presentation or pure-utility with no direct `AppEnvironment` access. Without it, platform-specific copies of these pieces would drift independently and break visual and behavioral parity between iOS and macOS Settings.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `Actions` | struct | `Packages/LillistUI/Sources/LillistUI/Settings/ICloudSyncSettingsSection.swift:33` | Callback bag holding four escaping closures; `onPausedTap` defaults to a no-op; callers supply the other three — toggle, sync-now, and open-system-settings. |
| `CrashReportSample` | enum | `Packages/LillistUI/Sources/LillistUI/Settings/CrashReportSample.swift:6` | Namespace enum; callers construct an `Environment` and call `preview(_:)` to obtain the multi-line crash-report preview string. |
| `Environment` | struct | `Packages/LillistUI/Sources/LillistUI/Settings/CrashReportSample.swift:7` | `Sendable + Equatable` value holding the five fields (build version, OS, device, recipient, method suffix) required to render a crash-report preview; callers own all fields. |
| `HourMinuteDate` | enum | `Packages/LillistUI/Sources/LillistUI/Settings/HourMinuteDate.swift:9` | Namespace enum; callers use `date(hour:minute:calendar:)` to build a `Date` whose calendar components match today for use in a `DatePicker` binding. |
| `ICloudSyncSettingsSection` | struct | `Packages/LillistUI/Sources/LillistUI/Settings/ICloudSyncSettingsSection.swift:13` | Pure-presentation `View`; callers supply a `ViewState` snapshot and an `Actions` bag; the view holds no `@State`, `.task`, or environment reads. |
| `SettingsDetailScreen` | struct | `Packages/LillistUI/Sources/LillistUI/Settings/SettingsDetailScreen.swift:32` | iOS-only pushed settings sub-page; wraps caller-supplied sections in a `Form` with shared settings chrome; owns no `NavigationStack` — must be pushed inside an existing one. |
| `SettingsFormStyle` | struct | `Packages/LillistUI/Sources/LillistUI/Settings/SettingsDetailScreen.swift:10` | iOS-only `ViewModifier` applying the rainbow toggle style, hidden scroll background, and workspace fill to a Settings `Form`; used via `.settingsFormStyle()`. |
| `SettingsRowIcon` | struct | `Packages/LillistUI/Sources/LillistUI/Settings/SettingsRowIcon.swift:15` | iOS-only 29×29 pt colored tile with a white SF Symbol; the glyph is `accessibilityHidden` because the row's text label already carries the accessible name. |
| `SortField` | extension | `Packages/LillistUI/Sources/LillistUI/Settings/SortField+DisplayName.swift:8` | Adds `displayName: String` to `LillistCore.SortField`; returns hard-coded English labels for use in sort-order picker rows in both app targets' Preferences UI. |
| `View` | extension | `Packages/LillistUI/Sources/LillistUI/Settings/SettingsDetailScreen.swift:19` | iOS-only extension on `View` adding the `settingsFormStyle()` convenience method; any `View` gains the method but it is meaningful only on a Settings `Form`. |
| `ViewState` | struct | `Packages/LillistUI/Sources/LillistUI/Settings/ICloudSyncSettingsSection.swift:14` | `Equatable + Sendable` snapshot of sync UI state; callers construct from live `SyncMode` and `SyncIndicator` values; `isToggleDisabled` and `disabledFooter` default to off/nil. |
| `body` | func | `Packages/LillistUI/Sources/LillistUI/Settings/SettingsDetailScreen.swift:11` | Applies rainbow toggle style, hidden scroll background, and `LillistColor.workspace` fill to the wrapped `Form` content; no side effects beyond view modifier composition. |
| `date` | func | `Packages/LillistUI/Sources/LillistUI/Settings/HourMinuteDate.swift:10` | Returns a `Date` combining today's year/month/day with the given hour and minute via `Calendar.date(from:)`; DST-safe and falls back to `Date()` on failure. |
| `preview` | func | `Packages/LillistUI/Sources/LillistUI/Settings/CrashReportSample.swift:33` | Returns a multi-line formatted string ready to display in a settings disclosure or mail draft; all five fields of `env` are interpolated verbatim. |
| `settingsFormStyle` | func | `Packages/LillistUI/Sources/LillistUI/Settings/SettingsDetailScreen.swift:21` | Chains `SettingsFormStyle` onto any `View`; callers use it on a `Form` to apply the shared Settings chrome in one call. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

- `Packages-LillistUI-Sources-LillistUI-Settings.Actions -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-Settings.Actions -> Packages-LillistUI-Sources-LillistUI-iOS-misc.SyncStatusBadge (calls)`

## Type notes

`ICloudSyncSettingsSection` follows the container/presenter split: it is pure presentation fed entirely by `ViewState` and `Actions` with no `@State`, `.task`, or `AppEnvironment` reads (`Packages/LillistUI/Sources/LillistUI/Settings/ICloudSyncSettingsSection.swift:6`). `SettingsDetailScreen` and `SettingsRowIcon` are gated by `#if os(iOS)` and do not exist on macOS (`Packages/LillistUI/Sources/LillistUI/Settings/SettingsDetailScreen.swift:1`, `Packages/LillistUI/Sources/LillistUI/Settings/SettingsRowIcon.swift:1`). `CrashReportSample.Environment` is `Sendable + Equatable`, safe to pass across concurrency domains (`Packages/LillistUI/Sources/LillistUI/Settings/CrashReportSample.swift:7`). `HourMinuteDate.date` rounds through `Calendar.dateComponents` and `Calendar.date(from:)` for DST correctness — consistent with the project-wide rule against `addingTimeInterval` for calendar math (`Packages/LillistUI/Sources/LillistUI/Settings/HourMinuteDate.swift:10`).

## External deps

- Foundation — imported
- LillistCore — imported
- SwiftUI — imported

## Gotchas

`SettingsDetailScreen` must NOT be given its own `NavigationStack` — it is pushed inside the calling screen's existing stack; adding one breaks back-button navigation. `Packages/LillistUI/Sources/LillistUI/Settings/SettingsDetailScreen.swift:28`. `SettingsDetailScreen` and `SettingsRowIcon` are compiled only on iOS (`#if os(iOS)`) — macOS callers cannot reference these types. `Packages/LillistUI/Sources/LillistUI/Settings/SettingsDetailScreen.swift:1`, `Packages/LillistUI/Sources/LillistUI/Settings/SettingsRowIcon.swift:1`. `SortField.displayName` strings are hard-coded English and are not passed through `String(localized:)` — callers should not expect automatic localization. `Packages/LillistUI/Sources/LillistUI/Settings/SortField+DisplayName.swift:9`.
