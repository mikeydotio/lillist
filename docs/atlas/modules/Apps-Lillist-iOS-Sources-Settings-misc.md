---
module: "Apps/Lillist-iOS/Sources/Settings (misc)"
summary: "iOS Settings section controllers: AppEnvironment-coupled wrappers wiring store state into LillistUI Settings presenters."
read_when: "Touching iOS Settings screens or env wiring"
sources:
  - path: Apps/Lillist-iOS/Sources/Settings/AdvancedSection.swift
    blob: 16cfb82d01a4ffc73a1cef2fd36960e58c4d2829
  - path: Apps/Lillist-iOS/Sources/Settings/BackupSection.swift
    blob: 9de8c3e16a4da35983fd6914496d67258e9c1ce1
  - path: Apps/Lillist-iOS/Sources/Settings/CrashReportingSection.swift
    blob: 0a6c119b7f6e45aa2db51acd27b2176627b1b308
  - path: Apps/Lillist-iOS/Sources/Settings/DiagnosticsSection.swift
    blob: b8a919d014172b63b83d988066bcb0ce43cbbd63
  - path: Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift
    blob: 51dd2c4bfbdf31e1d77289a65f3bb08c4e7e6cb9
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
baseline: 8e926f08fd5269de164d25b42880893a604a9d5c
---

# Module: Apps/Lillist-iOS/Sources/Settings (misc)

## Purpose

This module is the iOS-side, AppEnvironment-coupled controller layer for every Settings section — the container half of the container/presenter split used throughout Lillist. Each file wires live store state and async actions into state-free LillistUI presenters, and SettingsTab owns the root navigation that drives all per-domain drill-down pages. Without this module the pure LillistUI Settings presenters would be unreachable and all env-coupled preferences, migration, diagnostics, backup, and Reminders-import logic would have no iOS host.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AdvancedSection` | struct | `Apps/Lillist-iOS/Sources/Settings/AdvancedSection.swift:6` | Renders an Advanced section with export-to-tmp-dir and import-from-picker actions; requires `AppEnvironment` in the SwiftUI environment; async state is self-contained. |
| `BackupSection` | struct | `Apps/Lillist-iOS/Sources/Settings/BackupSection.swift:9` | Lists timestamped snapshots, creates on demand, shares, and restores; requires `AppEnvironment` with `backupSnapshotManager` and `backupRestoreService`; restore is gated on schema compatibility preflight and a destructive confirmation. |
| `CrashReportingSection` | struct | `Apps/Lillist-iOS/Sources/Settings/CrashReportingSection.swift:5` | Renders crash-reporting toggle and collapsible sample report; requires `Binding<PreferencesStore.Prefs>` and `AppEnvironment`; writes `crashPromptsEnabled` to both the prefs binding and the live env on change. |
| `DiagnosticsSection` | struct | `Apps/Lillist-iOS/Sources/Settings/DiagnosticsSection.swift:11` | Renders diagnostic-logging toggle and package-export flow; requires `AppEnvironment`; hydrates `enabled` once via `.task` with a `didHydrate` guard to prevent races with user taps. |
| `ICloudSyncSection` | struct | `Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:10` | Owns all iCloud sync migration sheet state (choice, confirmation, progress, disable, pause explainer); requires `AppEnvironment`; drives `MigrationCoordinator` for enable/disable and streams `progressStream` into the progress sheet. |
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
| `handleToggle` | func | `Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:111` | Single decision point routing the sync toggle: on→`showChoiceSheet`, off→`showDisableSheet`; without it, the toggle has no coordinator path (`Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:118-124`). |
| `isAvailable` | func | `Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:121` | Maps `iCloudAccountState` to a Bool; called three times in `viewState` to derive `iCloudAvailable`, `isToggleDisabled`, and the disabled footer text (`Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:132-135`). |
| `loadIfNeeded` | func | `Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift:88` | Single-pass initializer for the section: reads enabled flag, list ID, and authorization from device prefs, then conditionally loads lists; `didLoad` guard prevents redundant async fetches on re-renders (`Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift:88-97`). |
| `loadSnapshots` | func | `Apps/Lillist-iOS/Sources/Settings/BackupSection.swift:100` | Populates `snapshots` on `.task`; drives the entire backup list render; silently swallows errors so a missing snapshot dir shows an empty list rather than a crash (`Apps/Lillist-iOS/Sources/Settings/BackupSection.swift:100-102`). |
| `prepare` | func | `Apps/Lillist-iOS/Sources/Settings/DiagnosticsSection.swift:95` | Assembles `DiagnosticPackageBuilder.Metadata`, builds the zip, wraps it in `DiagnosticZipDocument`, removes the tmp file, and triggers `fileExporter`; called only after the include sheet fully dismisses to avoid conflicting presentations (`Apps/Lillist-iOS/Sources/Settings/DiagnosticsSection.swift:91-115`). |
| `prepareRestore` | func | `Apps/Lillist-iOS/Sources/Settings/BackupSection.swift:119` | Runs schema-compatibility preflight before presenting the destructive confirmation; gates restore behind `pre.isCompatible`, preventing cross-version data corruption (`Apps/Lillist-iOS/Sources/Settings/BackupSection.swift:119-134`). |
| `refreshLists` | func | `Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift:117` | Fetches the current Reminders lists and populates the picker; called from `loadIfNeeded`, `setEnabled`, and `requestAccess` — the shared refresh step across all authorization-change paths (`Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift:117-119`). |
| `requestAccess` | func | `Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift:109` | The sole Reminders permission-request path: requests access, re-checks authorization, and conditionally refreshes lists; fan-in of 3 (`setEnabled`, body button, `loadIfNeeded` chain) (`Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift:109-115`). |
| `runExport` | func | `Apps/Lillist-iOS/Sources/Settings/AdvancedSection.swift:67` | The only export path from Settings: creates the tmp directory, instantiates `Exporter` with persistence and preferences, calls `export(to:)`, and surfaces the resulting URL for `ShareLink` (`Apps/Lillist-iOS/Sources/Settings/AdvancedSection.swift:67-84`). |
| `runImport` | func | `Apps/Lillist-iOS/Sources/Settings/AdvancedSection.swift:86` | Bridges the iOS security-scoped file picker to `Importer.importBundle`; correctly calls `startAccessingSecurityScopedResource` / `stopAccessingSecurityScopedResource` so the sandbox access stays open for the import (`Apps/Lillist-iOS/Sources/Settings/AdvancedSection.swift:86-99`). |
| `runMigration` | func | `Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:174` | Central migration driver: streams `coordinator.progressStream` into `activePhase` on `@MainActor` so the progress sheet reflects live state, falls back to a tmp storeURL for test fixtures, and maps thrown errors to `.failed(reason:)`; all enable and disable paths funnel through it (`Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:189-205`). |
| `runRestore` | func | `Apps/Lillist-iOS/Sources/Settings/BackupSection.swift:136` | Executes the iCloud-propagating restore via `backupRestoreService.restore`; the point of no return — all data on every device on the account is replaced; announces completion for accessibility (`Apps/Lillist-iOS/Sources/Settings/BackupSection.swift:136-147`). |
| `setEnabled` | func | `Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift:99` | The single action invoked by `enabledBinding`'s setter (Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift:70) when the toggle changes. It chains three responsibilities: persists the new state to `DevicePreferencesStore`, triggers `requestAccess()` when permission is still undetermined, and calls `refreshLists()` when already authorized — making it the pivot between a UI toggle flip and the downstream permission + list-load side effects. |
| `triggerDisable` | func | `Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:162` | Converts `DisableStrategy` to the `coordinator.beginDisable` closure and schedules via `runMigration`; the sole entry point for all sync-disable flows from the Settings UI (`Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:177-181`). |
| `triggerEnable` | func | `Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:155` | Converts `SyncMigrationConfirmationDialog.Direction` to `EnableDirection` and schedules via `runMigration`; the sole entry point for all sync-enable flows from the Settings UI (`Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:170-175`). |

## Relationships

- `Apps-Lillist-iOS-Sources-Settings-misc.AdvancedSection -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Apps-Lillist-iOS-Sources-Settings-misc.BackupSection -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Apps-Lillist-iOS-Sources-Settings-misc.CrashReportingSection -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Apps-Lillist-iOS-Sources-Settings-misc.CrashReportingSection -> Packages-LillistUI-Sources-LillistUI-Settings.preview (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.DiagnosticsSection -> Packages-LillistCore-Sources-LillistCore-misc.diagnosticLoggingEnabled (reads)`
- `Apps-Lillist-iOS-Sources-Settings-misc.DiagnosticsSection -> Packages-LillistCore-Sources-LillistCore-misc.setDiagnosticLoggingEnabled (writes)`
- `Apps-Lillist-iOS-Sources-Settings-misc.DiagnosticsSection -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.DiagnosticsSection -> Packages-LillistUI-Sources-LillistUI-iOS-misc.DiagnosticsIncludeSheet (owns)`
- `Apps-Lillist-iOS-Sources-Settings-misc.ICloudSyncSection -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.ICloudSyncSection -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.ICloudSyncSection -> Packages-LillistUI-Sources-LillistUI-Settings.ICloudSyncSettingsSection (owns)`
- `Apps-Lillist-iOS-Sources-Settings-misc.ICloudSyncSection -> Packages-LillistUI-Sources-LillistUI-Sync.PauseExplainerDialog (owns)`
- `Apps-Lillist-iOS-Sources-Settings-misc.ICloudSyncSection -> Packages-LillistUI-Sources-LillistUI-Sync.SyncDisableConfirmationSheet (owns)`
- `Apps-Lillist-iOS-Sources-Settings-misc.ICloudSyncSection -> Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationChoiceSheet (owns)`
- `Apps-Lillist-iOS-Sources-Settings-misc.ICloudSyncSection -> Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationProgressSheet (owns)`
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
- `Apps-Lillist-iOS-Sources-Settings-misc.handleToggle -> Packages-LillistUI-Sources-LillistUI-Sync.afterToggle (calls)`
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

## Type notes

SettingsTab (Apps/Lillist-iOS/Sources/Settings/SettingsTab.swift:15) is the root: it reads PreferencesStore.Prefs once via .task and writes changes back via .onChange, threading a Binding<Prefs> down to NotificationsSection, TrashSection, QuickCaptureSection, and CrashReportingSection. Sections that bypass the Prefs binding — ICloudSyncSection, RemindersImportSection, DiagnosticsSection — own local @State and drive device-local or migration-coupled stores directly; their data cannot travel through the synced Prefs row.

ICloudSyncSection (Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:10) is the sole iOS owner of migration sheet routing: it holds @State route: SyncSheetRoute? and drives MigrationCoordinator.progressStream on the MainActor inside runMigration, swapping the route to .progress(_) in-place so no dismiss/re-present conflict occurs.

BackupSection (Apps/Lillist-iOS/Sources/Settings/BackupSection.swift:111) dispatches createSnapshot via Task.detached to avoid blocking the main actor during zip creation, then rejoins on MainActor to refresh the snapshot list. All sections are View types isolated to the MainActor; none is a Swift actor itself.

## External deps

- LillistCore — imported
- LillistUI — imported
- SwiftUI — imported
- UIKit — imported
- UniformTypeIdentifiers — imported

## Gotchas

A. `DiagnosticsSection` hosts `.fileExporter` on the `Button` node, not the enclosing `Section` — a deliberate split because co-locating `.sheet` and `.fileExporter` on the same node clobbered the include sheet and dismissed the whole Settings pane (comment explains at `Apps/Lillist-iOS/Sources/Settings/DiagnosticsSection.swift:40`). B. `ICloudSyncSection` funnels exactly **four** sync modals through one `.sheet(item: $route)` (`Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:40`): the `SyncSheetRoute` cases `choice`, `disable`, `pauseExplainer`, and `progress`. `afterToggle` is a static factory method on the route type (called at line 112), not a fifth case. The migration confirmation is a **separate** `.confirmationDialog` driven by `pendingDirection` (`Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:25`), deliberately kept distinct because a `confirmationDialog` coexists safely with one sheet. C. `TrashSection.init` coerces any non-preset `trashRetentionDays` (e.g. a legacy slider value of 45) into the nearest value from `[7,14,30,60,90,180,365]` so `Picker` renders cleanly — a non-preset value from `PreferencesStore.Prefs` is silently overwritten on construction (`Apps/Lillist-iOS/Sources/Settings/TrashSection.swift:18`).
