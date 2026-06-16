---
module: Apps/Lillist-macOS/Sources/Preferences
summary: "macOS Settings scene — eight env-coupled preference panes wrapping LillistCore stores and LillistUI sections"
read_when: "macOS Preferences panes"
sources:
  - path: Apps/Lillist-macOS/Sources/Preferences/AdvancedPane.swift
    blob: d89420303de7b130199435dc699956cff06ff2f0
  - path: Apps/Lillist-macOS/Sources/Preferences/CrashReportingPane.swift
    blob: 312ea7bc27fa054e887e39c71e5dd9cc4972a14c
  - path: Apps/Lillist-macOS/Sources/Preferences/DiagnosticsPane.swift
    blob: 86fc83af2047fc182ca7de9e1937aec14e208bde
  - path: Apps/Lillist-macOS/Sources/Preferences/GeneralPane.swift
    blob: a602b3a6e933cb743488655d4afb9327b6bad435
  - path: Apps/Lillist-macOS/Sources/Preferences/ICloudSyncPane.swift
    blob: 525535d588bc6f86021c5d604e1221dcb6b0ef74
  - path: Apps/Lillist-macOS/Sources/Preferences/NotificationsPane.swift
    blob: 97b81ffa9738b1d17d8b99e163a8ca5645203f67
  - path: Apps/Lillist-macOS/Sources/Preferences/PreferencesWindow.swift
    blob: 28817f36b86d2de4a1505301f64534ae2e45981d
  - path: Apps/Lillist-macOS/Sources/Preferences/QuickCapturePane.swift
    blob: b66909ec19bf98e3361b4d5dcdbec551b82adb1c
  - path: Apps/Lillist-macOS/Sources/Preferences/TrashPane.swift
    blob: 915336ea3a34d64d61da2fbd11f3d9f9c6fe239f
references_modules: [Apps-Lillist-macOS-Sources-misc, Apps-Lillist-macOS-Sources-Hotkey, Packages-LillistCore-Sources-LillistCore-Persistence, Packages-LillistCore-Sources-LillistCore-Sync-chunk-1, Packages-LillistUI-Sources-LillistUI-Settings, Packages-LillistUI-Sources-LillistUI-Sync, Packages-LillistUI-Sources-LillistUI-iOS-misc, Packages-LillistUI-Sources-LillistUI-Accessibility]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
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

- `Apps-Lillist-macOS-Sources-Preferences.GeneralPane -> Apps-Lillist-macOS-Sources-misc.AppEnvironment (reads)`
- `Apps-Lillist-macOS-Sources-Preferences.GeneralPane -> Packages-LillistCore-Sources-LillistCore-Persistence.PreferencesStore (reads)`
- `Apps-Lillist-macOS-Sources-Preferences.NotificationsPane -> Packages-LillistCore-Sources-LillistCore-Persistence.PreferencesStore (writes)`
- `Apps-Lillist-macOS-Sources-Preferences.ICloudSyncPane -> Packages-LillistUI-Sources-LillistUI-Settings.ICloudSyncSettingsSection (calls)`
- `Apps-Lillist-macOS-Sources-Preferences.ICloudSyncPane -> Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationProgressSheet (calls)`
- `Apps-Lillist-macOS-Sources-Preferences.ICloudSyncPane -> Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationChoiceSheet (calls)`
- `Apps-Lillist-macOS-Sources-Preferences.ICloudSyncPane -> Packages-LillistUI-Sources-LillistUI-Sync.SyncDisableConfirmationSheet (calls)`
- `Apps-Lillist-macOS-Sources-Preferences.ICloudSyncPane -> Packages-LillistUI-Sources-LillistUI-Sync.PauseExplainerDialog (calls)`
- `Apps-Lillist-macOS-Sources-Preferences.ICloudSyncPane -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.MigrationCoordinator (calls)`
- `Apps-Lillist-macOS-Sources-Preferences.ICloudSyncPane -> Packages-LillistCore-Sources-LillistCore-Persistence.MigrationPhase (extends)`
- `Apps-Lillist-macOS-Sources-Preferences.QuickCapturePane -> Apps-Lillist-macOS-Sources-Hotkey.HotkeyRecorder (calls)`
- `Apps-Lillist-macOS-Sources-Preferences.QuickCapturePane -> Apps-Lillist-macOS-Sources-Hotkey.GlobalHotkeyMonitor (calls)`
- `Apps-Lillist-macOS-Sources-Preferences.DiagnosticsPane -> Packages-LillistUI-Sources-LillistUI-iOS-misc.DiagnosticsIncludeSheet (calls)`
- `Apps-Lillist-macOS-Sources-Preferences.DiagnosticsPane -> Packages-LillistUI-Sources-LillistUI-iOS-misc.DiagnosticZipDocument (owns)`
- `Apps-Lillist-macOS-Sources-Preferences.TrashPane -> Packages-LillistUI-Sources-LillistUI-Accessibility.AccessibilityAnnouncements (calls)`

## Type notes

Panes are SwiftUI `View` structs (`@MainActor` via the protocol); none own
persistent state. The recurring pattern across General/Notifications/Trash/
QuickCapture/CrashReporting: hold `@State private var prefs: PreferencesStore.Prefs?`,
hydrate via `subscribe()` (initial `read()` then `prefsStream`), gate a derived
`binding`, and on `onChange(of: prefs)` write the full snapshot via
`preferencesStore.update`. `DiagnosticsPane` deviates — its toggle lives in
`DevicePreferencesStore`, so it uses local `@State` + a write-through binding and
a `didHydrate` guard (`DiagnosticsPane.swift:83`) instead of the prefs stream.
`ICloudSyncPane` owns the migration UI: `runMigration` spawns a phase-stream task
that mutates `activePhase`, cancelled via `defer` (`ICloudSyncPane.swift:185`); the
retroactive `MigrationPhase: Identifiable` conformance keys the progress
`.sheet(item:)`. Every pane ends in `.fixedSize()` so the pane content drives the
window size and the `TabView` animates between tabs (`PreferencesWindow.swift:31`).

## External deps

- SwiftUI — `Form`/`TabView`/`Settings` scene; all pane bodies
- AppKit — `NSOpenPanel`, `NSWorkspace` (export dir picks, reveal-in-Finder, open System Settings)
- UniformTypeIdentifiers — `.zip` content type for the diagnostics `.fileExporter`
