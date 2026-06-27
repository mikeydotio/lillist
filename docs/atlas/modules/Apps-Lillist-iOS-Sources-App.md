---
module: Apps/Lillist-iOS/Sources/App
summary: "iOS app entry point: builds AppEnvironment object graph, runs bootstrap, and wires crash/mail transport"
read_when: "iOS app launch or bootstrap sequence"
sources:
  - path: Apps/Lillist-iOS/Sources/App/AppEnvironment.swift
    blob: 8d07dbbaa6d82dd80c5d263b81526635e89b64bc
  - path: Apps/Lillist-iOS/Sources/App/CrashReporterHost.swift
    blob: 18a647c008f3c042a21ac4d872571d29513ef0f8
  - path: Apps/Lillist-iOS/Sources/App/LillistApp.swift
    blob: 3a876dc1d85de09764cf9cbb33916d48ff2c2d0e
  - path: Apps/Lillist-iOS/Sources/App/MailComposerTransport.swift
    blob: af54dda7da2700518a16e86aebb5d4735e0bcc16
  - path: Apps/Lillist-iOS/Sources/App/MailComposerView.swift
    blob: 7888c20651cafd6509b97b2de2c4eabde8305685
  - path: Apps/Lillist-iOS/Sources/App/MetricKitObserver.swift
    blob: 198daf20635d64ed69d25a5b805147d26a4d653f
references_modules: [Apps-Lillist-iOS-Sources-misc, Packages-LillistCore-Sources-LillistCore-Backup, Packages-LillistCore-Sources-LillistCore-CrashReporting, Packages-LillistCore-Sources-LillistCore-Diagnostics, Packages-LillistCore-Sources-LillistCore-Export, Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistCore-Sources-LillistCore-Notifications, Packages-LillistCore-Sources-LillistCore-Persistence, Packages-LillistCore-Sources-LillistCore-Reminders, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Sync-chunk-1, Packages-LillistCore-Sources-LillistCore-Sync-chunk-2, Packages-LillistCore-Sources-LillistCore-misc, Packages-LillistUI-Sources-LillistUI-CrashReporting, Packages-LillistUI-Sources-LillistUI-Status, Packages-LillistUI-Sources-LillistUI-Sync, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1, Packages-LillistUI-Sources-LillistUI-iOS-Tasks]
generator: cartographer/4
baseline: 8e926f08fd5269de164d25b42880893a604a9d5c
---

# Module: Apps/Lillist-iOS/Sources/App

## Purpose

This module is the iOS app's launch and environment layer: it assembles all LillistCore stores and services into an `AppEnvironment` object graph, then bootstraps sync, notification, crash, and backup state before any view renders. It also owns the iOS crash-reporting pipeline (`MailComposerTransport`, `MailComposerView`, `MetricKitObserver`) and drives first-launch onboarding and stale-migration recovery via `OnboardingPresentationModifier`. Without it the app has no entry point, no environment graph, and no path from LillistCore actors into the SwiftUI hierarchy.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AppEnvironment` | class | `Apps/Lillist-iOS/Sources/App/AppEnvironment.swift:19` | The single `@MainActor @Observable` root that owns all stores, sync, crash, notification, and backup objects for the iOS app lifetime; always obtained via `.environment(AppEnvironment.self)`, never constructed directly. |
| `Coordinator` | class | `Apps/Lillist-iOS/Sources/App/MailComposerView.swift:34` | Bridges `MFMailComposeViewControllerDelegate` to SwiftUI by dismissing the VC and forwarding the result to `onFinish` via `MainActor.assumeIsolated`. |
| `CrashReporterHost` | struct | `Apps/Lillist-iOS/Sources/App/CrashReporterHost.swift:9` | Wraps any Content view; on `.task` it detects a prior crash and presents `CrashReportSheet`, and presents `MailComposerView` when the transport stages a send; no-ops when `crashPromptsEnabled` is false or `--ui-test-bypass-gates` is present. |
| `LillistApp` | struct | `Apps/Lillist-iOS/Sources/App/LillistApp.swift:7` | The `@main` App entry point; registers the BGTask purge handler during `init`, assembles the scene with `.task`-driven environment loading, and publishes `sortBinding` via the SwiftUI `Environment`. |
| `MailComposerTransport` | class | `Apps/Lillist-iOS/Sources/App/MailComposerTransport.swift:10` | Implements `CrashReportTransport` for iOS by encoding the report and staging a `Pending` value; the SwiftUI host observes `onStage` and presents `MailComposerView`. |
| `MailComposerView` | struct | `Apps/Lillist-iOS/Sources/App/MailComposerView.swift:5` | A `UIViewControllerRepresentable` that presents `MFMailComposeViewController` configured with the supplied recipient, subject, body, and optional JSON attachment. |
| `MetricKitObserver` | class | `Apps/Lillist-iOS/Sources/App/MetricKitObserver.swift:14` | Subscribes to MetricKit and logs diagnostic payload summaries (crash/hang/launch/cpu/disk counts) to `LillistLog.metrics`; must be held strongly by the app because MetricKit retains subscribers weakly. |
| `MigrationJournal` | extension | `Apps/Lillist-iOS/Sources/App/LillistApp.swift:300` | Retroactive `Identifiable` conformance on `MigrationJournal` so SwiftUI sheet bindings can drive presentation; id encodes state+operation+timestamp so retries change identity and re-present the sheet. |
| `Pending` | struct | `Apps/Lillist-iOS/Sources/App/MailComposerTransport.swift:11` | Sendable value carrying the composed email subject, plain-text body, and JSON attachment for a single staged crash report; `id` is the attachment filename. |
| `body` | func | `Apps/Lillist-iOS/Sources/App/LillistApp.swift:219` | Applies onboarding, iCloud-unavailable, and stale-migration-recovery full-screen covers; evaluation runs exactly once per lifecycle via `didEvaluate` guard; entirely bypassed under `--ui-test-bypass-gates`. |
| `bootstrap` | func | `Apps/Lillist-iOS/Sources/App/AppEnvironment.swift:412` | Must be called once after `make()` before any store is used; registers notification categories, primes account/sync/pause state, installs lifecycle observers, and starts all background workers. |
| `didReceive` | func | `Apps/Lillist-iOS/Sources/App/MetricKitObserver.swift:31` | Logs the count of received metric payloads to `LillistLog.metrics` with public privacy; no call-stack data is emitted. |
| `didReceive` | func | `Apps/Lillist-iOS/Sources/App/MetricKitObserver.swift:37` | Logs crash, hang, launch, CPU-exception, and disk-write-exception counts per diagnostic payload to `LillistLog.metrics`; no stack data is included. |
| `inMemory` | func | `Apps/Lillist-iOS/Sources/App/AppEnvironment.swift:391` | Returns an isolated in-memory environment wired to an ephemeral `.inMemory` store and a unique UserDefaults suite; safe to call concurrently from multiple test cases. |
| `mailComposeController` | func | `Apps/Lillist-iOS/Sources/App/MailComposerView.swift:48` | Dismisses the mail VC and forwards the completion result or error to the `onFinish` closure on the main actor. |
| `make` | func | `Apps/Lillist-iOS/Sources/App/AppEnvironment.swift:361` | Constructs the live on-disk environment by reading the persisted sync mode and selecting the App Group store configuration; throws if the Core Data store fails to load. |
| `makeCoordinator` | func | `Apps/Lillist-iOS/Sources/App/MailComposerView.swift:32` | Creates and returns a `Coordinator` bound to `onFinish`; called once by SwiftUI at VC creation time. |
| `makeUIViewController` | func | `Apps/Lillist-iOS/Sources/App/MailComposerView.swift:18` | Configures and returns a `MFMailComposeViewController` with the view's recipient, subject, body, and optional attachment data. |
| `runBackgroundPurge` | func | `Apps/Lillist-iOS/Sources/App/AppEnvironment.swift:491` | Entry point for the iOS background-processing BGTask; runs the trash auto-purge and returns true on success so the BGTask can report completion. |
| `scheduleBackgroundPurge` | func | `Apps/Lillist-iOS/Sources/App/LillistApp.swift:176` | Submits a `BGProcessingTaskRequest` for the trash purge; safe to call repeatedly because BGTaskScheduler coalesces duplicate task identifiers. |
| `send` | func | `Apps/Lillist-iOS/Sources/App/MailComposerTransport.swift:27` | Encodes the crash report to JSON, packages it into a `Pending`, and calls `onStage`; throws only if JSON encoding fails. |
| `startReceiving` | func | `Apps/Lillist-iOS/Sources/App/MetricKitObserver.swift:16` | Registers the observer with `MXMetricManager.shared`; idempotent per instance. |
| `stopReceiving` | func | `Apps/Lillist-iOS/Sources/App/MetricKitObserver.swift:21` | Unregisters the observer from `MXMetricManager.shared`; called defensively from `deinit`. |
| `updateUIViewController` | func | `Apps/Lillist-iOS/Sources/App/MailComposerView.swift:30` | No-op; the VC is fully configured at creation and requires no SwiftUI-driven updates. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `LaunchSheet` | enum | `Apps/Lillist-iOS/Sources/App/LillistApp.swift:205` | Single-slot enum driving OnboardingPresentationModifier's .fullScreenCover(item:), enforcing mutual exclusivity across the three launch gates (iCloudUnavailable, onboarding, recovery). Its Identifiable id fingerprints each gate case so the iCloud-unavailable → onboarding handoff is a clean slot swap rather than a sheet-clobbering dismiss-and-re-present on stacked modifiers. Guards the invariant at Apps/Lillist-iOS/Sources/App/LillistApp.swift:205. |
| `OnboardingPresentationModifier` | struct | `Apps/Lillist-iOS/Sources/App/LillistApp.swift:195` | Controls the three first-launch gates (onboarding, iCloud-unavailable, stale-migration recovery); omitting it means new users bypass onboarding and crash-recovery is never surfaced. LillistApp.swift:195-282. |
| `evaluate` | func | `Apps/Lillist-iOS/Sources/App/LillistApp.swift:266` | Inspects the migration journal for a stale in-flight state and drives the three-way fork (recovery / iCloud-unavailable / onboarding); the `didEvaluate` guard guarantees exactly one evaluation per lifecycle. LillistApp.swift:250-275. |
| `isAvailable` | func | `Apps/Lillist-iOS/Sources/App/LillistApp.swift:292` | Maps `iCloudAccountState` to the Bool gate used by `evaluate` to choose between iCloud onboarding and the unavailable flow; owns the policy of which account states permit iCloud onboarding. LillistApp.swift:276-283. |
| `loadEnvironmentIfNeeded` | func | `Apps/Lillist-iOS/Sources/App/LillistApp.swift:114` | The single `.task`-driven entry point that calls `AppEnvironment.make()`, `bootstrap()`, and `defaultsInstaller.installIfNeeded()`, then assigns the result; also arms the UI-test reset seam via `--ui-test-reset-store`. LillistApp.swift:114-128. |
| `runBackgroundPurge` | func | `Apps/Lillist-iOS/Sources/App/LillistApp.swift:169` | Constructs a fresh `AppEnvironment` in the BGTask context (the `@State` env is unavailable there) and delegates to `env.runBackgroundPurge()`; required because BGTask closures are non-isolated. LillistApp.swift:169-172. |
| `startObservingAccountState` | func | `Apps/Lillist-iOS/Sources/App/AppEnvironment.swift:557` | Keeps `AppEnvironment.accountState` in sync with the actor-isolated `AccountStateMonitor.stateStream`; without it, SwiftUI views observing `accountState` never update after the initial bootstrap prime. AppEnvironment.swift:557-566. |
| `startObservingPauseReason` | func | `Apps/Lillist-iOS/Sources/App/AppEnvironment.swift:588` | Re-classifies and mirrors `pauseReason` on every account-state change; the sync-status badge and PauseExplainerDialog depend on this mirror being live after bootstrap. AppEnvironment.swift:588-600. |
| `startObservingSyncMode` | func | `Apps/Lillist-iOS/Sources/App/AppEnvironment.swift:572` | Bridges `SyncModeStore.modeStream` onto the observable `currentSyncMode`; the settings toggle and status-bar indicator react immediately to any mode change regardless of trigger path. AppEnvironment.swift:572-581. |
| `uiTestResetState` | func | `Apps/Lillist-iOS/Sources/App/LillistApp.swift:134` | Wipes the App Group container, UserDefaults, and on-disk store, then seeds LocalOnly mode and onboarding-complete; the entire `Lillist-iOSUITests` suite depends on this reset for a clean baseline. LillistApp.swift:134-165. |

## Relationships

- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Backup.BackupRestoreService (owns)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Backup.BackupSnapshotManager (owns)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Backup.LocalBackupCoordinator (owns)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Backup.TaskBackupStore (calls)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-CrashReporting.BreadcrumbBuffer (owns)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CanaryFile (calls)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReporter (owns)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-CrashReporting.OSLogFetcher (calls)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-CrashReporting.defaultURL (reads)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticHistoryObserver (owns)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Diagnostics.shared (reads)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Export.Importer (calls)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Notifications.NotificationPermissions (owns)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Notifications.NotificationScheduler (owns)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Notifications.NotificationSpecStore (owns)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Notifications.SnoozeRegistry (owns)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Notifications.SystemUserNotificationCenter (calls)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Notifications.current (reads)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Persistence.AutoPurgeJob (owns)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistentHistoryTokenStore (calls)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Persistence.QuarantineManager (calls)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Persistence.RemoteChangeReconciler (owns)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Persistence.localTaskRowCount (reads)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Reminders.EventKitRemindersGateway (owns)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Reminders.RemindersImporter (owns)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.AttachmentStore (owns)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.JournalStore (owns)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SeriesStore (owns)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.AccountStateMonitor (owns)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.CloudKitAccountStatusProvider (calls)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.ConstantNetworkReachability (calls)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.LiveCloudKitZoneEraser (calls)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.MigrationCoordinator (owns)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.PauseReasonClassifier (owns)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-2.SyncQuiesceMonitor (calls)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-2.SyncStatusMonitor (calls)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-misc.AppPreferencesPartitionMigrator (owns)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-misc.DefaultsInstaller (owns)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-misc.OnboardingState (owns)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistUI-Sources-LillistUI-Status.CloudKitSyncStatusAdapter (owns)`
- `Apps-Lillist-iOS-Sources-App.CrashReporterHost -> Packages-LillistCore-Sources-LillistCore-CrashReporting.detectAndPrepare (reads)`
- `Apps-Lillist-iOS-Sources-App.CrashReporterHost -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Apps-Lillist-iOS-Sources-App.CrashReporterHost -> Packages-LillistUI-Sources-LillistUI-CrashReporting.CrashReportSheet (calls)`
- `Apps-Lillist-iOS-Sources-App.CrashReporterHost -> Packages-LillistUI-Sources-LillistUI-CrashReporting.CrashReportViewModel (owns)`
- `Apps-Lillist-iOS-Sources-App.LillistApp -> Apps-Lillist-iOS-Sources-misc.RootShell (calls)`
- `Apps-Lillist-iOS-Sources-App.LillistApp -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.registerIfNeeded (calls)`
- `Apps-Lillist-iOS-Sources-App.LillistApp -> Packages-LillistUI-Sources-LillistUI-iOS-Tasks.TasksSort (reads)`
- `Apps-Lillist-iOS-Sources-App.body -> Apps-Lillist-iOS-Sources-misc.OnboardingScreen (calls)`
- `Apps-Lillist-iOS-Sources-App.body -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.restoreFromBackup (calls)`
- `Apps-Lillist-iOS-Sources-App.body -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.setMode (writes)`
- `Apps-Lillist-iOS-Sources-App.body -> Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationRecoverySheet (calls)`
- `Apps-Lillist-iOS-Sources-App.bootstrap -> Packages-LillistCore-Sources-LillistCore-Backup.bootstrapAtLaunch (calls)`
- `Apps-Lillist-iOS-Sources-App.bootstrap -> Packages-LillistCore-Sources-LillistCore-CrashReporting.detectAndPrepare (calls)`
- `Apps-Lillist-iOS-Sources-App.bootstrap -> Packages-LillistCore-Sources-LillistCore-Persistence.HistoryPruner (calls)`
- `Apps-Lillist-iOS-Sources-App.bootstrap -> Packages-LillistCore-Sources-LillistCore-Persistence.sweep (calls)`
- `Apps-Lillist-iOS-Sources-App.bootstrap -> Packages-LillistCore-Sources-LillistCore-Reminders.drainIfNeeded (calls)`
- `Apps-Lillist-iOS-Sources-App.bootstrap -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.normalizeSingletons (calls)`
- `Apps-Lillist-iOS-Sources-App.bootstrap -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.currentMode (reads)`
- `Apps-Lillist-iOS-Sources-App.bootstrap -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.currentReason (reads)`
- `Apps-Lillist-iOS-Sources-App.bootstrap -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.refresh (calls)`

## Type notes

- `AppEnvironment` is `@MainActor @Observable`; all stored properties are main-actor-isolated. `AppEnvironment.swift:17-19`.
- `private init` enforces factory-only construction; callers must use `make()` (production) or `inMemory()` (tests). `AppEnvironment.swift:112,361,391`.
- `MetricKitObserver` is a `let` constant on `AppEnvironment` because MetricKit holds subscribers weakly — the env is the sole strong owner. `AppEnvironment.swift:102`.
- `MailComposerTransport` is `@unchecked Sendable` with a private `DispatchQueue` for the pending-value slot; `onStage` is the only cross-actor delivery seam. `MailComposerTransport.swift:10,23`.
- `CrashReporterHost` uses `.sheet(item: $model)` bound to a non-nil `CrashReportViewModel` to structurally prevent an empty-modal failure mode. `CrashReporterHost.swift:13-14`.
- `MailComposerView.Coordinator.mailComposeController` uses `MainActor.assumeIsolated` because UIKit guarantees main-thread delivery but the SDK declares the delegate nonisolated. `MailComposerView.swift:54`.
- `AppEnvironment.appGroupID = "group.app.lillist"` is the shared App Group used by the main app, Share Extension, and Shortcuts extension. `AppEnvironment.swift:354`.

## External deps

- BackgroundTasks — imported
- CloudKit — imported
- Foundation — imported
- LillistCore — imported
- LillistUI — imported
- MessageUI — imported
- MetricKit — imported
- Observation — imported
- SwiftUI — imported
- UIKit — imported

## Gotchas

Canary must NOT be armed in `bootstrap()` — arming there races `CrashReporterHost.detectAndPrepare()` and produces a false crash sheet on every cold launch; the canary is written only on subsequent `didBecomeActive` events. `AppEnvironment.swift:450-456`. // The `willResignActive` observer uses a `DispatchGroup.wait(timeout: .now() + .seconds(2))` to block the observer thread briefly so `markCleanExit` lands before OS suspension; `willTerminate` is the wrong hook because iOS silently kills suspended apps without firing it. `AppEnvironment.swift:504-511,544-552`. // The `BGTaskScheduler.register` closure is not `@MainActor`; `AppEnvironment.make()` and `env.runBackgroundPurge()` are `@MainActor`-isolated, so an explicit `Task { @MainActor in … }` hop is required and `BGTask` itself must never cross actor boundaries. `LillistApp.swift:50-52`. // `--ui-test-bypass-gates` suppresses both the crash-report sheet (`CrashReporterHost.swift:36-38`) and the onboarding/recovery gates (`LillistApp.swift:250-253`).
