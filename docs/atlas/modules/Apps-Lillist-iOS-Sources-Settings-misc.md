---
module: "Apps/Lillist-iOS/Sources/Settings (misc)"
summary: "iOS Settings landing view and env-coupled sections: sync, notifications, trash, backup, diagnostics."
read_when: "Touching iOS Settings screens"
sources:
  - path: Apps/Lillist-iOS/Sources/Settings/AdvancedSection.swift
    blob: 16cfb82d01a4ffc73a1cef2fd36960e58c4d2829
  - path: Apps/Lillist-iOS/Sources/Settings/BackupSection.swift
    blob: 9de8c3e16a4da35983fd6914496d67258e9c1ce1
  - path: Apps/Lillist-iOS/Sources/Settings/CrashReportingSection.swift
    blob: 0a6c119b7f6e45aa2db51acd27b2176627b1b308
  - path: Apps/Lillist-iOS/Sources/Settings/DiagnosticsSection.swift
    blob: afeafdf9990d22c3fa4c758946a3ccd56529c834
  - path: Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift
    blob: 323be3ad575e487b01656468b1d7b0c348725e60
  - path: Apps/Lillist-iOS/Sources/Settings/NotificationsSection.swift
    blob: 254a5ffeb365bd10ddca648b74241275df310079
  - path: Apps/Lillist-iOS/Sources/Settings/QuickCaptureSection.swift
    blob: bf450601d8c0b95a98aee0f0ea499f2eeffeca61
  - path: Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift
    blob: d0376ca5e47433b56769bde02fb1fbe81a6e5e0a
  - path: Apps/Lillist-iOS/Sources/Settings/ResetDataStoreSection.swift
    blob: 429f833edb09a6ad03185a32c739805395ed665e
  - path: Apps/Lillist-iOS/Sources/Settings/SettingsTab.swift
    blob: 62e7e6734a310a6b9dbf54eb20b3df3081356761
  - path: Apps/Lillist-iOS/Sources/Settings/TrashSection.swift
    blob: 047a2d56222b6c4b659d138012e3afa69d484205
references_modules: [Apps-Lillist-iOS-Sources-Settings-Pages, Apps-Lillist-macOS-Sources-Hotkey, Packages-LillistCore-Sources-LillistCore-Backup, Packages-LillistCore-Sources-LillistCore-Diagnostics, Packages-LillistCore-Sources-LillistCore-Export, Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistCore-Sources-LillistCore-Notifications, Packages-LillistCore-Sources-LillistCore-Reminders, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistCore-Sources-LillistCore-Sync-chunk-1, Packages-LillistCore-Sources-LillistCore-misc, Packages-LillistUI-Sources-LillistUI-Accessibility, Packages-LillistUI-Sources-LillistUI-Settings, Packages-LillistUI-Sources-LillistUI-Sync, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1, Packages-LillistUI-Sources-LillistUI-iOS-misc]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Apps/Lillist-iOS/Sources/Settings (misc)

## Purpose

This module is the iOS Settings infrastructure: `SettingsTab` provides the icon-tile landing navigation, and the section components (`NotificationsSection`, `ICloudSyncSection`, `TrashSection`, `BackupSection`, `DiagnosticsSection`, `RemindersImportSection`, `CrashReportingSection`, `AdvancedSection`, `QuickCaptureSection`, `ResetDataStoreSection`) compose into the sub-pages. These sections are env-coupled — they read `AppEnvironment` directly and bridge user gestures into LillistCore operations — because they depend on stores (`DevicePreferencesStore`, `MigrationCoordinator`, `TaskStore`, etc.) that LillistUI cannot import. Without this layer, iOS Settings would have no connection to app state: the LillistUI shell (`SettingsScreen`) would have chrome but no content capable of reading or writing live data.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AdvancedSection` | struct | `Apps/Lillist-iOS/Sources/Settings/AdvancedSection.swift:6` | Renders an Advanced section with export-to-tmp-dir and import-from-picker actions; requires `AppEnvironment` in the SwiftUI environment; async state is self-contained. |
| `BackupSection` | struct | `Apps/Lillist-iOS/Sources/Settings/BackupSection.swift:9` | Lists timestamped snapshots, creates on demand, shares, and restores; requires `AppEnvironment` with `backupSnapshotManager` and `backupRestoreService`; restore is gated on schema compatibility preflight and a destructive confirmation. |
| `CrashReportingSection` | struct | `Apps/Lillist-iOS/Sources/Settings/CrashReportingSection.swift:5` | Renders crash-reporting toggle and collapsible sample report; requires `Binding<PreferencesStore.Prefs>` and `AppEnvironment`; writes `crashPromptsEnabled` to both the prefs binding and the live env on change. |
| `DiagnosticsSection` | struct | `Apps/Lillist-iOS/Sources/Settings/DiagnosticsSection.swift:11` | Renders diagnostic-logging toggle and package-export flow; requires `AppEnvironment`; hydrates `enabled` once via `.task` with a `didHydrate` guard to prevent races with user taps. |
| `ICloudSyncSection` | struct | `Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:10` | Owns all iCloud sync migration sheet state (choice, confirmation, progress, disable, pause explainer); requires `AppEnvironment`; drives `MigrationCoordinator` for enable/disable and streams `progressStream` into the progress sheet. |
| `MigrationPhase` | extension | `Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:208` | Retroactively conforms `MigrationPhase` to `Identifiable` with a stable string `id` per case, enabling use as a `.fullScreenCover(item:)` binding in `ICloudSyncSection`. |
| `NotificationsSection` | struct | `Apps/Lillist-iOS/Sources/Settings/NotificationsSection.swift:5` | Renders all-day time, morning-summary, and notification-permission sections; requires `Binding<PreferencesStore.Prefs>` and `AppEnvironment`; debounces scheduler writes 750ms after preference changes. |
| `QuickCaptureSection` | struct | `Apps/Lillist-iOS/Sources/Settings/QuickCaptureSection.swift:4` | Renders the floating-button toggle and a Shortcuts deeplink; requires only `Binding<PreferencesStore.Prefs>`; no async operations. |
| `RemindersImportSection` | struct | `Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift:13` | Controls Reminders import: enable/list selection/manual drain; requires `AppEnvironment`; reads and writes `DevicePreferencesStore` (device-local, not synced); requests Reminders permission on first enable. |
| `ResetDataStoreSection` | struct | `Apps/Lillist-iOS/Sources/Settings/ResetDataStoreSection.swift:11` | Offers irreversible full data-store reset behind a destructive confirmation; requires `AppEnvironment` with `dataStoreReset`; posts an accessibility announcement on success or failure. |
| `SettingsTab` | struct | `Apps/Lillist-iOS/Sources/Settings/SettingsTab.swift:15` | iOS Settings landing view; loads `PreferencesStore.Prefs` on appear, writes back on change, and renders icon-tile rows that navigate into focused sub-pages; requires `AppEnvironment`. |
| `TrashSection` | struct | `Apps/Lillist-iOS/Sources/Settings/TrashSection.swift:5` | Renders trash-retention picker and empty-trash action; requires `Binding<PreferencesStore.Prefs>` and `AppEnvironment`; `init` coerces any legacy non-preset retention value to the nearest preset. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `backupNow` | func | `Apps/Lillist-iOS/Sources/Settings/BackupSection.swift:104` | Detaches `createSnapshot()` so the non-actor-isolated `BackupSnapshotManager` doesn't block MainActor, then reloads the list and announces the result; the `Task.detached` is the load-bearing detail (`Apps/Lillist-iOS/Sources/Settings/BackupSection.swift:104-117`). |
| `drainNow` | func | `Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift:121` | The only manual-drain path from Settings: calls `remindersImporter.drainIfNeeded()` and surfaces the imported count as a status message (`Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift:121-126`). |
| `emptyTrash` | func | `Apps/Lillist-iOS/Sources/Settings/TrashSection.swift:77` | The only path for manual trash emptying from Settings: calls `taskStore.purgeAll()` and announces the result via `AccessibilityAnnouncements`; destructive and iCloud-propagating (`Apps/Lillist-iOS/Sources/Settings/TrashSection.swift:77-92`). |
| `handleToggle` | func | `Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:118` | Single decision point routing the sync toggle: on→`showChoiceSheet`, off→`showDisableSheet`; without it, the toggle has no coordinator path (`Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:118-124`). |
| `isAvailable` | func | `Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:132` | Maps `iCloudAccountState` to a Bool; called three times in `viewState` to derive `iCloudAvailable`, `isToggleDisabled`, and the disabled footer text (`Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:132-135`). |
| `loadIfNeeded` | func | `Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift:88` | Single-pass initializer for the section: reads enabled flag, list ID, and authorization from device prefs, then conditionally loads lists; `didLoad` guard prevents redundant async fetches on re-renders (`Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift:88-97`). |
| `loadSnapshots` | func | `Apps/Lillist-iOS/Sources/Settings/BackupSection.swift:100` | Populates `snapshots` on `.task`; drives the entire backup list render; silently swallows errors so a missing snapshot dir shows an empty list rather than a crash (`Apps/Lillist-iOS/Sources/Settings/BackupSection.swift:100-102`). |
| `prepare` | func | `Apps/Lillist-iOS/Sources/Settings/DiagnosticsSection.swift:91` | Assembles `DiagnosticPackageBuilder.Metadata`, builds the zip, wraps it in `DiagnosticZipDocument`, removes the tmp file, and triggers `fileExporter`; called only after the include sheet fully dismisses to avoid conflicting presentations (`Apps/Lillist-iOS/Sources/Settings/DiagnosticsSection.swift:91-115`). |
| `prepareRestore` | func | `Apps/Lillist-iOS/Sources/Settings/BackupSection.swift:119` | Runs schema-compatibility preflight before presenting the destructive confirmation; gates restore behind `pre.isCompatible`, preventing cross-version data corruption (`Apps/Lillist-iOS/Sources/Settings/BackupSection.swift:119-134`). |
| `refreshLists` | func | `Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift:117` | Fetches the current Reminders lists and populates the picker; called from `loadIfNeeded`, `setEnabled`, and `requestAccess` — the shared refresh step across all authorization-change paths (`Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift:117-119`). |
| `requestAccess` | func | `Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift:109` | The sole Reminders permission-request path: requests access, re-checks authorization, and conditionally refreshes lists; fan-in of 3 (`setEnabled`, body button, `loadIfNeeded` chain) (`Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift:109-115`). |
| `runExport` | func | `Apps/Lillist-iOS/Sources/Settings/AdvancedSection.swift:67` | The only export path from Settings: creates the tmp directory, instantiates `Exporter` with persistence and preferences, calls `export(to:)`, and surfaces the resulting URL for `ShareLink` (`Apps/Lillist-iOS/Sources/Settings/AdvancedSection.swift:67-84`). |
| `runImport` | func | `Apps/Lillist-iOS/Sources/Settings/AdvancedSection.swift:86` | Bridges the iOS security-scoped file picker to `Importer.importBundle`; correctly calls `startAccessingSecurityScopedResource` / `stopAccessingSecurityScopedResource` so the sandbox access stays open for the import (`Apps/Lillist-iOS/Sources/Settings/AdvancedSection.swift:86-99`). |
| `runMigration` | func | `Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:189` | Central migration driver: streams `coordinator.progressStream` into `activePhase` on `@MainActor` so the progress sheet reflects live state, falls back to a tmp storeURL for test fixtures, and maps thrown errors to `.failed(reason:)`; all enable and disable paths funnel through it (`Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:189-205`). |
| `runRestore` | func | `Apps/Lillist-iOS/Sources/Settings/BackupSection.swift:136` | Executes the iCloud-propagating restore via `backupRestoreService.restore`; the point of no return — all data on every device on the account is replaced; announces completion for accessibility (`Apps/Lillist-iOS/Sources/Settings/BackupSection.swift:136-147`). |
| `setEnabled` | func | `Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift:99` | The single action invoked by `enabledBinding`'s setter (Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift:70) when the toggle changes. It chains three responsibilities: persists the new state to `DevicePreferencesStore`, triggers `requestAccess()` when permission is still undetermined, and calls `refreshLists()` when already authorized — making it the pivot between a UI toggle flip and the downstream permission + list-load side effects. |
| `triggerDisable` | func | `Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:177` | Converts `DisableStrategy` to the `coordinator.beginDisable` closure and schedules via `runMigration`; the sole entry point for all sync-disable flows from the Settings UI (`Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:177-181`). |
| `triggerEnable` | func | `Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:170` | Converts `SyncMigrationConfirmationDialog.Direction` to `EnableDirection` and schedules via `runMigration`; the sole entry point for all sync-enable flows from the Settings UI (`Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:170-175`). |

## Relationships

- `Apps-Lillist-iOS-Sources-Settings-misc.AdvancedSection -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Apps-Lillist-iOS-Sources-Settings-misc.BackupSection -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Apps-Lillist-iOS-Sources-Settings-misc.CrashReportingSection -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Apps-Lillist-iOS-Sources-Settings-misc.CrashReportingSection -> Packages-LillistUI-Sources-LillistUI-Settings.preview (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.DiagnosticsSection -> Packages-LillistCore-Sources-LillistCore-misc.diagnosticLoggingEnabled (reads)`
- `Apps-Lillist-iOS-Sources-Settings-misc.DiagnosticsSection -> Packages-LillistCore-Sources-LillistCore-misc.setDiagnosticLoggingEnabled (writes)`
- `Apps-Lillist-iOS-Sources-Settings-misc.DiagnosticsSection -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Apps-Lillist-iOS-Sources-Settings-misc.DiagnosticsSection -> Packages-LillistUI-Sources-LillistUI-iOS-misc.DiagnosticsIncludeSheet (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.ICloudSyncSection -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.ICloudSyncSection -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Apps-Lillist-iOS-Sources-Settings-misc.ICloudSyncSection -> Packages-LillistUI-Sources-LillistUI-Settings.ICloudSyncSettingsSection (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.ICloudSyncSection -> Packages-LillistUI-Sources-LillistUI-Sync.PauseExplainerDialog (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.ICloudSyncSection -> Packages-LillistUI-Sources-LillistUI-Sync.SyncDisableConfirmationSheet (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.ICloudSyncSection -> Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationChoiceSheet (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.ICloudSyncSection -> Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationProgressSheet (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.MorningKey -> Apps-Lillist-macOS-Sources-Hotkey.open (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.MorningKey -> Packages-LillistCore-Sources-LillistCore-Notifications.currentStatus (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.NotificationsSection -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Apps-Lillist-iOS-Sources-Settings-misc.RemindersImportSection -> Packages-LillistCore-Sources-LillistCore-misc.setRemindersImportListID (writes)`
- `Apps-Lillist-iOS-Sources-Settings-misc.RemindersImportSection -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Apps-Lillist-iOS-Sources-Settings-misc.ResetDataStoreSection -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Apps-Lillist-iOS-Sources-Settings-misc.SettingsTab -> Apps-Lillist-iOS-Sources-Settings-Pages.AppearancePage (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.SettingsTab -> Apps-Lillist-iOS-Sources-Settings-Pages.DataManagementPage (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.SettingsTab -> Apps-Lillist-iOS-Sources-Settings-Pages.DebugPage (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.SettingsTab -> Apps-Lillist-iOS-Sources-Settings-Pages.ICloudSyncPage (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.SettingsTab -> Apps-Lillist-iOS-Sources-Settings-Pages.NotificationsPage (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.SettingsTab -> Apps-Lillist-iOS-Sources-Settings-Pages.QuickCapturePage (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.SettingsTab -> Apps-Lillist-iOS-Sources-Settings-Pages.RemindersImportPage (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.SettingsTab -> Apps-Lillist-iOS-Sources-Settings-Pages.TaskDefaultsPage (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.SettingsTab -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Apps-Lillist-iOS-Sources-Settings-misc.SettingsTab -> Packages-LillistUI-Sources-LillistUI-iOS-misc.SettingsScreen (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.TrashSection -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.TrashSection -> Packages-LillistUI-Sources-LillistUI-Accessibility.value (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.TrashSection -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Apps-Lillist-iOS-Sources-Settings-misc.announce -> Packages-LillistUI-Sources-LillistUI-Accessibility.post (emits)`
- `Apps-Lillist-iOS-Sources-Settings-misc.applyAllDayChange -> Packages-LillistCore-Sources-LillistCore-Notifications.updateDefaultAllDayTime (writes)`
- `Apps-Lillist-iOS-Sources-Settings-misc.applyMorningSummaryChange -> Packages-LillistCore-Sources-LillistCore-Notifications.installMorningSummary (writes)`
- `Apps-Lillist-iOS-Sources-Settings-misc.applyMorningSummaryChange -> Packages-LillistCore-Sources-LillistCore-Notifications.uninstallMorningSummary (writes)`
- `Apps-Lillist-iOS-Sources-Settings-misc.backupNow -> Packages-LillistCore-Sources-LillistCore-Backup.createSnapshot (writes)`
- `Apps-Lillist-iOS-Sources-Settings-misc.backupNow -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.drainNow -> Packages-LillistCore-Sources-LillistCore-Reminders.drainIfNeeded (writes)`
- `Apps-Lillist-iOS-Sources-Settings-misc.emptyTrash -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.emptyTrash -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.purgeAll (writes)`
- `Apps-Lillist-iOS-Sources-Settings-misc.emptyTrash -> Packages-LillistUI-Sources-LillistUI-Accessibility.post (emits)`
- `Apps-Lillist-iOS-Sources-Settings-misc.isAvailable -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.loadIfNeeded -> Packages-LillistCore-Sources-LillistCore-misc.remindersImportEnabled (reads)`
- `Apps-Lillist-iOS-Sources-Settings-misc.loadIfNeeded -> Packages-LillistCore-Sources-LillistCore-misc.remindersImportListID (reads)`
- `Apps-Lillist-iOS-Sources-Settings-misc.loadSnapshots -> Packages-LillistCore-Sources-LillistCore-Backup.listSnapshots (reads)`
- `Apps-Lillist-iOS-Sources-Settings-misc.navRow -> Packages-LillistUI-Sources-LillistUI-Settings.SettingsRowIcon (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.openSystemSettings -> Apps-Lillist-macOS-Sources-Hotkey.open (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.prepare -> Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticPackageBuilder (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.prepare -> Packages-LillistCore-Sources-LillistCore-Diagnostics.Metadata (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.prepare -> Packages-LillistCore-Sources-LillistCore-Diagnostics.diagnosticsDirectory (reads)`
- `Apps-Lillist-iOS-Sources-Settings-misc.prepare -> Packages-LillistUI-Sources-LillistUI-iOS-misc.DiagnosticZipDocument (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.prepareRestore -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.runExport -> Packages-LillistCore-Sources-LillistCore-Export.Exporter (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.runExport -> Packages-LillistCore-Sources-LillistCore-Export.export (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.runImport -> Packages-LillistCore-Sources-LillistCore-Export.Importer (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.runImport -> Packages-LillistCore-Sources-LillistCore-Export.importBundle (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.runReset -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`

## Type notes

Every section view reads `AppEnvironment` via `@Environment(AppEnvironment.self)` — they are env-coupled presenters, not the pure-presentation LillistUI screens that take closures at init.

`RemindersImportSection` is deliberately device-only: it reads/writes `DevicePreferencesStore` (not the CloudKit-synced `PreferencesStore`) because Reminders `calendarIdentifier` values are device-local, so the section owns its own `@State enabled`/`selectedListID` rather than sharing the `PreferencesStore.Prefs` binding used by other sections (`Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift:6-12`).

`NotificationsSection` debounces scheduler calls with `.task(id: AllDayKey(...))`/`.task(id: MorningKey(...))`: changes sleep 750ms before `applyAllDayChange`/`applyMorningSummaryChange` fire, so rapid picker adjustments don't flood `NotificationScheduler` (`Apps/Lillist-iOS/Sources/Settings/NotificationsSection.swift:46-61`).

`DiagnosticsSection` uses a `didHydrate` flag to guard the one-shot `.task` read: if the user taps the toggle before the async read returns, the stale read is discarded (`Apps/Lillist-iOS/Sources/Settings/DiagnosticsSection.swift:46-50`).

`ICloudSyncSection.runMigration` streams `coordinator.progressStream` into `activePhase` on `@MainActor`; all enable and disable flows funnel through it so the progress sheet always reflects live migration state (`Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:189-205`).

`TrashSection.init` coerces any pre-Plan-26 arbitrary `trashRetentionDays` value to the nearest discrete preset so the `Picker` always has a matching tag (`Apps/Lillist-iOS/Sources/Settings/TrashSection.swift:16-22`).

## External deps

- LillistCore — imported
- LillistUI — imported
- SwiftUI — imported
- UIKit — imported
- UniformTypeIdentifiers — imported

## Gotchas

`DiagnosticsSection` presents `fileExporter` only after the include sheet fully dismisses via `onDismiss` — presenting two sheets simultaneously conflicts on iOS; `wantsExport` defers `prepare()` until the first sheet is gone (`Apps/Lillist-iOS/Sources/Settings/DiagnosticsSection.swift:52-55`).

`DiagnosticsSection` `didHydrate` guards against a late async `.task` read overwriting a user-initiated toggle change (`Apps/Lillist-iOS/Sources/Settings/DiagnosticsSection.swift:46-50, 81`).

`ICloudSyncSection.runMigration` falls back to a temp SQLite path when `environment.storeURL` is nil so test-fixture paths don't crash (`Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:190-192`).

`TrashSection.init` coerces legacy non-preset `trashRetentionDays` to nearest preset; skipping this leaves the `Picker` with no matching tag and a blank selection (`Apps/Lillist-iOS/Sources/Settings/TrashSection.swift:16-22`).
