---
module: Apps/Lillist-iOS/Sources/Settings/Pages
summary: "Eight iOS Settings push-destination pages that wrap env-coupled sections inside SettingsDetailScreen chrome."
read_when: "Restructuring iOS Settings nav destinations"
sources:
  - path: Apps/Lillist-iOS/Sources/Settings/Pages/AppearancePage.swift
    blob: 7ba0f3187182d9419c711baf13fd14c81f7b3300
  - path: Apps/Lillist-iOS/Sources/Settings/Pages/DataManagementPage.swift
    blob: 7fbbe22d508490fef1742d84d427e756c130f85b
  - path: Apps/Lillist-iOS/Sources/Settings/Pages/DebugPage.swift
    blob: d27d8162fad2b49fd3db057a3c97882b369c0ad8
  - path: Apps/Lillist-iOS/Sources/Settings/Pages/ICloudSyncPage.swift
    blob: 0fac2ae3807c7921a858e5c78f0458dcce2b5244
  - path: Apps/Lillist-iOS/Sources/Settings/Pages/NotificationsPage.swift
    blob: a80abff7dcf0788764e95fa779047b82de8e7f61
  - path: Apps/Lillist-iOS/Sources/Settings/Pages/QuickCapturePage.swift
    blob: 070cf9a9599cc8b40110499ca357ea9e4f4bc6a2
  - path: Apps/Lillist-iOS/Sources/Settings/Pages/RemindersImportPage.swift
    blob: 5f78f573662cfd0a1f35a46b2f815544f4b655f9
  - path: Apps/Lillist-iOS/Sources/Settings/Pages/TaskDefaultsPage.swift
    blob: 62514212653db5952119c175a2dcec317e20f7d8
references_modules: [Apps-Lillist-iOS-Sources-Settings-misc, Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistUI-Sources-LillistUI-Settings, Packages-LillistUI-Sources-LillistUI-Sync, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1, Packages-LillistUI-Sources-LillistUI-iOS-misc]
generator: cartographer/4
baseline: 99321d774840d17affd02fe2ac63b01b3d8cbec3
---

# Module: Apps/Lillist-iOS/Sources/Settings/Pages

## Purpose

This module is the navigation-destination layer for the iOS Settings screen: each file is one second-level page that serves as the push target for a Settings menu row. The pages do no state management themselves — they assemble one or more env-coupled Section components inside the shared `SettingsDetailScreen` chrome from LillistUI. Without this layer the settings `NavigationStack` has no destinations, and every settings row in the parent screen would be dead.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AppearancePage` | struct | `Apps/Lillist-iOS/Sources/Settings/Pages/AppearancePage.swift:7` | Settings page for Appearance; caller provides `$prefs` binding; presents a ColorPicker bound to `prefs.defaultTagTintHex` with hex round-trip fallback. |
| `DataManagementPage` | struct | `Apps/Lillist-iOS/Sources/Settings/Pages/DataManagementPage.swift:7` | Settings page for Data Management; caller provides `$prefs` binding; composes TrashSection, BackupSection, and AdvancedSection inside SettingsDetailScreen. |
| `DebugPage` | struct | `Apps/Lillist-iOS/Sources/Settings/Pages/DebugPage.swift:14` | Settings page for Debug; caller provides `$prefs` binding; composes CrashReportingSection, DiagnosticsSection, and ResetDataStoreSection. |
| `ICloudSyncPage` | struct | `Apps/Lillist-iOS/Sources/Settings/Pages/ICloudSyncPage.swift:11` | Settings page for iCloud Sync; stateless (no stored properties); wraps ICloudSyncSection which reads AppEnvironment directly. |
| `NotificationsPage` | struct | `Apps/Lillist-iOS/Sources/Settings/Pages/NotificationsPage.swift:8` | Settings page for Notifications; caller provides `$prefs` binding; wraps NotificationsSection inside SettingsDetailScreen chrome. |
| `QuickCapturePage` | struct | `Apps/Lillist-iOS/Sources/Settings/Pages/QuickCapturePage.swift:8` | Settings page for Quick Capture; caller provides `$prefs` binding; wraps QuickCaptureSection inside SettingsDetailScreen chrome. |
| `RemindersImportPage` | struct | `Apps/Lillist-iOS/Sources/Settings/Pages/RemindersImportPage.swift:7` | Settings page for Tasks from Reminders; stateless (no stored properties); wraps RemindersImportSection which reads AppEnvironment directly. |
| `TaskDefaultsPage` | struct | `Apps/Lillist-iOS/Sources/Settings/Pages/TaskDefaultsPage.swift:8` | Settings page for Task Defaults; caller provides `$prefs` binding; presents a Picker for `prefs.defaultTaskListSort` over `SortField.allCases`. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

- `Apps-Lillist-iOS-Sources-Settings-Pages.AppearancePage -> Packages-LillistUI-Sources-LillistUI-Settings.SettingsDetailScreen (owns)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.AppearancePage -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.Color (calls)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.AppearancePage -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.toHex (calls)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.DataManagementPage -> Apps-Lillist-iOS-Sources-Settings-misc.AdvancedSection (owns)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.DataManagementPage -> Apps-Lillist-iOS-Sources-Settings-misc.BackupSection (owns)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.DataManagementPage -> Apps-Lillist-iOS-Sources-Settings-misc.TrashSection (owns)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.DataManagementPage -> Packages-LillistUI-Sources-LillistUI-Settings.SettingsDetailScreen (owns)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.DebugPage -> Apps-Lillist-iOS-Sources-Settings-misc.CrashReportingSection (calls)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.DebugPage -> Apps-Lillist-iOS-Sources-Settings-misc.DiagnosticsExportModel (owns)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.DebugPage -> Apps-Lillist-iOS-Sources-Settings-misc.DiagnosticsSection (calls)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.DebugPage -> Apps-Lillist-iOS-Sources-Settings-misc.ResetDataStoreSection (calls)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.DebugPage -> Apps-Lillist-iOS-Sources-Settings-misc.ShareSheet (calls)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.DebugPage -> Apps-Lillist-iOS-Sources-Settings-misc.requestExport (calls)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.DebugPage -> Apps-Lillist-iOS-Sources-Settings-misc.sheetDismissed (calls)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.DebugPage -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.DebugPage -> Packages-LillistUI-Sources-LillistUI-Settings.SettingsDetailScreen (calls)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.DebugPage -> Packages-LillistUI-Sources-LillistUI-iOS-misc.DiagnosticsIncludeSheet (calls)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.ICloudSyncPage -> Apps-Lillist-iOS-Sources-Settings-misc.ICloudSyncModalsModel (owns)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.ICloudSyncPage -> Apps-Lillist-iOS-Sources-Settings-misc.ICloudSyncSection (calls)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.ICloudSyncPage -> Apps-Lillist-iOS-Sources-Settings-misc.confirmReplace (calls)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.ICloudSyncPage -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.ICloudSyncPage -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.ICloudSyncPage -> Packages-LillistUI-Sources-LillistUI-Settings.SettingsDetailScreen (calls)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.ICloudSyncPage -> Packages-LillistUI-Sources-LillistUI-Sync.PauseExplainerDialog (calls)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.ICloudSyncPage -> Packages-LillistUI-Sources-LillistUI-Sync.SyncDisableConfirmationSheet (calls)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.ICloudSyncPage -> Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationChoiceSheet (calls)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.ICloudSyncPage -> Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationProgressSheet (calls)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.NotificationsPage -> Apps-Lillist-iOS-Sources-Settings-misc.NotificationsSection (owns)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.NotificationsPage -> Packages-LillistUI-Sources-LillistUI-Settings.SettingsDetailScreen (owns)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.QuickCapturePage -> Apps-Lillist-iOS-Sources-Settings-misc.QuickCaptureSection (owns)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.QuickCapturePage -> Packages-LillistUI-Sources-LillistUI-Settings.SettingsDetailScreen (owns)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.RemindersImportPage -> Apps-Lillist-iOS-Sources-Settings-misc.RemindersImportSection (owns)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.RemindersImportPage -> Packages-LillistUI-Sources-LillistUI-Settings.SettingsDetailScreen (owns)`
- `Apps-Lillist-iOS-Sources-Settings-Pages.TaskDefaultsPage -> Packages-LillistUI-Sources-LillistUI-Settings.SettingsDetailScreen (owns)`

## Type notes

Six of the eight pages carry `@Binding var prefs: PreferencesStore.Prefs` and forward the binding directly to their child sections (AppearancePage.swift:8, DataManagementPage.swift:8, DebugPage.swift:9, NotificationsPage.swift:9, QuickCapturePage.swift:9, TaskDefaultsPage.swift:9). ICloudSyncPage and RemindersImportPage have no stored properties — their sections source all dependencies from AppEnvironment. All eight conform to SwiftUI `View` and are implicitly `@MainActor`-isolated. The uniform pattern is `SettingsDetailScreen(title) { sections... }` with no `@State`, `.task`, or lifecycle hooks at the page level.

## External deps

- LillistCore — imported
- LillistUI — imported
- SwiftUI — imported

## Gotchas

AppearancePage.swift:23 — the tint write-back uses `$0.toHex() ?? LillistTokens.defaultTagTintHex`: if `toHex()` returns nil (e.g. a system-adaptive Color that cannot round-trip through hex), the stored hex reverts to the token default rather than persisting nil or an empty string. ICloudSyncPage.swift and RemindersImportPage.swift carry no stored properties at all — their sections source all dependencies from AppEnvironment, so passing a prefs binding to these pages at the call site would be a silent no-op.
