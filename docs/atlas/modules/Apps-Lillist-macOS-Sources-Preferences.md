---
module: Apps/Lillist-macOS/Sources/Preferences
summary: "macOS Settings window: ten tabbed panes wiring user preferences back to LillistCore's store layer."
read_when: "Touching macOS Preferences panes"
sources:
  - path: Apps/Lillist-macOS/Sources/Preferences/AdvancedPane.swift
    blob: c80427aeb751264a50474d48ec49951470f14a62
  - path: Apps/Lillist-macOS/Sources/Preferences/BackupPane.swift
    blob: 468fff3906d91a155daa2e7ba7bae1b0a7dba87b
  - path: Apps/Lillist-macOS/Sources/Preferences/CrashReportingPane.swift
    blob: 62d0e20e27ca7212a417fc3aa596c3d348d5bf0d
  - path: Apps/Lillist-macOS/Sources/Preferences/DiagnosticsPane.swift
    blob: 77810f50a18c3a1191651014a86138727a72c3ca
  - path: Apps/Lillist-macOS/Sources/Preferences/GeneralPane.swift
    blob: b9d931ffa5f633ab2a7ba7748f5f6e2badbc0a82
  - path: Apps/Lillist-macOS/Sources/Preferences/ICloudSyncPane.swift
    blob: b201bcbdf74497b6d4053a3f31f9084049c9b122
  - path: Apps/Lillist-macOS/Sources/Preferences/NotificationsPane.swift
    blob: 1a0dae89d0c41480471cd077769249173b61f621
  - path: Apps/Lillist-macOS/Sources/Preferences/PreferencesWindow.swift
    blob: f825832e950dbfe9caee0f3679d7d320b797c55a
  - path: Apps/Lillist-macOS/Sources/Preferences/QuickCapturePane.swift
    blob: 17ce4db03aa689ea8b3ad4e59f313693b2342451
  - path: Apps/Lillist-macOS/Sources/Preferences/RemindersPane.swift
    blob: b8907b2a8dadea8406239c6b0c15b9e2f0b972f2
  - path: Apps/Lillist-macOS/Sources/Preferences/TrashPane.swift
    blob: 11ac9a27d3d735c3cf5075b01b7dc2957a3985f2
references_modules: [Apps-Lillist-macOS-Sources-Hotkey, Packages-LillistCore-Sources-LillistCore-Backup, Packages-LillistCore-Sources-LillistCore-Diagnostics, Packages-LillistCore-Sources-LillistCore-Export, Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistCore-Sources-LillistCore-Notifications, Packages-LillistCore-Sources-LillistCore-Persistence, Packages-LillistCore-Sources-LillistCore-Reminders, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistCore-Sources-LillistCore-Sync-chunk-1, Packages-LillistCore-Sources-LillistCore-misc, Packages-LillistUI-Sources-LillistUI-Accessibility, Packages-LillistUI-Sources-LillistUI-Settings, Packages-LillistUI-Sources-LillistUI-Sync, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1, Packages-LillistUI-Sources-LillistUI-iOS-misc]
generator: cartographer/4
baseline: 99321d774840d17affd02fe2ac63b01b3d8cbec3
---

# Module: Apps/Lillist-macOS/Sources/Preferences

## Purpose

The Preferences module is the macOS `Settings` scene: ten tabbed panes assembled in `PreferencesWindow` covering every user-facing configuration surface the app exposes. The unifying idea is a clean store-access boundary — each pane reads `AppEnvironment` and either subscribes to the `PreferencesStore.Prefs` stream for CloudKit-synced values or queries `DevicePreferencesStore` directly for device-local values, with no direct Core Data dependency. Remove this module and the macOS app has no preferences surface; there is no other path for users to change notification schedules, sync mode, crash-reporting consent, hotkeys, or backup state.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AdvancedPane` | struct | `Apps/Lillist-macOS/Sources/Preferences/AdvancedPane.swift:14` | Renders export-to-directory, import-from-bundle, and reveal-store-in-Finder actions in a macOS Form. Requires `AppEnvironment` in the SwiftUI environment hierarchy. |
| `BackupPane` | struct | `Apps/Lillist-macOS/Sources/Preferences/BackupPane.swift:11` | Renders backup snapshot list, create-backup, save-copy, and restore (with schema preflight + destructive confirmation) in a macOS Form. Requires `AppEnvironment`. |
| `CrashReportingPane` | struct | `Apps/Lillist-macOS/Sources/Preferences/CrashReportingPane.swift:11` | Renders crash-prompt consent toggle and redacted sample preview; also mirrors `crashPromptsEnabled` live onto `AppEnvironment` so the current session picks it up immediately. |
| `DiagnosticsPane` | struct | `Apps/Lillist-macOS/Sources/Preferences/DiagnosticsPane.swift:11` | Renders device-local diagnostic-logging toggle (DevicePreferencesStore-backed) and a "Prepare diagnostic package" button that builds and exports a zip via `.fileExporter`. |
| `GeneralPane` | struct | `Apps/Lillist-macOS/Sources/Preferences/GeneralPane.swift:11` | Renders default task-list sort picker and default tag-tint color picker; writes the full `PreferencesStore.Prefs` snapshot back on every change. |
| `ICloudSyncPane` | struct | `Apps/Lillist-macOS/Sources/Preferences/ICloudSyncPane.swift:9` | Renders the iCloud sync toggle, sync status, and all migration sheets (choice, confirmation, progress, pause-explainer, disable); drives the full enable/disable migration flow via `MigrationCoordinator`. |
| `NotificationsPane` | struct | `Apps/Lillist-macOS/Sources/Preferences/NotificationsPane.swift:18` | Renders all-day reminder time, morning summary toggle and time, and notification permission status; applies scheduler side effects immediately without requiring relaunch. |
| `PreferencesMetrics` | enum | `Apps/Lillist-macOS/Sources/Preferences/PreferencesWindow.swift:50` | Single constant `contentWidth: CGFloat = 520` — every pane pins to this width so the Settings window and tab bar do not reflow when switching panes. |
| `PreferencesWindow` | struct | `Apps/Lillist-macOS/Sources/Preferences/PreferencesWindow.swift:11` | Root `TabView` for the macOS `Settings { }` scene; composes all ten preference panes as labeled tabs with system images and applies `.toggleStyle(.rainbow)` globally. |
| `QuickCapturePane` | struct | `Apps/Lillist-macOS/Sources/Preferences/QuickCapturePane.swift:13` | Renders quick-capture enable toggle, status-bar-icon toggle, and `HotkeyRecorder`; applies hotkey changes immediately via `GlobalHotkeyMonitor.reregister` after the prefs write. |
| `RemindersPane` | struct | `Apps/Lillist-macOS/Sources/Preferences/RemindersPane.swift:14` | Renders the Reminders-import toggle, list picker, drain button, and authorization flow; reads/writes `DevicePreferencesStore` (device-local, not synced via CloudKit). |
| `TrashPane` | struct | `Apps/Lillist-macOS/Sources/Preferences/TrashPane.swift:9` | Renders a trash-retention slider (7–365 days) and destructive "Empty Trash now" button backed by `TaskStore.purgeAll`; posts an accessibility announcement on completion. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `backupNow` | func | `Apps/Lillist-macOS/Sources/Preferences/BackupPane.swift:100` | Runs BackupSnapshotManager.createSnapshot in a detached Task (non-blocking), then reloads the snapshot list. The sole create-backup path in this pane. (BackupPane.swift:100-115) |
| `drainNow` | func | `Apps/Lillist-macOS/Sources/Preferences/RemindersPane.swift:128` | Triggers RemindersImporter.drainIfNeeded and surfaces a localized task count result string; the only on-demand import path in this pane. (RemindersPane.swift:128-133) |
| `emptyTrash` | func | `Apps/Lillist-macOS/Sources/Preferences/TrashPane.swift:94` | Calls TaskStore.purgeAll, formats a localized result string, and posts an accessibility announcement; the sole empty-trash path including the a11y feedback contract. (TrashPane.swift:94-109) |
| `handleToggle` | func | `Apps/Lillist-macOS/Sources/Preferences/ICloudSyncPane.swift:123` | Routes the sync toggle: enable shows the choice sheet, disable shows the disable-confirmation sheet. Gate for the full migration flow; wrong routing here breaks the migration UX. (ICloudSyncPane.swift:117-123) |
| `hmBinding` | func | `Apps/Lillist-macOS/Sources/Preferences/NotificationsPane.swift:99` | Maps Int16 defaultAllDayHour/Minute prefs fields bidirectionally to a Date for the all-day DatePicker; the sole bridging path between raw prefs and the DatePicker. (NotificationsPane.swift:99-108) |
| `isAvailable` | func | `Apps/Lillist-macOS/Sources/Preferences/ICloudSyncPane.swift:133` | Maps iCloudAccountState enum to a Bool used to gate the toggle and show a footer; called from three sites in viewState computation. (ICloudSyncPane.swift:131-134) |
| `loadIfNeeded` | func | `Apps/Lillist-macOS/Sources/Preferences/RemindersPane.swift:95` | One-shot init with didLoad guard: reads enabled flag, selected list ID, and authorization from DevicePreferencesStore, then conditionally loads Reminders lists. (RemindersPane.swift:95-104) |
| `loadSnapshots` | func | `Apps/Lillist-macOS/Sources/Preferences/BackupPane.swift:96` | Populates the snapshot list from BackupSnapshotManager; called on .task and after backupNow. Without it, the pane always shows empty even when backups exist. (BackupPane.swift:96-98) |
| `morningBinding` | func | `Apps/Lillist-macOS/Sources/Preferences/NotificationsPane.swift:110` | Maps Int16 morningSummaryHour/Minute prefs fields bidirectionally to a Date for the morning DatePicker. (NotificationsPane.swift:110-118) |
| `prepare` | func | `Apps/Lillist-macOS/Sources/Preferences/DiagnosticsPane.swift:98` | Sole execution path for building and exporting the diagnostic package. Orchestrates DiagnosticPackageBuilder with user-selected options (includeLogs/includeStore), manages isPreparing gate, populates exportDocument to trigger the fileExporter, and surfaces any build error. Without it the 'Prepare diagnostic package' button is a dead end (DiagnosticsPane.swift:98-122). |
| `prepareRestore` | func | `Apps/Lillist-macOS/Sources/Preferences/BackupPane.swift:134` | Schema preflight guard before showing the destructive restore confirmation; prevents incompatible backups from reaching runRestore. (BackupPane.swift:134-150) |
| `refreshCounts` | func | `Apps/Lillist-macOS/Sources/Preferences/ICloudSyncPane.swift:111` | Sole supplier of taskCounts, which feeds localTaskCount and mirroredTaskCount into viewState for ICloudSyncSettingsSection. Called on initial .task and on every syncMonitor.indicator change to keep counts current after a sync settles. Without it both count fields always show nil (ICloudSyncPane.swift:111-113, 29-33). |
| `refreshLists` | func | `Apps/Lillist-macOS/Sources/Preferences/RemindersPane.swift:124` | Fetches current Reminders lists from the gateway and updates the Picker; called after authorization is granted and after setEnabled. (RemindersPane.swift:124-126) |
| `requestAccess` | func | `Apps/Lillist-macOS/Sources/Preferences/RemindersPane.swift:116` | Requests Reminders authorization, re-reads the result, and conditionally refreshes lists; fan-in 3 reflects it is called from the toggle flow, explicit button, and setEnabled. (RemindersPane.swift:116-122) |
| `runExport` | func | `Apps/Lillist-macOS/Sources/Preferences/AdvancedPane.swift:69` | Orchestrates the full export flow: NSOpenPanel → timestamped directory creation → Exporter lifecycle → Finder reveal on success. Without it, the Advanced pane's export button is inert. (AdvancedPane.swift:69-103) |
| `runImport` | func | `Apps/Lillist-macOS/Sources/Preferences/AdvancedPane.swift:105` | Orchestrates the import flow: NSOpenPanel → Importer lifecycle → importSummary display. The only path from UI to Importer.importBundle. (AdvancedPane.swift:105-122) |
| `runMigration` | func | `Apps/Lillist-macOS/Sources/Preferences/ICloudSyncPane.swift:179` | Shared @MainActor migration helper: subscribes progressStream to activePhase before calling the kickoff closure, ensuring no phase is lost. Shared by both enable and disable paths. (ICloudSyncPane.swift:176-194) |
| `runRestore` | func | `Apps/Lillist-macOS/Sources/Preferences/BackupPane.swift:152` | Executes the restore via backupRestoreService.restore and prompts for relaunch; the terminal action of the backup restore flow. (BackupPane.swift:152-165) |
| `setEnabled` | func | `Apps/Lillist-macOS/Sources/Preferences/RemindersPane.swift:106` | Sole convergence point for the enable toggle: writes the flag to `devicePreferences`, then branches — triggering `requestAccess()` when permission is undetermined or `refreshLists()` when authorized. All side effects of enabling Reminders import funnel through this one function (Apps/Lillist-macOS/Sources/Preferences/RemindersPane.swift:106), invoked from `enabledBinding` (line 77). |
| `snapshotRow` | func | `Apps/Lillist-macOS/Sources/Preferences/BackupPane.swift:75` | ViewBuilder for each snapshot row showing date, size, Save-a-copy, and Restore buttons; the only rendering path for individual snapshots in the list. (BackupPane.swift:75-92) |
| `subscribe` | func | `Apps/Lillist-macOS/Sources/Preferences/CrashReportingPane.swift:66` | The sole lifecycle hook that seeds the form's state from `PreferencesStore.read()` and then drives it from the live `prefsStream` async sequence. Without it the pane renders only `ProgressView()` indefinitely and never reflects external prefs changes. Called once via `.task` (Apps/Lillist-macOS/Sources/Preferences/CrashReportingPane.swift:54). |
| `subscribe` | func | `Apps/Lillist-macOS/Sources/Preferences/GeneralPane.swift:48` | Prefs-stream entry point for GeneralPane; provides initial load and live CloudKit/cross-process update propagation with echo suppression. (GeneralPane.swift:48-62) |
| `subscribe` | func | `Apps/Lillist-macOS/Sources/Preferences/NotificationsPane.swift:69` | Prefs-stream entry point for NotificationsPane; also reads notificationPermissions.currentStatus() on initial load for the permission section. (NotificationsPane.swift:69-79) |
| `subscribe` | func | `Apps/Lillist-macOS/Sources/Preferences/QuickCapturePane.swift:60` | Prefs-stream entry point for QuickCapturePane; hydrates prefs and keeps the hotkey binding current across CloudKit updates. (QuickCapturePane.swift:60-70) |
| `subscribe` | func | `Apps/Lillist-macOS/Sources/Preferences/TrashPane.swift:78` | Prefs-stream entry point for TrashPane; hydrates trashRetentionDays and keeps the slider current across external changes. (TrashPane.swift:78-93) |
| `triggerDisable` | func | `Apps/Lillist-macOS/Sources/Preferences/ICloudSyncPane.swift:167` | Converts DisableStrategy into a runMigration kickoff call to coordinator.beginDisable; bridges UI selection to the MigrationCoordinator API. (ICloudSyncPane.swift:169-173) |
| `triggerEnable` | func | `Apps/Lillist-macOS/Sources/Preferences/ICloudSyncPane.swift:160` | Converts UI Direction to EnableDirection and wraps coordinator.beginEnable as a runMigration kickoff; the only enable-path entry into MigrationCoordinator. (ICloudSyncPane.swift:162-167) |

## Relationships

- `Apps-Lillist-macOS-Sources-Preferences.AdvancedPane -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Apps-Lillist-macOS-Sources-Preferences.BackupPane -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Apps-Lillist-macOS-Sources-Preferences.CrashReportingPane -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Apps-Lillist-macOS-Sources-Preferences.DiagnosticsPane -> Packages-LillistCore-Sources-LillistCore-misc.diagnosticLoggingEnabled (reads)`
- `Apps-Lillist-macOS-Sources-Preferences.DiagnosticsPane -> Packages-LillistCore-Sources-LillistCore-misc.setDiagnosticLoggingEnabled (writes)`
- `Apps-Lillist-macOS-Sources-Preferences.DiagnosticsPane -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (calls)`
- `Apps-Lillist-macOS-Sources-Preferences.DiagnosticsPane -> Packages-LillistUI-Sources-LillistUI-iOS-misc.DiagnosticsIncludeSheet (calls)`
- `Apps-Lillist-macOS-Sources-Preferences.GeneralPane -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Apps-Lillist-macOS-Sources-Preferences.ICloudSyncPane -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Apps-Lillist-macOS-Sources-Preferences.ICloudSyncPane -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (calls)`
- `Apps-Lillist-macOS-Sources-Preferences.ICloudSyncPane -> Packages-LillistUI-Sources-LillistUI-Settings.ICloudSyncSettingsSection (owns)`
- `Apps-Lillist-macOS-Sources-Preferences.ICloudSyncPane -> Packages-LillistUI-Sources-LillistUI-Sync.PauseExplainerDialog (owns)`
- `Apps-Lillist-macOS-Sources-Preferences.ICloudSyncPane -> Packages-LillistUI-Sources-LillistUI-Sync.SyncDisableConfirmationSheet (owns)`
- `Apps-Lillist-macOS-Sources-Preferences.ICloudSyncPane -> Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationChoiceSheet (owns)`
- `Apps-Lillist-macOS-Sources-Preferences.ICloudSyncPane -> Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationProgressSheet (owns)`
- `Apps-Lillist-macOS-Sources-Preferences.NotificationsPane -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Apps-Lillist-macOS-Sources-Preferences.QuickCapturePane -> Apps-Lillist-macOS-Sources-Hotkey.HotkeyRecorder (calls)`
- `Apps-Lillist-macOS-Sources-Preferences.QuickCapturePane -> Apps-Lillist-macOS-Sources-Hotkey.reregister (writes)`
- `Apps-Lillist-macOS-Sources-Preferences.QuickCapturePane -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Apps-Lillist-macOS-Sources-Preferences.RemindersPane -> Packages-LillistCore-Sources-LillistCore-misc.setRemindersImportListID (writes)`
- `Apps-Lillist-macOS-Sources-Preferences.RemindersPane -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Apps-Lillist-macOS-Sources-Preferences.TrashPane -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Apps-Lillist-macOS-Sources-Preferences.applySchedulerSideEffects -> Packages-LillistCore-Sources-LillistCore-Notifications.installMorningSummary (writes)`
- `Apps-Lillist-macOS-Sources-Preferences.applySchedulerSideEffects -> Packages-LillistCore-Sources-LillistCore-Notifications.uninstallMorningSummary (writes)`
- `Apps-Lillist-macOS-Sources-Preferences.applySchedulerSideEffects -> Packages-LillistCore-Sources-LillistCore-Notifications.updateDefaultAllDayTime (writes)`
- `Apps-Lillist-macOS-Sources-Preferences.backupNow -> Packages-LillistCore-Sources-LillistCore-Backup.createSnapshot (writes)`
- `Apps-Lillist-macOS-Sources-Preferences.backupNow -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Apps-Lillist-macOS-Sources-Preferences.drainNow -> Packages-LillistCore-Sources-LillistCore-Reminders.drainIfNeeded (writes)`
- `Apps-Lillist-macOS-Sources-Preferences.emptyTrash -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Apps-Lillist-macOS-Sources-Preferences.emptyTrash -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.purgeAll (writes)`
- `Apps-Lillist-macOS-Sources-Preferences.emptyTrash -> Packages-LillistUI-Sources-LillistUI-Accessibility.post (emits)`
- `Apps-Lillist-macOS-Sources-Preferences.handleToggle -> Packages-LillistUI-Sources-LillistUI-Sync.afterToggle (calls)`
- `Apps-Lillist-macOS-Sources-Preferences.isAvailable -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Apps-Lillist-macOS-Sources-Preferences.loadIfNeeded -> Packages-LillistCore-Sources-LillistCore-misc.remindersImportEnabled (reads)`
- `Apps-Lillist-macOS-Sources-Preferences.loadIfNeeded -> Packages-LillistCore-Sources-LillistCore-misc.remindersImportListID (reads)`
- `Apps-Lillist-macOS-Sources-Preferences.loadSnapshots -> Packages-LillistCore-Sources-LillistCore-Backup.listSnapshots (reads)`
- `Apps-Lillist-macOS-Sources-Preferences.openRemindersPrivacy -> Apps-Lillist-macOS-Sources-Hotkey.open (calls)`
- `Apps-Lillist-macOS-Sources-Preferences.openSystemSettings -> Apps-Lillist-macOS-Sources-Hotkey.open (calls)`
- `Apps-Lillist-macOS-Sources-Preferences.prepare -> Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticPackageBuilder (owns)`
- `Apps-Lillist-macOS-Sources-Preferences.prepare -> Packages-LillistCore-Sources-LillistCore-Diagnostics.Metadata (owns)`
- `Apps-Lillist-macOS-Sources-Preferences.prepare -> Packages-LillistCore-Sources-LillistCore-Diagnostics.diagnosticsDirectory (reads)`
- `Apps-Lillist-macOS-Sources-Preferences.prepare -> Packages-LillistUI-Sources-LillistUI-iOS-misc.DiagnosticZipDocument (owns)`
- `Apps-Lillist-macOS-Sources-Preferences.prepareRestore -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Apps-Lillist-macOS-Sources-Preferences.refreshCounts -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.syncCounts (reads)`
- `Apps-Lillist-macOS-Sources-Preferences.revealStoreInFinder -> Packages-LillistCore-Sources-LillistCore-Persistence.onDisk (reads)`
- `Apps-Lillist-macOS-Sources-Preferences.runExport -> Packages-LillistCore-Sources-LillistCore-Export.Exporter (owns)`
- `Apps-Lillist-macOS-Sources-Preferences.runExport -> Packages-LillistCore-Sources-LillistCore-Export.export (writes)`
- `Apps-Lillist-macOS-Sources-Preferences.runImport -> Packages-LillistCore-Sources-LillistCore-Export.Importer (owns)`
- `Apps-Lillist-macOS-Sources-Preferences.runImport -> Packages-LillistCore-Sources-LillistCore-Export.importBundle (writes)`
- `Apps-Lillist-macOS-Sources-Preferences.runRestore -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Apps-Lillist-macOS-Sources-Preferences.saveCopy -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Apps-Lillist-macOS-Sources-Preferences.setEnabled -> Packages-LillistCore-Sources-LillistCore-misc.setRemindersImportEnabled (writes)`
- `Apps-Lillist-macOS-Sources-Preferences.subscribe -> Packages-LillistCore-Sources-LillistCore-Notifications.currentStatus (reads)`
- `Apps-Lillist-macOS-Sources-Preferences.subscribe -> Packages-LillistUI-Sources-LillistUI-Settings.preview (calls)`
- `Apps-Lillist-macOS-Sources-Preferences.subscribe -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.Color (calls)`
- `Apps-Lillist-macOS-Sources-Preferences.subscribe -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.toHex (calls)`
- `Apps-Lillist-macOS-Sources-Preferences.triggerDisable -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.beginDisable (writes)`
- `Apps-Lillist-macOS-Sources-Preferences.triggerEnable -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.beginEnable (calls)`

## Type notes

All ten panes are plain SwiftUI `View` structs with no retained identity between window opens; all `@State` resets when SwiftUI tears the view down. Seven panes (General, Notifications, Trash, CrashReporting, QuickCapture, Backup, iCloudSync) bind to synced prefs via a shared pattern: `.task` loads the initial value and loops on `preferencesStore.prefsStream`, while `.onChange` writes the full `PreferencesStore.Prefs` snapshot back via `preferencesStore.update` (`Apps/Lillist-macOS/Sources/Preferences/GeneralPane.swift:38-44`). `DiagnosticsPane` and `RemindersPane` own their state directly against `DevicePreferencesStore`; `DiagnosticsPane` uses a `didHydrate` flag to prevent a delayed `.task` read from overwriting a user edit already in flight (`Apps/Lillist-macOS/Sources/Preferences/DiagnosticsPane.swift:88`). No pane declares explicit actor isolation; async store calls are dispatched via `Task {}` blocks under SwiftUI's implicit `@MainActor`. `ICloudSyncPane` holds `@State private var route: SyncSheetRoute?` as the exclusive routing token for four sync sheets; the single-slot invariant prevents simultaneous sheet presentation and cascade-close (`Apps/Lillist-macOS/Sources/Preferences/ICloudSyncPane.swift:14`, `Apps/Lillist-macOS/Sources/Preferences/ICloudSyncPane.swift:43`). `NotificationsPane` carries a side-effect obligation: pref changes must also propagate to `notificationScheduler` synchronously so the in-process scheduler reflects the new cadence before its next fire (`Apps/Lillist-macOS/Sources/Preferences/NotificationsPane.swift:125-155`). `QuickCapturePane` carries an analogous obligation: after writing the new hotkey string to the store it calls `monitor.reregister(combo:)` to hot-reload the global hotkey without a relaunch (`Apps/Lillist-macOS/Sources/Preferences/QuickCapturePane.swift:50`). `PreferencesMetrics.contentWidth = 520` is the sole shared layout constant; every pane calls `.frame(width:).fixedSize()` so only the window height animates on tab switch (`Apps/Lillist-macOS/Sources/Preferences/PreferencesWindow.swift:51`).

## External deps

- AppKit — imported
- LillistCore — imported
- LillistUI — imported
- SwiftUI — imported
- UniformTypeIdentifiers — imported

## Gotchas

In `DiagnosticsPane`, `.fileExporter` is attached to the `Button` node and `.sheet` to the `Form` — deliberately separate nodes — because co-locating both on the same node caused the include sheet's dismissal to cascade up and close the Preferences window (`Apps/Lillist-macOS/Sources/Preferences/DiagnosticsPane.swift:42-46`). `ICloudSyncPane` replaced four stacked `.sheet` modifiers with a single `SyncSheetRoute`-routed `.sheet(item: $route)` for the same reason: the dismiss-one-present-another sequence previously dismissed the entire Settings window (`Apps/Lillist-macOS/Sources/Preferences/ICloudSyncPane.swift:12-13`).
