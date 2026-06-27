---
module: "Apps/Lillist-macOS/Sources (chunk 1)"
summary: "macOS app entry point: AppEnvironment composition root, LillistApp scenes, and macOS-specific surfaces."
read_when: "Touching macOS launch or AppEnvironment"
sources:
  - path: Apps/Lillist-macOS/Sources/AppDelegate.swift
    blob: fd5588ac73fa176eb0978da0a32f1614c97b3524
  - path: Apps/Lillist-macOS/Sources/AppEnvironment.swift
    blob: 4b09f7010fb9dcfa044818cf31e5bf0e4a4cca34
  - path: Apps/Lillist-macOS/Sources/Commands/CommandNotifications.swift
    blob: 7aff3d05672cf12da1aacf9a41b86b4ee760bb1b
  - path: Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift
    blob: 7b5ef967c54ac51a87e1a964d4b7a4c7bf5b864e
  - path: Apps/Lillist-macOS/Sources/Common/SceneBindings.swift
    blob: cdcd588c6b3281e488abc2397a33c90d9a5c4516
  - path: Apps/Lillist-macOS/Sources/CrashReporterHost.swift
    blob: b3a56574761886ab64c2efdb80bab618ec92c82e
  - path: Apps/Lillist-macOS/Sources/Editor/EditorOpenDecision.swift
    blob: 886dc8df7fdd02054ac98860626e6748af72fda2
  - path: Apps/Lillist-macOS/Sources/Editor/MacTaskEditorHost.swift
    blob: 5cc30f86a9c6a89cb48c3ab14689905fc370ea3b
  - path: Apps/Lillist-macOS/Sources/Indexing/IndexingMappers.swift
    blob: 8c68ace7364c0e1eb64600e2c237bb2f984f4c17
  - path: Apps/Lillist-macOS/Sources/Indexing/IndexingService.swift
    blob: c00e14675bbccb261ed0a76c199264a7e474303a
  - path: Apps/Lillist-macOS/Sources/LillistApp.swift
    blob: a69509a46bc2ccccbdb0ac712529f58567bc630e
  - path: Apps/Lillist-macOS/Sources/MailtoTransport.swift
    blob: 62d6df19a2ee52c3dfa72c411577dd2e4dd94d22
  - path: Apps/Lillist-macOS/Sources/MenuBar/MenuBarExtraScene.swift
    blob: 02305835ca157cd328fca49ebd3ce7147f10c615
  - path: Apps/Lillist-macOS/Sources/Onboarding/OnboardingSheet.swift
    blob: e252864f910909a073621b494fddf7d062eade3f
  - path: Apps/Lillist-macOS/Sources/Services/LillistServicesProvider.swift
    blob: 7fbe83aa6c8cda947dd2df8601c8b2166e107e4a
references_modules: [Apps-Lillist-macOS-Sources-Hotkey, Apps-Lillist-macOS-Sources-Preferences, Apps-Lillist-macOS-Sources-chunk-2, Packages-LillistCore-Sources-LillistCore-Backup, Packages-LillistCore-Sources-LillistCore-CrashReporting, Packages-LillistCore-Sources-LillistCore-Diagnostics, Packages-LillistCore-Sources-LillistCore-Export, Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistCore-Sources-LillistCore-Notifications, Packages-LillistCore-Sources-LillistCore-Persistence, Packages-LillistCore-Sources-LillistCore-Reminders, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistCore-Sources-LillistCore-Sync-chunk-1, Packages-LillistCore-Sources-LillistCore-Sync-chunk-2, Packages-LillistCore-Sources-LillistCore-misc, Packages-LillistUI-Sources-LillistUI-Accessibility, Packages-LillistUI-Sources-LillistUI-Components-chunk-1, Packages-LillistUI-Sources-LillistUI-CrashReporting, Packages-LillistUI-Sources-LillistUI-Editor, Packages-LillistUI-Sources-LillistUI-Onboarding, Packages-LillistUI-Sources-LillistUI-Recurrence, Packages-LillistUI-Sources-LillistUI-Settings, Packages-LillistUI-Sources-LillistUI-Status, Packages-LillistUI-Sources-LillistUI-Sync, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1, Packages-LillistUI-Sources-LillistUI-iOS-Tasks, Packages-LillistUI-Sources-LillistUI-iOS-misc]
generator: cartographer/4
baseline: 8e926f08fd5269de164d25b42880893a604a9d5c
---

# Module: Apps/Lillist-macOS/Sources (chunk 1)

## Purpose

This module is the macOS app entry point and composition root. `LillistApp` declares the SwiftUI scene graph; `AppEnvironment` constructs and owns every LillistCore store, scheduler, and service that the whole app touches. If this module vanished, the macOS app would have no launch sequence, no environment graph, and no macOS-specific surfaces (Spotlight, dock badge, menu-bar extra, Services integration, onboarding sheet, crash reporter host).

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AppDelegate` | class | `Apps/Lillist-macOS/Sources/AppDelegate.swift:14` | AppKit bridge owning the quick-capture panel, hotkey wiring, dock badge observer, Spotlight service, and Services provider for the process lifetime. |
| `AppEnvironment` | class | `Apps/Lillist-macOS/Sources/AppEnvironment.swift:15` | Root `@Observable` composition object on `@MainActor`; holds every LillistCore store, scheduler, sync service, and macOS singleton as `let` properties. Never exposes `NSManagedObject` to callers. |
| `CommandNotifications` | enum | `Apps/Lillist-macOS/Sources/Commands/CommandNotifications.swift:32` | Registry of notification names posted by the `LillistCommands` menu surface; currently empty (`postedByCommands: []`) because ⌘N flips a binding rather than posting. |
| `CrashReporterHost` | struct | `Apps/Lillist-macOS/Sources/CrashReporterHost.swift:7` | Wraps the scene root; presents `CrashReportSheet` via `.sheet(item:)` when `detectAndPrepare()` returns a pending report and `crashPromptsEnabled` is true. |
| `EditorOpenDecision` | enum | `Apps/Lillist-macOS/Sources/Editor/EditorOpenDecision.swift:16` | Discriminated union of three panel outcomes: `.present(request)`, `.retarget(id)`, `.noop`; produced exclusively by `decide(isOpen:request:)`. |
| `EditorOpenRequest` | enum | `Apps/Lillist-macOS/Sources/Editor/EditorOpenDecision.swift:11` | Input to `EditorOpenDecision.decide`: `.quickCapture` for a new draft, `.existing(UUID)` for opening a specific task. |
| `EnvironmentValues` | extension | `Apps/Lillist-macOS/Sources/Common/SceneBindings.swift:22` | Adds `isQuickCapturePresentedBinding` (in-window editor trigger) and `sortBinding` (per-machine `@AppStorage`-backed sort) to the SwiftUI environment. |
| `IndexingMappers` | enum | `Apps/Lillist-macOS/Sources/Indexing/IndexingMappers.swift:10` | Namespace for pure, testable factory functions mapping `TaskStore.TaskRecord` → `CSSearchableItemAttributeSet` and `CSSearchableItem`; no Core Data access or Spotlight side effects. |
| `IndexingService` | class | `Apps/Lillist-macOS/Sources/Indexing/IndexingService.swift:17` | `@MainActor` class that keeps tasks indexed in Spotlight; performs a full reindex on first launch or signature bump and subscribes to Core Data saves for incremental updates. |
| `IsQuickCapturePresentedBindingKey` | struct | `Apps/Lillist-macOS/Sources/Common/SceneBindings.swift:14` | Environment key for the `Binding<Bool>` that triggers the in-window unified editor's new-capture flow from both `LillistCommands` (⌘N) and the FAB. |
| `LillistApp` | struct | `Apps/Lillist-macOS/Sources/LillistApp.swift:32` | `@main` App struct; declares the main WindowGroup, Settings, and MenuBarExtra scenes; wires `AppDelegate` via `@NSApplicationDelegateAdaptor`; orchestrates environment load and UI-test seams. |
| `LillistCommands` | struct | `Apps/Lillist-macOS/Sources/Commands/LillistCommands.swift:13` | SwiftUI `Commands`: installs ⌘N as "New Task" (replacing default new-window), a custom About panel with byline, and a GitHub help link. |
| `LillistServicesProvider` | class | `Apps/Lillist-macOS/Sources/Services/LillistServicesProvider.swift:14` | AppKit `NSObject` registered as `NSApp.servicesProvider`; receives "Add to Lillist as task" selections and creates a task via `taskStore.create` with first-line title, remaining text as notes. |
| `MacTaskEditorHost` | struct | `Apps/Lillist-macOS/Sources/Editor/MacTaskEditorHost.swift:27` | Singleton in-window overlay host for the unified task editor; reacts to `newCaptureTrigger` (FAB/⌘N) and `openTaskID` (row tap) bindings; uses `NSOpenPanel` for attachments. |
| `MailtoTransport` | struct | `Apps/Lillist-macOS/Sources/MailtoTransport.swift:10` | macOS `CrashReportTransport`: writes report to a temp `.lillistcrash` file via `FileSaveTransport` then opens a `mailto:` URL; user must manually attach the file. |
| `MenuBarExtraScene` | struct | `Apps/Lillist-macOS/Sources/MenuBar/MenuBarExtraScene.swift:22` | SwiftUI `MenuBarExtra` scene with `.window` style; conditionally inserted via `isInserted:` binding so it can be toggled in Preferences without a relaunch. |
| `MigrationJournal` | extension | `Apps/Lillist-macOS/Sources/LillistApp.swift:402` | Retroactive `Identifiable` conformance on `MigrationJournal` so it can drive `.sheet(item:)` in `OnboardingPresentationModifier`. |
| `Notification` | extension | `Apps/Lillist-macOS/Sources/Commands/CommandNotifications.swift:14` | Declares the four macOS shell notification names (`tasksDidChange`, `selectTodayFilter`, `selectFilter`, `reopenMainWindow`) consumed by `MacTasksView` and `LillistApp`. |
| `OnboardingSheet` | struct | `Apps/Lillist-macOS/Sources/Onboarding/OnboardingSheet.swift:22` | First-launch macOS onboarding sheet; one-screen presenter with notification permission request, hotkey bullet, and three completion paths; non-dismissable interactively. |
| `SortBindingKey` | struct | `Apps/Lillist-macOS/Sources/Common/SceneBindings.swift:18` | Environment key for the `Binding<TasksSort>` backed by `@AppStorage("lillist.macos.sort")` and threaded down to `MacTasksView`. |
| `applicationDidFinishLaunching` | func | `Apps/Lillist-macOS/Sources/AppDelegate.swift:35` | Pins NSApp.appearance for UI-test appearance args only; all real wiring is deferred to `bootstrap()` to avoid racing AppEnvironment availability. |
| `applicationDockMenu` | func | `Apps/Lillist-macOS/Sources/AppDelegate.swift:173` | Returns an NSMenu built synchronously from `pinnedFilterCache`; items: Quick Capture, Today's Tasks, and pinned smart filters with their stored UUIDs as representedObject. |
| `applicationShouldHandleReopen` | func | `Apps/Lillist-macOS/Sources/AppDelegate.swift:56` | When no visible windows exist, activates the app and posts `.lillistReopenMainWindow` so `MainWindowReopener` can invoke `openWindow(id: "main")`; always returns true. |
| `applicationWillTerminate` | func | `Apps/Lillist-macOS/Sources/AppDelegate.swift:105` | Uninstalls the global hotkey and calls `crashReporter.markCleanExit()` with a ≤2 s timeout so the canary is deleted before process teardown. |
| `attributeSet` | func | `Apps/Lillist-macOS/Sources/Indexing/IndexingMappers.swift:20` | Constructs a `CSSearchableItemAttributeSet` from title, notes, and tag-name keywords; pure function safe to call in tests without a live index. |
| `body` | func | `Apps/Lillist-macOS/Sources/Editor/MacTaskEditorHost.swift:36` | Applies `.taskEditorOverlay` with `TaskEditorView` inside and `.onChange` handlers routing `newCaptureTrigger` → `openNewCapture` and `openTaskID` → `openExisting`. |
| `body` | func | `Apps/Lillist-macOS/Sources/LillistApp.swift:21` | Lays content at `1/scale` of available space then applies `.scaleEffect(scale, anchor: .topLeading)` so the iOS surface reflowed to Mac density without forking design tokens. |
| `body` | func | `Apps/Lillist-macOS/Sources/LillistApp.swift:310` | Applies onboarding, iCloud-unavailable, and migration-recovery sheets as `.sheet(isPresented:)` / `.sheet(item:)` modifiers; drives them via a one-shot `evaluate()` call in `.task`. |
| `body` | func | `Apps/Lillist-macOS/Sources/LillistApp.swift:415` | Subscribes to `.lillistReopenMainWindow` notifications and calls `openWindow(id: "main")` to re-spawn the main window after ⌘W or menu-bar-popover reopen. |
| `bootstrap` | func | `Apps/Lillist-macOS/Sources/AppDelegate.swift:64` | Idempotent (guard on `quickCapturePanel == nil`); wires the hotkey panel, installs dock badge observer, registers NSApp.servicesProvider, and starts Spotlight indexing. |
| `bootstrap` | func | `Apps/Lillist-macOS/Sources/AppEnvironment.swift:346` | One-shot async startup: runs preferences migration, notification scheduling, auto-purge, backup bootstrap, history prune, crash hydration, iCloud account prime, sync-mode/pause-reason observation, and Reminders drain registration. |
| `checkForUpdates` | func | `Apps/Lillist-macOS/Sources/AppDelegate.swift:31` | Delegates to `SPUStandardUpdaterController.checkForUpdates()`; called from the "Check for Updates…" menu item in the app menu. |
| `decide` | func | `Apps/Lillist-macOS/Sources/Editor/EditorOpenDecision.swift:24` | Pure function: returns `.noop` for a quick-capture request while the panel is open; `.retarget(id)` for an existing-task request on an open panel; `.present` otherwise. |
| `make` | func | `Apps/Lillist-macOS/Sources/AppEnvironment.swift:304` | Async factory: loads the Core Data store with the stored sync mode, wires all stores and services, returns a fully constructed `AppEnvironment`; throws if the store fails to load. |
| `refreshDockBadge` | func | `Apps/Lillist-macOS/Sources/AppDelegate.swift:149` | Fetches the Today filter's task count and sets `NSApp.dockTile.badgeLabel`; clears the badge on zero count or any error. |
| `refreshPinnedFilterCache` | func | `Apps/Lillist-macOS/Sources/AppDelegate.swift:165` | Refreshes `pinnedFilterCache` to the subset of smart filters where `isPinned == true`; read synchronously by `applicationDockMenu`. |
| `reindexAll` | func | `Apps/Lillist-macOS/Sources/Indexing/IndexingService.swift:60` | Fetches all live and trashed tasks, upserts live items into `CSSearchableIndex.default()`, removes trashed IDs; errors logged with type-only privacy. |
| `searchableItem` | func | `Apps/Lillist-macOS/Sources/Indexing/IndexingMappers.swift:33` | Constructs a `CSSearchableItem` with `uniqueIdentifier = record.id.uuidString` and `domainIdentifier = IndexingMappers.domainIdentifier`. |
| `send` | func | `Apps/Lillist-macOS/Sources/MailtoTransport.swift:15` | Saves the crash report via `FileSaveTransport`, builds a `mailto:` URL with subject/body, opens it in NSWorkspace, and selects the temp file in Finder for easy attachment. |
| `start` | func | `Apps/Lillist-macOS/Sources/Indexing/IndexingService.swift:30` | Idempotent: checks `lillist.spotlight.indexSignature` in UserDefaults and triggers `reindexAll()` if stale, then installs the Core Data save observer. |
| `stop` | func | `Apps/Lillist-macOS/Sources/Indexing/IndexingService.swift:40` | Removes the `NSManagedObjectContextDidSave` observer and clears `saveObserver`; safe to call multiple times. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `LaunchSheet` | enum | `Apps/Lillist-macOS/Sources/LillistApp.swift:296` | Single-slot Identifiable enum multiplexing three mutually exclusive launch gates (iCloudUnavailable, onboarding, recovery(MigrationJournal)) behind one .sheet(item:) binding. Prevents the sheet-clobber bug that three stacked .sheet modifiers cause during iCloud-unavailable → onboarding handoff; each transition is a clean slot swap. The .recovery case carries the MigrationJournal so the sheet id fingerprints the specific failure (enabling retry re-presentation). Grounded at Apps/Lillist-macOS/Sources/LillistApp.swift:291–308. |
| `MainWindowReopener` | struct | `Apps/Lillist-macOS/Sources/LillistApp.swift:413` | Subscribes to `.lillistReopenMainWindow` and calls `openWindow(id: "main")`; without it, ⌘W close is permanent — SwiftUI's `WindowGroup` does not auto-reopen on Dock activation. |
| `OnboardingPresentationModifier` | struct | `Apps/Lillist-macOS/Sources/LillistApp.swift:286` | First-launch gate: drives the decision among onboarding sheet, iCloud-unavailable screen, and migration-recovery sheet; blocks main-window content until the user proceeds. |
| `cancel` | func | `Apps/Lillist-macOS/Sources/Editor/MacTaskEditorHost.swift:87` | Discriminates cancel intent: calls `model.discard()` for a new capture draft, `model.saveTextNow()` for an existing task; guards against data loss on tap-outside / Esc. |
| `complete` | func | `Apps/Lillist-macOS/Sources/Onboarding/OnboardingSheet.swift:130` | The single completion gate for onboarding: both the primary 'Get started' CTA (Apps/Lillist-macOS/Sources/Onboarding/OnboardingSheet.swift:100) and the 'Skip for now' link (line 117) call `complete()`, which calls `onboardingState.markCompleted()` and fires the `onCompleted` closure (line 141-142). The third button — 'Set up notifications' (line 88) — calls `requestPermission()` instead and does not route through here. |
| `dismissCommitted` | func | `Apps/Lillist-macOS/Sources/Editor/MacTaskEditorHost.swift:79` | Handles the committed-save dismissal path: closes the overlay and fires `onChanged()` to refresh the task list after a successful Add/Done. |
| `evaluate` | func | `Apps/Lillist-macOS/Sources/LillistApp.swift:359` | Decision function for first-launch gating: checks migration journal staleness, onboarding completion, and iCloud account availability to select which sheet to surface. |
| `isAvailable` | func | `Apps/Lillist-macOS/Sources/LillistApp.swift:394` | Pure mapping from `iCloudAccountState` → `Bool` used by `evaluate()` to decide the onboarding path; incorrect classification would route new users into the wrong setup flow. |
| `loadEnvironmentIfNeeded` | func | `Apps/Lillist-macOS/Sources/LillistApp.swift:158` | The async environment-load gate called from the main WindowGroup `.task`; handles UI-test seams, calls `AppEnvironment.make()`, then triggers both `appDelegate.bootstrap()` and `env.bootstrap()`. |
| `openExisting` | func | `Apps/Lillist-macOS/Sources/Editor/MacTaskEditorHost.swift:70` | Re-targets the singleton editor to an existing task by constructing a new `TaskEditorModel` and calling `load()`; ensures row-tap opening always shows the correct task. |
| `openNewCapture` | func | `Apps/Lillist-macOS/Sources/Editor/MacTaskEditorHost.swift:62` | Guards the singleton invariant (no-op if already presented) before constructing a new-capture `TaskEditorModel`; prevents stacked editors. |
| `presentAttachmentPicker` | func | `Apps/Lillist-macOS/Sources/Editor/MacTaskEditorHost.swift:102` | Owns the macOS-specific attachment flow: opens `NSOpenPanel` restricted to images and calls `model.addImageAttachment`; the only attachment entry point for the in-window editor on macOS. |
| `requestPermission` | func | `Apps/Lillist-macOS/Sources/Onboarding/OnboardingSheet.swift:124` | Calls `notificationPermissions.requestAuthorization()` and updates `permissionStatus` state; drives the "Set up notifications" button and disables it once a decision is made. |
| `startObservingAccountState` | func | `Apps/Lillist-macOS/Sources/AppEnvironment.swift:420` | Pumps `AccountStateMonitor.stateStream` into the `@Observable` `accountState` field on every change; without it, `accountState` never updates from its initial `.noAccount` value, breaking the onboarding iCloud gate. |
| `startObservingPauseReason` | func | `Apps/Lillist-macOS/Sources/AppEnvironment.swift:448` | Re-classifies the sync pause reason on every iCloud account-state change, mirroring iOS behavior; without it, `pauseReason` is never updated after bootstrap, leaving the macOS sync surface stale. |
| `startObservingSyncMode` | func | `Apps/Lillist-macOS/Sources/AppEnvironment.swift:434` | Bridges `SyncModeStore.modeStream` → `AppEnvironment.currentSyncMode` so the Preferences pane and status surfaces react immediately to mode changes without polling. |
| `uiTestResetState` | func | `Apps/Lillist-macOS/Sources/LillistApp.swift:213` | UI-test state reset primitive: wipes App Group container, app support dir, and UserDefaults then pre-marks onboarding complete in LocalOnly mode for a clean test run. |

## Relationships

- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Apps-Lillist-macOS-Sources-Hotkey.GlobalHotkeyMonitor (owns)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Apps-Lillist-macOS-Sources-Hotkey.install (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Apps-Lillist-macOS-Sources-Hotkey.reregister (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Backup.BackupRestoreService (owns)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Backup.BackupSnapshotManager (owns)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Backup.LocalBackupCoordinator (owns)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Backup.TaskBackupStore (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-CrashReporting.BreadcrumbBuffer (owns)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CanaryFile (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReporter (owns)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-CrashReporting.OSLogFetcher (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-CrashReporting.defaultURL (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticHistoryObserver (owns)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Diagnostics.shared (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Export.Importer (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Notifications.NotificationPermissions (owns)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Notifications.NotificationScheduler (owns)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Notifications.NotificationSpecStore (owns)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Notifications.SnoozeRegistry (owns)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Notifications.SystemUserNotificationCenter (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Notifications.current (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Persistence.AutoPurgeJob (owns)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistentHistoryTokenStore (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Persistence.QuarantineManager (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Persistence.localTaskRowCount (reads)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Reminders.EventKitRemindersGateway (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Reminders.RemindersImporter (owns)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.AttachmentStore (owns)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.JournalStore (owns)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SeriesStore (owns)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.AccountStateMonitor (owns)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.CloudKitAccountStatusProvider (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.ConstantNetworkReachability (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.LiveCloudKitZoneEraser (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.MigrationCoordinator (owns)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.PauseReasonClassifier (owns)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-2.SyncQuiesceMonitor (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-2.SyncStatusMonitor (owns)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-misc.AppPreferencesPartitionMigrator (owns)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-misc.DefaultsInstaller (owns)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-misc.OnboardingState (owns)`
- `Apps-Lillist-macOS-Sources-chunk-1.AppEnvironment -> Packages-LillistUI-Sources-LillistUI-Status.CloudKitSyncStatusAdapter (owns)`
- `Apps-Lillist-macOS-Sources-chunk-1.CrashReporterHost -> Packages-LillistCore-Sources-LillistCore-CrashReporting.detectAndPrepare (reads)`
- `Apps-Lillist-macOS-Sources-chunk-1.CrashReporterHost -> Packages-LillistUI-Sources-LillistUI-CrashReporting.CrashReportSheet (owns)`
- `Apps-Lillist-macOS-Sources-chunk-1.CrashReporterHost -> Packages-LillistUI-Sources-LillistUI-CrashReporting.CrashReportViewModel (owns)`
- `Apps-Lillist-macOS-Sources-chunk-1.EditorOpenDecision -> Apps-Lillist-macOS-Sources-Hotkey.present (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1.LillistApp -> Apps-Lillist-macOS-Sources-Preferences.PreferencesWindow (owns)`
- `Apps-Lillist-macOS-Sources-chunk-1.LillistApp -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.registerIfNeeded (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1.LillistApp -> Packages-LillistUI-Sources-LillistUI-iOS-Tasks.TasksSort (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1.LillistServicesProvider -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1.LillistServicesProvider -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1.MainWindowReopener -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1.MenuBarPopover -> Apps-Lillist-macOS-Sources-Hotkey.open (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1.MenuBarPopover -> Apps-Lillist-macOS-Sources-chunk-2.TodayPopoverView (owns)`
- `Apps-Lillist-macOS-Sources-chunk-1.MenuBarPopover -> Packages-LillistUI-Sources-LillistUI-Accessibility.post (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1.MenuBarPopover -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1.OnboardingSheet -> Apps-Lillist-macOS-Sources-Hotkey.open (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1.OnboardingSheet -> Packages-LillistCore-Sources-LillistCore-Notifications.currentStatus (reads)`
- `Apps-Lillist-macOS-Sources-chunk-1.OnboardingSheet -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1.DotGridBackdrop (owns)`
- `Apps-Lillist-macOS-Sources-chunk-1.OnboardingSheet -> Packages-LillistUI-Sources-LillistUI-Onboarding.OnboardingContent (owns)`

## Type notes

`AppEnvironment` is `@MainActor @Observable`; all stored `let` properties are wired in `init` and `make()` is `async throws` because `PersistenceController.init` is (`AppEnvironment.swift:13-15`). `AppDelegate` is `@MainActor final class` installed via `@NSApplicationDelegateAdaptor`; its `bootstrap()` is called from `LillistApp.task` *after* `AppEnvironment.make()` succeeds — not from `applicationDidFinishLaunching` — to avoid racing environment availability (`AppDelegate.swift:36-38`, `LillistApp.swift:174`). `LillistServicesProvider` is `@MainActor final class`; `NSApp.servicesProvider` holds it `unowned`, so `AppDelegate.servicesProvider` must retain a strong reference or it deallocates immediately after `bootstrap()` (`AppDelegate.swift:93-97`). `IndexingService` is `@MainActor final class`; the `NSManagedObjectContextDidSave` observer it installs keeps it alive for the process lifetime via `AppDelegate.indexingService` (`AppDelegate.swift:103`). `MailtoTransport` is the sole macOS `CrashReportTransport`; it writes a temp `.lillistcrash` file via `FileSaveTransport` then opens a `mailto:` URL — the user must attach the file manually (`MailtoTransport.swift:15-44`). `OnboardingPresentationModifier` and `MainWindowReopener` are `private struct ViewModifier` types declared at the bottom of `LillistApp.swift`; they are never exposed outside the file.

## External deps

- AppKit — imported
- CloudKit — imported
- CoreData — imported
- CoreSpotlight — imported
- Foundation — imported
- LillistCore — imported
- LillistUI — imported
- Observation — imported
- Sparkle — imported
- SwiftUI — imported

## Gotchas

`CrashReporterHost` arms the canary lazily via its `.task` modifier, never from `AppEnvironment.bootstrap()`. A prior version called `detectAndPrepare()` in `bootstrap()`, which wrote a canary that was immediately read back as evidence of a crash — popping the report sheet on every launch (`AppEnvironment.swift:374-381`). `NSApp.servicesProvider` holds the provider `unowned`; `AppDelegate.servicesProvider` must hold a strong reference or the provider is deallocated immediately after `bootstrap()` returns (`AppDelegate.swift:93-97`). `OnboardingSheet` uses explicit constructor injection rather than `@Environment` reads because SwiftUI sheet presentation creates a fresh environment chain; silent env lookups would crash on first paint (`OnboardingSheet.swift:19-22`). The main window renders the shared iOS surface at 0.75 scale via `ScaledWindowContent`; the layout is reflowed at `1/scale` of the window canvas before scaling down, so hit-testing maps correctly but text raster is slightly soft at non-integral scales (`LillistApp.swift:17-28`).
