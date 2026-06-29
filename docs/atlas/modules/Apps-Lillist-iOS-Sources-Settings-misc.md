---
module: "Apps/Lillist-iOS/Sources/Settings (misc)"
summary: "iOS Settings Form sections: env-coupled panes that own state, trigger store operations, and compose into Settings pages."
read_when: "Touching iOS Settings sections or wiring env stores into Settings UI."
sources:
  - path: Apps/Lillist-iOS/Sources/Settings/AdvancedSection.swift
    blob: 16cfb82d01a4ffc73a1cef2fd36960e58c4d2829
  - path: Apps/Lillist-iOS/Sources/Settings/BackupSection.swift
    blob: 9de8c3e16a4da35983fd6914496d67258e9c1ce1
  - path: Apps/Lillist-iOS/Sources/Settings/CrashReportingSection.swift
    blob: 0a6c119b7f6e45aa2db51acd27b2176627b1b308
  - path: Apps/Lillist-iOS/Sources/Settings/DiagnosticsSection.swift
    blob: 42c624e1b59eef85fb94ebfb6ee604f94ea12b74
  - path: Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift
    blob: 5e0f38d1fd6a97e8b819ce4594f8eba2dd9e340c
  - path: Apps/Lillist-iOS/Sources/Settings/NotificationsSection.swift
    blob: 254a5ffeb365bd10ddca648b74241275df310079
  - path: Apps/Lillist-iOS/Sources/Settings/QuickCaptureSection.swift
    blob: bf450601d8c0b95a98aee0f0ea499f2eeffeca61
  - path: Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift
    blob: d0376ca5e47433b56769bde02fb1fbe81a6e5e0a
  - path: Apps/Lillist-iOS/Sources/Settings/ResetDataStoreSection.swift
    blob: f528e428f6bb0f42dfe2ba9a3a051c49a4c5c864
  - path: Apps/Lillist-iOS/Sources/Settings/SettingsTab.swift
    blob: 62e7e6734a310a6b9dbf54eb20b3df3081356761
  - path: Apps/Lillist-iOS/Sources/Settings/TrashSection.swift
    blob: 047a2d56222b6c4b659d138012e3afa69d484205
references_modules: [Apps-Lillist-iOS-Sources-Settings-Pages, Apps-Lillist-macOS-Sources-Hotkey, Packages-LillistCore-Sources-LillistCore-Backup, Packages-LillistCore-Sources-LillistCore-Diagnostics, Packages-LillistCore-Sources-LillistCore-Export, Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistCore-Sources-LillistCore-Notifications, Packages-LillistCore-Sources-LillistCore-Reminders, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistCore-Sources-LillistCore-Sync-chunk-1, Packages-LillistCore-Sources-LillistCore-misc, Packages-LillistUI-Sources-LillistUI-Accessibility, Packages-LillistUI-Sources-LillistUI-Settings, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1, Packages-LillistUI-Sources-LillistUI-iOS-misc]
generator: cartographer/4
baseline: 99321d774840d17affd02fe2ac63b01b3d8cbec3
---

# Module: Apps/Lillist-iOS/Sources/Settings (misc)

## Purpose

This module implements the iOS Settings screen's env-coupled Form sections — the individual settings panes that require direct access to AppEnvironment stores (iCloud sync migration, notifications, trash, backups, diagnostics, Reminders import, export/import, crash reporting, and data reset). It is the boundary layer between LillistUI's state-free presentation components and the live LillistCore stores; sections here own @State, issue async store calls, and pipe results back into the UI. Without this module, the iOS app would have no way to surface or mutate persistent user preferences and trigger heavyweight operations like sync migration or data store reset.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AdvancedSection` | struct | `Apps/Lillist-iOS/Sources/Settings/AdvancedSection.swift:6` | Renders an Advanced section with export-to-tmp-dir and import-from-picker actions; requires `AppEnvironment` in the SwiftUI environment; async state is self-contained. |
| `BackupSection` | struct | `Apps/Lillist-iOS/Sources/Settings/BackupSection.swift:9` | Lists timestamped snapshots, creates on demand, shares, and restores; requires `AppEnvironment` with `backupSnapshotManager` and `backupRestoreService`; restore is gated on schema compatibility preflight and a destructive confirmation. |
| `CrashReportingSection` | struct | `Apps/Lillist-iOS/Sources/Settings/CrashReportingSection.swift:5` | Renders crash-reporting toggle and collapsible sample report; requires `Binding<PreferencesStore.Prefs>` and `AppEnvironment`; writes `crashPromptsEnabled` to both the prefs binding and the live env on change. |
| `DiagnosticsExportModel` | class | `Apps/Lillist-iOS/Sources/Settings/DiagnosticsSection.swift:31` | @MainActor @Observable model owning diagnostics export state; callers hydrate once with hydrate(_:), toggle via setLogging(_:_:), and drive export via requestExport()+sheetDismissed(_:). |
| `DiagnosticsSection` | struct | `Apps/Lillist-iOS/Sources/Settings/DiagnosticsSection.swift:127` | Renders diagnostic-logging toggle and package-export flow; requires `AppEnvironment`; hydrates `enabled` once via `.task` with a `didHydrate` guard to prevent races with user taps. |
| `DiagnosticsSheet` | enum | `Apps/Lillist-iOS/Sources/Settings/DiagnosticsSection.swift:11` | Identifiable enum with two cases (.include, .share(URL)) used as the item type for .sheet(item:) in DiagnosticsSection's host page; id is a stable String. |
| `ICloudSyncModalsModel` | class | `Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:17` | @MainActor @Observable model holding a single SyncSheetRoute? slot; callers set route via handleToggle/showPauseExplainer/triggerEnable/triggerDisable and read it to drive .sheet(item:) in the host page. |
| `ICloudSyncSection` | struct | `Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:87` | Owns all iCloud sync migration sheet state (choice, confirmation, progress, disable, pause explainer); requires `AppEnvironment`; drives `MigrationCoordinator` for enable/disable and streams `progressStream` into the progress sheet. |
| `NotificationsSection` | struct | `Apps/Lillist-iOS/Sources/Settings/NotificationsSection.swift:5` | Renders all-day time, morning-summary, and notification-permission sections; requires `Binding<PreferencesStore.Prefs>` and `AppEnvironment`; debounces scheduler writes 750ms after preference changes. |
| `QuickCaptureSection` | struct | `Apps/Lillist-iOS/Sources/Settings/QuickCaptureSection.swift:4` | Renders the floating-button toggle and a Shortcuts deeplink; requires only `Binding<PreferencesStore.Prefs>`; no async operations. |
| `RemindersImportSection` | struct | `Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift:13` | Controls Reminders import: enable/list selection/manual drain; requires `AppEnvironment`; reads and writes `DevicePreferencesStore` (device-local, not synced); requests Reminders permission on first enable. |
| `ResetDataStoreSection` | struct | `Apps/Lillist-iOS/Sources/Settings/ResetDataStoreSection.swift:15` | Offers irreversible full data-store reset behind a destructive confirmation; requires `AppEnvironment` with `dataStoreReset`; posts an accessibility announcement on success or failure. |
| `SettingsTab` | struct | `Apps/Lillist-iOS/Sources/Settings/SettingsTab.swift:15` | iOS Settings landing view; loads `PreferencesStore.Prefs` on appear, writes back on change, and renders icon-tile rows that navigate into focused sub-pages; requires `AppEnvironment`. |
| `ShareSheet` | struct | `Apps/Lillist-iOS/Sources/Settings/DiagnosticsSection.swift:109` | UIViewControllerRepresentable wrapping UIActivityViewController; callers supply activityItems and it presents the system share sheet via makeUIViewController. |
| `TrashSection` | struct | `Apps/Lillist-iOS/Sources/Settings/TrashSection.swift:5` | Renders trash-retention picker and empty-trash action; requires `Binding<PreferencesStore.Prefs>` and `AppEnvironment`; `init` coerces any legacy non-preset retention value to the nearest preset. |
| `confirmReplace` | func | `Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:25` | Commits the pending enable direction (stored in pendingDirection) by calling triggerEnable; clears pendingDirection regardless; no-op if pendingDirection is nil. |
| `handleToggle` | func | `Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:22` | Routes a toggle event to the .afterToggle(on:) sheet route; callers pass the new Bool from the toggle's onChange. |
| `hydrate` | func | `Apps/Lillist-iOS/Sources/Settings/DiagnosticsSection.swift:47` | One-shot async hydration from DevicePreferencesStore; safe to call multiple times — only the first call sets enabled; subsequent calls are no-ops if didHydrate is true. |
| `makeUIViewController` | func | `Apps/Lillist-iOS/Sources/Settings/DiagnosticsSection.swift:112` | UIViewControllerRepresentable protocol requirement; returns a UIActivityViewController initialized with the receiver's activityItems. |
| `openICloudSystemSettings` | func | `Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:77` | Opens the iOS system Settings app via UIApplication.openSettingsURLString; used for iCloud sign-in and pause-reason flows. |
| `requestExport` | func | `Apps/Lillist-iOS/Sources/Settings/DiagnosticsSection.swift:64` | Signals intent to build the diagnostic package: sets wantsExport=true and dismisses the current sheet; the actual build fires in sheetDismissed to avoid a double-sheet conflict. |
| `setLogging` | func | `Apps/Lillist-iOS/Sources/Settings/DiagnosticsSection.swift:52` | Write-through toggle: marks didHydrate=true so hydrate cannot overwrite, then persists to DevicePreferencesStore and updates the live DiagnosticLog immediately. |
| `sheetDismissed` | func | `Apps/Lillist-iOS/Sources/Settings/DiagnosticsSection.swift:66` | Must be called after each sheet dismissal; fires buildAndShare when wantsExport is pending, or cleans up the temp zip URL when the share sheet closes. |
| `showPauseExplainer` | func | `Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:23` | Routes to .pauseExplainer sheet; callers invoke when the user taps the paused sync indicator. |
| `triggerDisable` | func | `Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:37` | Kicks off a disable migration on MainActor via runMigration; strategy (keepLocal/eraseLocal) determines which coordinator path runs; route streams phase events until completion or failure. |
| `triggerEnable` | func | `Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:30` | Kicks off an enable migration on MainActor; direction (replaceICloud/replaceLocal) is forwarded to coordinator.beginEnable; route streams phase events until completion or failure. |
| `updateUIViewController` | func | `Apps/Lillist-iOS/Sources/Settings/DiagnosticsSection.swift:116` | UIViewControllerRepresentable protocol no-op; UIActivityViewController manages its own lifecycle and needs no SwiftUI-driven updates. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `backupNow` | func | `Apps/Lillist-iOS/Sources/Settings/BackupSection.swift:104` | Detaches `createSnapshot()` so the non-actor-isolated `BackupSnapshotManager` doesn't block MainActor, then reloads the list and announces the result; the `Task.detached` is the load-bearing detail (`Apps/Lillist-iOS/Sources/Settings/BackupSection.swift:104-117`). |
| `drainNow` | func | `Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift:121` | The only manual-drain path from Settings: calls `remindersImporter.drainIfNeeded()` and surfaces the imported count as a status message (`Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift:121-126`). |
| `emptyTrash` | func | `Apps/Lillist-iOS/Sources/Settings/TrashSection.swift:77` | The only path for manual trash emptying from Settings: calls `taskStore.purgeAll()` and announces the result via `AccessibilityAnnouncements`; destructive and iCloud-propagating (`Apps/Lillist-iOS/Sources/Settings/TrashSection.swift:77-92`). |
| `isAvailable` | func | `Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:145` | Maps `iCloudAccountState` to a Bool; called three times in `viewState` to derive `iCloudAvailable`, `isToggleDisabled`, and the disabled footer text (`Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:132-135`). |
| `loadIfNeeded` | func | `Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift:88` | Single-pass initializer for the section: reads enabled flag, list ID, and authorization from device prefs, then conditionally loads lists; `didLoad` guard prevents redundant async fetches on re-renders (`Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift:88-97`). |
| `loadSnapshots` | func | `Apps/Lillist-iOS/Sources/Settings/BackupSection.swift:100` | Populates `snapshots` on `.task`; drives the entire backup list render; silently swallows errors so a missing snapshot dir shows an empty list rather than a crash (`Apps/Lillist-iOS/Sources/Settings/BackupSection.swift:100-102`). |
| `prepareRestore` | func | `Apps/Lillist-iOS/Sources/Settings/BackupSection.swift:119` | Runs schema-compatibility preflight before presenting the destructive confirmation; gates restore behind `pre.isCompatible`, preventing cross-version data corruption (`Apps/Lillist-iOS/Sources/Settings/BackupSection.swift:119-134`). |
| `refreshCounts` | func | `Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:104` | Fetches TaskStore.syncCounts() and writes the result into taskCounts, which feeds localTaskCount/mirroredTaskCount into ICloudSyncSettingsSection.ViewState. Without it the sync section shows nil counts. Called on appear and on every sync indicator change so the mirrored figure tracks reality. |
| `refreshLists` | func | `Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift:117` | Fetches the current Reminders lists and populates the picker; called from `loadIfNeeded`, `setEnabled`, and `requestAccess` — the shared refresh step across all authorization-change paths (`Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift:117-119`). |
| `requestAccess` | func | `Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift:109` | The sole Reminders permission-request path: requests access, re-checks authorization, and conditionally refreshes lists; fan-in of 3 (`setEnabled`, body button, `loadIfNeeded` chain) (`Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift:109-115`). |
| `runExport` | func | `Apps/Lillist-iOS/Sources/Settings/AdvancedSection.swift:67` | The only export path from Settings: creates the tmp directory, instantiates `Exporter` with persistence and preferences, calls `export(to:)`, and surfaces the resulting URL for `ShareLink` (`Apps/Lillist-iOS/Sources/Settings/AdvancedSection.swift:67-84`). |
| `runImport` | func | `Apps/Lillist-iOS/Sources/Settings/AdvancedSection.swift:86` | Bridges the iOS security-scoped file picker to `Importer.importBundle`; correctly calls `startAccessingSecurityScopedResource` / `stopAccessingSecurityScopedResource` so the sandbox access stays open for the import (`Apps/Lillist-iOS/Sources/Settings/AdvancedSection.swift:86-99`). |
| `runMigration` | func | `Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:52` | Central migration executor used by both triggerEnable and triggerDisable (fan-in 5): streams MigrationCoordinator phase events into route, handles terminal phases (success→nil, failure→.progress(.failed)), and ensures the progress sheet renders live state throughout the operation. |
| `runRestore` | func | `Apps/Lillist-iOS/Sources/Settings/BackupSection.swift:136` | Executes the iCloud-propagating restore via `backupRestoreService.restore`; the point of no return — all data on every device on the account is replaced; announces completion for accessibility (`Apps/Lillist-iOS/Sources/Settings/BackupSection.swift:136-147`). |
| `setEnabled` | func | `Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift:99` | The single action invoked by `enabledBinding`'s setter (Apps/Lillist-iOS/Sources/Settings/RemindersImportSection.swift:70) when the toggle changes. It chains three responsibilities: persists the new state to `DevicePreferencesStore`, triggers `requestAccess()` when permission is still undetermined, and calls `refreshLists()` when already authorized — making it the pivot between a UI toggle flip and the downstream permission + list-load side effects. |

## Relationships

- `Apps-Lillist-iOS-Sources-Settings-misc.AdvancedSection -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Apps-Lillist-iOS-Sources-Settings-misc.BackupSection -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Apps-Lillist-iOS-Sources-Settings-misc.CrashReportingSection -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Apps-Lillist-iOS-Sources-Settings-misc.CrashReportingSection -> Packages-LillistUI-Sources-LillistUI-Settings.preview (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.DiagnosticsSection -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.ICloudSyncSection -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.ICloudSyncSection -> Packages-LillistUI-Sources-LillistUI-Settings.ICloudSyncSettingsSection (owns)`
- `Apps-Lillist-iOS-Sources-Settings-misc.MorningKey -> Apps-Lillist-macOS-Sources-Hotkey.open (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.MorningKey -> Packages-LillistCore-Sources-LillistCore-Notifications.currentStatus (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.NotificationsSection -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Apps-Lillist-iOS-Sources-Settings-misc.RemindersImportSection -> Packages-LillistCore-Sources-LillistCore-misc.setRemindersImportListID (writes)`
- `Apps-Lillist-iOS-Sources-Settings-misc.RemindersImportSection -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Apps-Lillist-iOS-Sources-Settings-misc.ResetDataStoreSection -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (calls)`
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
- `Apps-Lillist-iOS-Sources-Settings-misc.buildAndShare -> Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticPackageBuilder (owns)`
- `Apps-Lillist-iOS-Sources-Settings-misc.buildAndShare -> Packages-LillistCore-Sources-LillistCore-Diagnostics.Metadata (owns)`
- `Apps-Lillist-iOS-Sources-Settings-misc.buildAndShare -> Packages-LillistCore-Sources-LillistCore-Diagnostics.diagnosticsDirectory (reads)`
- `Apps-Lillist-iOS-Sources-Settings-misc.confirmMessage -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.drainNow -> Packages-LillistCore-Sources-LillistCore-Reminders.drainIfNeeded (writes)`
- `Apps-Lillist-iOS-Sources-Settings-misc.emptyTrash -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.emptyTrash -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.purgeAll (writes)`
- `Apps-Lillist-iOS-Sources-Settings-misc.emptyTrash -> Packages-LillistUI-Sources-LillistUI-Accessibility.post (emits)`
- `Apps-Lillist-iOS-Sources-Settings-misc.hydrate -> Packages-LillistCore-Sources-LillistCore-misc.diagnosticLoggingEnabled (reads)`
- `Apps-Lillist-iOS-Sources-Settings-misc.loadIfNeeded -> Packages-LillistCore-Sources-LillistCore-misc.remindersImportEnabled (reads)`
- `Apps-Lillist-iOS-Sources-Settings-misc.loadIfNeeded -> Packages-LillistCore-Sources-LillistCore-misc.remindersImportListID (reads)`
- `Apps-Lillist-iOS-Sources-Settings-misc.loadSnapshots -> Packages-LillistCore-Sources-LillistCore-Backup.listSnapshots (reads)`
- `Apps-Lillist-iOS-Sources-Settings-misc.navRow -> Packages-LillistUI-Sources-LillistUI-Settings.SettingsRowIcon (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.openICloudSystemSettings -> Apps-Lillist-macOS-Sources-Hotkey.open (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.prepareRestore -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.refreshCounts -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.refreshCounts -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.syncCounts (reads)`
- `Apps-Lillist-iOS-Sources-Settings-misc.resetButton -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.runExport -> Packages-LillistCore-Sources-LillistCore-Export.Exporter (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.runExport -> Packages-LillistCore-Sources-LillistCore-Export.export (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.runImport -> Packages-LillistCore-Sources-LillistCore-Export.Importer (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.runImport -> Packages-LillistCore-Sources-LillistCore-Export.importBundle (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.runReset -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.runReset -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.resetAndRedownload (writes)`
- `Apps-Lillist-iOS-Sources-Settings-misc.runReset -> Packages-LillistUI-Sources-LillistUI-Accessibility.post (emits)`
- `Apps-Lillist-iOS-Sources-Settings-misc.runRestore -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc.setEnabled -> Packages-LillistCore-Sources-LillistCore-misc.setRemindersImportEnabled (writes)`
- `Apps-Lillist-iOS-Sources-Settings-misc.setLogging -> Packages-LillistCore-Sources-LillistCore-misc.setDiagnosticLoggingEnabled (writes)`

## Type notes

Two heavyweight sections extract their modal state into separate @Observable final classes to work around a SwiftUI limitation: a .sheet or .confirmationDialog attached directly to a Form Section inside a pushed NavigationStack destination (itself inside the Settings .sheet) presents-then-immediately-dismisses, tearing the parent sheet down. ICloudSyncModalsModel (ICloudSyncSection.swift:17) and DiagnosticsExportModel (DiagnosticsSection.swift:31) are the solution — they are allocated by the page-level container (ICloudSyncPage, DebugPage) and passed down as @Bindable, so the modal presentations anchor to a stable view above the Form. Both are @MainActor isolated. The remaining sections (TrashSection, NotificationsSection, CrashReportingSection, QuickCaptureSection) take a @Binding<PreferencesStore.Prefs> and write through it; SettingsTab owns the one async read and a .onChange persister so the binding is always backed by live store state. RemindersImportSection and AdvancedSection use local @State rather than the shared prefs binding because their data is device-local (DevicePreferencesStore) or is not a preference at all.

## External deps

- LillistCore — imported
- LillistUI — imported
- SwiftUI — imported
- UIKit — imported
- UniformTypeIdentifiers — imported

## Gotchas

Sheet-on-Section teardown: attaching .sheet to a Form Section inside a nav-destination-in-a-sheet dismisses the parent Settings sheet immediately. The fix — host modals on the page container above the Form — is documented in the DiagnosticsSection header (Apps/Lillist-iOS/Sources/Settings/DiagnosticsSection.swift:6-10) and the ICloudSyncSection header (Apps/Lillist-iOS/Sources/Settings/ICloudSyncSection.swift:8-14). TrashSection.init coerces legacy custom trashRetentionDays values (e.g. 45 from an old slider) to the nearest preset before the Picker renders, silently fixing stale prefs (Apps/Lillist-iOS/Sources/Settings/TrashSection.swift:14-22). DiagnosticsExportModel uses a two-phase export flow (requestExport sets wantsExport=true, sheetDismissed fires buildAndShare) so the share sheet only presents after the include sheet fully disappears — one .sheet slot, no conflict (Apps/Lillist-iOS/Sources/Settings/DiagnosticsSection.swift:63-75).
