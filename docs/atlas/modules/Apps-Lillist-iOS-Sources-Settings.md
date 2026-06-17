---
module: Apps/Lillist-iOS/Sources/Settings
summary: Env-coupled iOS Settings sections wiring AppEnvironment into LillistUI chrome; owns full iCloud sync migration UI
read_when: Touching iOS Settings screens, iCloud sync migration UI, notification prefs, or data export/import
sources:
  - path: Apps/Lillist-iOS/Sources/Settings/AdvancedSection.swift
  - path: Apps/Lillist-iOS/Sources/Settings/CrashReportingSection.swift
  - path: Apps/Lillist-iOS/Sources/Settings/DiagnosticsSection.swift
  - path: Apps/Lillist-iOS/Sources/Settings/GeneralSection.swift
  - path: Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift
  - path: Apps/Lillist-iOS/Sources/Settings/NotificationsSection.swift
  - path: Apps/Lillist-iOS/Sources/Settings/QuickCaptureSection.swift
  - path: Apps/Lillist-iOS/Sources/Settings/SettingsTab.swift
  - path: Apps/Lillist-iOS/Sources/Settings/TrashSection.swift
references_modules:
  - Apps-Lillist-iOS-Sources-App
  - Apps-Lillist-iOS-Sources-misc
  - Packages-LillistUI-Sources-LillistUI-Settings
  - Packages-LillistUI-Sources-LillistUI-Sync
  - Packages-LillistUI-Sources-LillistUI-iOS-misc
  - Packages-LillistCore-Sources-LillistCore-Persistence
  - Packages-LillistCore-Sources-LillistCore-Sync-chunk-1
  - Packages-LillistCore-Sources-LillistCore-Export
  - Packages-LillistCore-Sources-LillistCore-Diagnostics
  - Packages-LillistCore-Sources-LillistCore-Notifications
  - Packages-LillistCore-Sources-LillistCore-CrashReporting
  - Packages-LillistCore-Sources-LillistCore-Stores-chunk-2
  - Packages-LillistCore-Sources-LillistCore-misc
generator: cartographer/1 model=claude-sonnet-4-6
---

# Module: Apps/Lillist-iOS/Sources/Settings

## Purpose

The env-coupled half of the iOS Settings screen. `SettingsScreen` (LillistUI) owns the navigation chrome; each section here is the iOS-app presenter that reads/writes `AppEnvironment` stores, schedulers, and migration coordinator that LillistUI cannot import. `SettingsTab` hydrates a single `PreferencesStore.Prefs` and threads a shared `Binding` to every prefs-backed section, so all preference edits round-trip through one read/update lifecycle. Without this module the iOS app has no Settings surface.

## Public API

All section views are `internal` to the Lillist-iOS app target. `SettingsTab` is the only symbol consumed outside this directory (by the Tasks tab's gear action).

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `SettingsTab` | struct (View) | `Apps/Lillist-iOS/Sources/Settings/SettingsTab.swift:10` | Composes all sections into `SettingsScreen`; owns the `Prefs` read/update lifecycle |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `ICloudSyncSection` | struct (View) | `Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:10` | Owns all sync-migration sheet/dialog state; drives the migration coordinator |
| `runMigration` | func | `Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:189` | `@MainActor` driver: streams `progressStream` phases into `activePhase` for the progress sheet |
| `MigrationPhase` (ext) | extension | `Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:208` | Retroactive `Identifiable` conformance so the phase drives `.fullScreenCover(item:)` |
| `handleToggle` | func | `Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:118` | Branches toggle on/off to choice sheet vs. disable sheet; entry point for all sync-mode changes |
| `isAvailable` | func | `Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:132` | Determines whether the iCloud toggle is enabled; gates on `iCloudAccountState.available` |
| `DiagnosticsSection` | struct (View) | `Apps/Lillist-iOS/Sources/Settings/DiagnosticsSection.swift:11` | Write-through logging toggle + diagnostic package build/export flow |
| `NotificationsSection` | struct (View) | `Apps/Lillist-iOS/Sources/Settings/NotificationsSection.swift:5` | Debounced reminder-time edits + permission status, via the notification scheduler |
| `AdvancedSection` | struct (View) | `Apps/Lillist-iOS/Sources/Settings/AdvancedSection.swift:6` | Export-to-folder and import-bundle flows over `environment.persistence` |
| `TrashSection` | struct (View) | `Apps/Lillist-iOS/Sources/Settings/TrashSection.swift:5` | Retention-days picker + Empty Trash; coerces legacy custom values to presets |
| `GeneralSection` | struct (View) | `Apps/Lillist-iOS/Sources/Settings/GeneralSection.swift:5` | Default sort + tag-tint pickers, bound to `Prefs` |
| `CrashReportingSection` | struct (View) | `Apps/Lillist-iOS/Sources/Settings/CrashReportingSection.swift:5` | Crash-prompt toggle; mirrors change into live env and previews report payload |

## Relationships

- `Apps-Lillist-iOS-Sources-misc.TasksView -> Apps-Lillist-iOS-Sources-Settings.SettingsTab (calls)`
- `Apps-Lillist-iOS-Sources-Settings.SettingsTab -> Packages-LillistUI-Sources-LillistUI-iOS-misc.SettingsScreen (calls)`
- `Apps-Lillist-iOS-Sources-Settings.SettingsTab -> Apps-Lillist-iOS-Sources-App.AppEnvironment (reads)`
- `Apps-Lillist-iOS-Sources-Settings.ICloudSyncSection -> Packages-LillistUI-Sources-LillistUI-Settings.ICloudSyncSettingsSection (calls)`
- `Apps-Lillist-iOS-Sources-Settings.ICloudSyncSection -> Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationChoiceSheet (calls)`
- `Apps-Lillist-iOS-Sources-Settings.ICloudSyncSection -> Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationProgressSheet (calls)`
- `Apps-Lillist-iOS-Sources-Settings.ICloudSyncSection -> Packages-LillistUI-Sources-LillistUI-Sync.SyncDisableConfirmationSheet (calls)`
- `Apps-Lillist-iOS-Sources-Settings.ICloudSyncSection -> Packages-LillistUI-Sources-LillistUI-Sync.PauseExplainerDialog (calls)`
- `Apps-Lillist-iOS-Sources-Settings.runMigration -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.MigrationCoordinator (calls)`
- `Apps-Lillist-iOS-Sources-Settings.MigrationPhase -> Packages-LillistCore-Sources-LillistCore-Persistence.MigrationPhase (extends)`
- `Apps-Lillist-iOS-Sources-Settings.NotificationsSection -> Packages-LillistCore-Sources-LillistCore-Notifications.NotificationPermissions (calls)`
- `Apps-Lillist-iOS-Sources-Settings.TrashSection -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (calls)`
- `Apps-Lillist-iOS-Sources-Settings.AdvancedSection -> Packages-LillistCore-Sources-LillistCore-Export.Exporter (calls)`
- `Apps-Lillist-iOS-Sources-Settings.AdvancedSection -> Packages-LillistCore-Sources-LillistCore-Export.Importer (calls)`
- `Apps-Lillist-iOS-Sources-Settings.DiagnosticsSection -> Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticPackageBuilder (calls)`
- `Apps-Lillist-iOS-Sources-Settings.DiagnosticsSection -> Packages-LillistUI-Sources-LillistUI-iOS-misc.DiagnosticZipDocument (owns)`
- `Apps-Lillist-iOS-Sources-Settings.CrashReportingSection -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReportSample (calls)`
- `Apps-Lillist-iOS-Sources-Settings.CrashReportingSection -> Packages-LillistCore-Sources-LillistCore-misc.LillistCoreContact (reads)`

## Type notes

Every section is a pure `View` struct that reaches `AppEnvironment` through `@Environment(AppEnvironment.self)`; only `SettingsTab` owns the canonical `Prefs` state and passes a `Binding` down, so sections never read `PreferencesStore` directly (`Apps/Lillist-iOS/Sources/Settings/SettingsTab.swift:13`). `DiagnosticsSection`'s logging toggle is a write-through `Binding`: `.task` hydration sets `enabled` without persisting and `didHydrate` guards against a late read clobbering a user tap (`Apps/Lillist-iOS/Sources/Settings/DiagnosticsSection.swift:77`). `ICloudSyncSection.runMigration` is `@MainActor`; it spawns a child `Task` consuming `coordinator.progressStream` and cancels it on exit (`Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:193`). `TrashSection.init` mutates the passed `Binding` to snap a legacy retention value onto the nearest preset before render (`Apps/Lillist-iOS/Sources/Settings/TrashSection.swift:14`).

## External deps

- SwiftUI — every section is a `View`; sheets, pickers, `fileImporter`/`fileExporter`
- UIKit — `UIApplication.openSettingsURLString` to deep-link into system settings
- UniformTypeIdentifiers — `.folder`/`.zip` content types for import/export pickers

## Gotchas

- `DiagnosticsSection` defers building the exporter until the include sheet fully dismisses, so the two presentations never conflict (`Apps/Lillist-iOS/Sources/Settings/DiagnosticsSection.swift:52`).
- `CrashReportingSection` mirrors the toggle into the live env immediately because the current session's `CrashReporterHost` reads a `var` (`Apps/Lillist-iOS/Sources/Settings/CrashReportingSection.swift:24`).
- `NotificationsSection` debounces reminder-time edits with a 750ms `Task.sleep` keyed on the time values before calling the scheduler (`Apps/Lillist-iOS/Sources/Settings/NotificationsSection.swift:46`).
- `MigrationPhase` gains `Identifiable` via a `@retroactive` extension; any second conformance elsewhere will conflict at link time (`Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:208`).
