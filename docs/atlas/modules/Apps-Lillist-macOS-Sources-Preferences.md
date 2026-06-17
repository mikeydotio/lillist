---
module: Apps/Lillist-macOS/Sources/Preferences
summary: "macOS Settings scene — eight env-coupled preference panes wrapping LillistCore stores and LillistUI sections"
read_when: "Touching macOS Preferences panes, iCloud sync toggle, notifications, trash, quick capture, diagnostics, or export/import"
sources:
  - path: Apps/Lillist-macOS/Sources/Preferences/AdvancedPane.swift
  - path: Apps/Lillist-macOS/Sources/Preferences/CrashReportingPane.swift
  - path: Apps/Lillist-macOS/Sources/Preferences/DiagnosticsPane.swift
  - path: Apps/Lillist-macOS/Sources/Preferences/GeneralPane.swift
  - path: Apps/Lillist-macOS/Sources/Preferences/ICloudSyncPane.swift
  - path: Apps/Lillist-macOS/Sources/Preferences/NotificationsPane.swift
  - path: Apps/Lillist-macOS/Sources/Preferences/PreferencesWindow.swift
  - path: Apps/Lillist-macOS/Sources/Preferences/QuickCapturePane.swift
  - path: Apps/Lillist-macOS/Sources/Preferences/TrashPane.swift
references_modules: [Apps-Lillist-macOS-Sources-misc, Apps-Lillist-macOS-Sources-Hotkey, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistCore-Sources-LillistCore-Export, Packages-LillistCore-Sources-LillistCore-Diagnostics, Packages-LillistCore-Sources-LillistCore-Notifications, Packages-LillistCore-Sources-LillistCore-Sync-chunk-1, Packages-LillistUI-Sources-LillistUI-Settings, Packages-LillistUI-Sources-LillistUI-Sync, Packages-LillistUI-Sources-LillistUI-Accessibility]
generator: cartographer/1 model=claude-sonnet-4-6
---

# Module: Apps/Lillist-macOS/Sources/Preferences

## Purpose

The macOS `Settings { … }` scene: `PreferencesWindow` hosts eight tabbed panes
(iCloud Sync, General, Notifications, Trash, Quick Capture, Crash Reporting,
Diagnostics, Advanced). Each pane is a thin SwiftUI `View` that reads
`AppEnvironment` via `@Environment`, renders a self-sizing `Form`, and writes
mutations back through LillistCore stores — keeping all persistence and scheduling
logic out of the view layer while the panes own only `@State` and presentation.

## Public API

All panes are internal `struct`s consumed only by `PreferencesWindow`; the scene
itself is the module's single externally-instantiated surface.

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AdvancedPane` | struct | `Apps/Lillist-macOS/Sources/Preferences/AdvancedPane.swift:14` | Data export/import + reveal-store-in-Finder actions |
| `CrashReportingPane` | struct | `Apps/Lillist-macOS/Sources/Preferences/CrashReportingPane.swift:11` | Crash-prompt toggle + sample-report disclosure |
| `DiagnosticsPane` | struct | `Apps/Lillist-macOS/Sources/Preferences/DiagnosticsPane.swift:11` | Device-local logging toggle + diagnostic package export |
| `GeneralPane` | struct | `Apps/Lillist-macOS/Sources/Preferences/GeneralPane.swift:11` | Default sort + default tag tint defaults |
| `ICloudSyncPane` | struct | `Apps/Lillist-macOS/Sources/Preferences/ICloudSyncPane.swift:9` | Sync toggle + owns migration confirm/progress sheets |
| `NotificationsPane` | struct | `Apps/Lillist-macOS/Sources/Preferences/NotificationsPane.swift:18` | All-day/morning-summary times + permission test |
| `PreferencesWindow` | struct | `Apps/Lillist-macOS/Sources/Preferences/PreferencesWindow.swift:9` | Root `TabView` of the Settings scene; `.toggleStyle(.rainbow)` |
| `QuickCapturePane` | struct | `Apps/Lillist-macOS/Sources/Preferences/QuickCapturePane.swift:13` | Quick Capture toggles + global hotkey recorder |
| `TrashPane` | struct | `Apps/Lillist-macOS/Sources/Preferences/TrashPane.swift:9` | Retention slider + empty-trash action |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `runMigration` | func | `Apps/Lillist-macOS/Sources/Preferences/ICloudSyncPane.swift:176` | Drives every enable/disable; subscribes to coordinator `progressStream` into `activePhase` |
| `MigrationPhase` (Identifiable) | extension | `Apps/Lillist-macOS/Sources/Preferences/ICloudSyncPane.swift:195` | Retroactive `id` lets the LillistCore phase drive `.sheet(item:)` |
| `applySchedulerSideEffects` | func | `Apps/Lillist-macOS/Sources/Preferences/NotificationsPane.swift:124` | Reconciles scheduler caches synchronously on any all-day/morning-summary change |
| `subscribe` | func | `Apps/Lillist-macOS/Sources/Preferences/GeneralPane.swift:47` | Shared prefs-stream pattern: initial `read()` then `prefsStream`, echo-suppressed |
| `loggingBinding` | var | `Apps/Lillist-macOS/Sources/Preferences/DiagnosticsPane.swift:79` | Write-through binding so `.task` hydration never echoes back as a write |

## Relationships

- `Apps-Lillist-macOS-Sources-Preferences.GeneralPane -> Apps-Lillist-macOS-Sources-misc.AppEnvironment (reads)` — `@Environment(AppEnvironment.self)` in every pane (`Apps/Lillist-macOS/Sources/Preferences/GeneralPane.swift:12`)
- `Apps-Lillist-macOS-Sources-Preferences.GeneralPane -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.PreferencesStore (reads)` — subscribes to `prefsStream` and calls `preferencesStore.update` (`Apps/Lillist-macOS/Sources/Preferences/GeneralPane.swift:56`)
- `Apps-Lillist-macOS-Sources-Preferences.NotificationsPane -> Packages-LillistCore-Sources-LillistCore-Notifications.NotificationScheduler (calls)` — `applySchedulerSideEffects` calls `updateDefaultAllDayTime`, `installMorningSummary`, `uninstallMorningSummary` (`Apps/Lillist-macOS/Sources/Preferences/NotificationsPane.swift:133`)
- `Apps-Lillist-macOS-Sources-Preferences.TrashPane -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (calls)` — `emptyTrash` calls `environment.taskStore.purgeAll()` (`Apps/Lillist-macOS/Sources/Preferences/TrashPane.swift:97`)
- `Apps-Lillist-macOS-Sources-Preferences.TrashPane -> Packages-LillistUI-Sources-LillistUI-Accessibility.AccessibilityAnnouncements (calls)` — posts result string with priority after purge (`Apps/Lillist-macOS/Sources/Preferences/TrashPane.swift:103`)
- `Apps-Lillist-macOS-Sources-Preferences.ICloudSyncPane -> Packages-LillistUI-Sources-LillistUI-Sync.ICloudSyncSettingsSection (calls)` — instantiates `ICloudSyncSettingsSection(viewState:actions:)` (`Apps/Lillist-macOS/Sources/Preferences/ICloudSyncPane.swift:20`)
- `Apps-Lillist-macOS-Sources-Preferences.ICloudSyncPane -> Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationChoiceSheet (calls)` — sheet on enable toggle (`Apps/Lillist-macOS/Sources/Preferences/ICloudSyncPane.swift:30`)
- `Apps-Lillist-macOS-Sources-Preferences.ICloudSyncPane -> Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationProgressSheet (calls)` — sheet keyed on `activePhase` (`Apps/Lillist-macOS/Sources/Preferences/ICloudSyncPane.swift:52`)
- `Apps-Lillist-macOS-Sources-Preferences.ICloudSyncPane -> Packages-LillistUI-Sources-LillistUI-Sync.SyncDisableConfirmationSheet (calls)` — sheet on disable toggle (`Apps/Lillist-macOS/Sources/Preferences/ICloudSyncPane.swift:60`)
- `Apps-Lillist-macOS-Sources-Preferences.ICloudSyncPane -> Packages-LillistUI-Sources-LillistUI-Sync.PauseExplainerDialog (calls)` — sheet when paused indicator is tapped (`Apps/Lillist-macOS/Sources/Preferences/ICloudSyncPane.swift:74`)
- `Apps-Lillist-macOS-Sources-Preferences.ICloudSyncPane -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.MigrationCoordinator (calls)` — `runMigration` calls `beginEnable`/`beginDisable` and reads `progressStream` (`Apps/Lillist-macOS/Sources/Preferences/ICloudSyncPane.swift:164`)
- `Apps-Lillist-macOS-Sources-Preferences.AdvancedPane -> Packages-LillistCore-Sources-LillistCore-Export.Exporter (calls)` — `runExport` constructs `Exporter(persistence:preferences:)` and calls `.export(to:)` (`Apps/Lillist-macOS/Sources/Preferences/AdvancedPane.swift:92`)
- `Apps-Lillist-macOS-Sources-Preferences.AdvancedPane -> Packages-LillistCore-Sources-LillistCore-Export.Importer (calls)` — `runImport` constructs `Importer(persistence:)` and calls `.importBundle(at:conflictPolicy:)` (`Apps/Lillist-macOS/Sources/Preferences/AdvancedPane.swift:114`)
- `Apps-Lillist-macOS-Sources-Preferences.DiagnosticsPane -> Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticPackageBuilder (calls)` — `prepare()` constructs and calls `builder.build(options:)` (`Apps/Lillist-macOS/Sources/Preferences/DiagnosticsPane.swift:104`)
- `Apps-Lillist-macOS-Sources-Preferences.QuickCapturePane -> Apps-Lillist-macOS-Sources-Hotkey.GlobalHotkeyMonitor (calls)` — `onChange` calls `monitor.reregister(combo:)` after prefs write (`Apps/Lillist-macOS/Sources/Preferences/QuickCapturePane.swift:49`)

## Type notes

Panes are SwiftUI `View` structs (`@MainActor` via the protocol); none own
persistent state. The recurring pattern across General/Notifications/Trash/
QuickCapture/CrashReporting: hold `@State private var prefs: PreferencesStore.Prefs?`,
hydrate via `subscribe()` (initial `read()` then `prefsStream`), gate a derived
`binding`, and on `onChange(of: prefs)` write the full snapshot via
`preferencesStore.update`. `DiagnosticsPane` deviates — its toggle lives in
`DevicePreferencesStore`, so it uses local `@State` + a write-through binding and
a `didHydrate` guard (`Apps/Lillist-macOS/Sources/Preferences/DiagnosticsPane.swift:83`) instead of the prefs stream.
`ICloudSyncPane` owns the migration UI: `runMigration` spawns a phase-stream task
that mutates `activePhase`, cancelled via `defer` (`Apps/Lillist-macOS/Sources/Preferences/ICloudSyncPane.swift:185`); the
retroactive `MigrationPhase: Identifiable` conformance keys the progress
`.sheet(item:)`. Every pane ends in `.fixedSize()` so the pane content drives the
window size and the `TabView` animates between tabs (`Apps/Lillist-macOS/Sources/Preferences/PreferencesWindow.swift:31`).

## External deps

- SwiftUI — `Form`/`TabView`/`Settings` scene; all pane bodies
- AppKit — `NSOpenPanel`, `NSWorkspace` (export dir picks, reveal-in-Finder, open System Settings)
- UniformTypeIdentifiers — `.zip` content type for the diagnostics `.fileExporter`
