---
module: Apps/Lillist-iOS/Sources/App
summary: iOS app entry point, composition-root environment graph, and crash-report presentation host
read_when: iOS app launch + env graph
sources:
  - path: Apps/Lillist-iOS/Sources/App/AppEnvironment.swift
  - path: Apps/Lillist-iOS/Sources/App/CrashReporterHost.swift
  - path: Apps/Lillist-iOS/Sources/App/LillistApp.swift
  - path: Apps/Lillist-iOS/Sources/App/MailComposerTransport.swift
  - path: Apps/Lillist-iOS/Sources/App/MailComposerView.swift
  - path: Apps/Lillist-iOS/Sources/App/MetricKitObserver.swift
references_modules: [Apps-Lillist-iOS-Sources-misc, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Sync-chunk-1, Packages-LillistCore-Sources-LillistCore-CrashReporting, Packages-LillistUI-Sources-LillistUI-CrashReporting, Packages-LillistUI-Sources-LillistUI-Onboarding, Packages-LillistUI-Sources-LillistUI-Sync]
generator: cartographer/1
---

# Module: Apps/Lillist-iOS/Sources/App

## Purpose

The iOS app's composition root and launch path. `AppEnvironment` is the single
`@Observable` object graph that constructs every LillistCore store, the
notification/migration/crash machinery, and mirrors actor state onto MainActor
properties SwiftUI can observe. `LillistApp` (`@main`) wires the scene, loads the
environment asynchronously, and registers the background-purge task; the rest of
the app reads dependencies out of the injected `AppEnvironment` rather than from
singletons. If this module vanished, nothing downstream could be constructed.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `MailComposerTransport` | class | `Apps/Lillist-iOS/Sources/App/MailComposerTransport.swift:10` | `CrashReportTransport` impl; stages a `Pending` payload and signals `onStage` for the SwiftUI host to present |
| `MailComposerTransport.Pending` | struct | `Apps/Lillist-iOS/Sources/App/MailComposerTransport.swift:11` | Sendable, Identifiable staged crash-mail payload (subject/body/attachment) |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `AppEnvironment` | class | `Apps/Lillist-iOS/Sources/App/AppEnvironment.swift:19` | `@MainActor @Observable` root graph; owns all stores + crash/migration/notification machinery; highest fan-in in the app |
| `AppEnvironment.make()` | func | `Apps/Lillist-iOS/Sources/App/AppEnvironment.swift:277` | Async constructor: loads Core Data in the App Group container, resolves initial `SyncMode`, builds the graph |
| `AppEnvironment.inMemory()` | func | `Apps/Lillist-iOS/Sources/App/AppEnvironment.swift:307` | In-memory variant for tests/previews; isolated UserDefaults suite per instance |
| `AppEnvironment.bootstrap()` | func | `Apps/Lillist-iOS/Sources/App/AppEnvironment.swift:328` | One-shot launch work: prefs migration, history catch-up, scheduler bootstrap, purge, account/pause priming, observers |
| `AppEnvironment.appGroupID` | static let | `Apps/Lillist-iOS/Sources/App/AppEnvironment.swift:270` | `group.io.mikeydotio.Lillist`; shared by app, Share Extension, Shortcuts |
| `LillistApp` | struct | `Apps/Lillist-iOS/Sources/App/LillistApp.swift:7` | `@main` `App`; holds env in `@State`, wires scene + commands, registers `BGTask` |
| `CrashReporterHost` | struct | `Apps/Lillist-iOS/Sources/App/CrashReporterHost.swift:9` | Wraps root content; `.sheet(item:)`-binds crash report + mail/clipboard fallback |
| `OnboardingPresentationModifier` | struct | `Apps/Lillist-iOS/Sources/App/LillistApp.swift:195` | One-time launch evaluation: onboarding, iCloud-unavailable, or stale-migration recovery |
| `MetricKitObserver` | class | `Apps/Lillist-iOS/Sources/App/MetricKitObserver.swift:14` | Retained `MXMetricManagerSubscriber`; logs payload summaries to `LillistLog.metrics` |
| `MailComposerView` | struct | `Apps/Lillist-iOS/Sources/App/MailComposerView.swift:5` | `UIViewControllerRepresentable` over `MFMailComposeViewController` |

## Relationships

- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TaskStore (owns)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.MigrationCoordinator (owns)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.AccountStateMonitor (reads)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReporter (owns)`
- `Apps-Lillist-iOS-Sources-App.MailComposerTransport -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReportTransport (conforms-to)`
- `Apps-Lillist-iOS-Sources-App.MailComposerTransport -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReport (reads)`
- `Apps-Lillist-iOS-Sources-App.LillistApp -> Apps-Lillist-iOS-Sources-misc.RootShell (calls)`
- `Apps-Lillist-iOS-Sources-App.LillistApp -> Apps-Lillist-iOS-Sources-misc.LillistCommands (calls)`
- `Apps-Lillist-iOS-Sources-App.CrashReporterHost -> Packages-LillistUI-Sources-LillistUI-CrashReporting.CrashReportSheet (calls)`
- `Apps-Lillist-iOS-Sources-App.CrashReporterHost -> Packages-LillistUI-Sources-LillistUI-CrashReporting.CrashReportViewModel (calls)`
- `Apps-Lillist-iOS-Sources-App.CrashReporterHost -> Apps-Lillist-iOS-Sources-App.MailComposerView (calls)`
- `Apps-Lillist-iOS-Sources-App.OnboardingPresentationModifier -> Apps-Lillist-iOS-Sources-misc.OnboardingScreen (calls)`
- `Apps-Lillist-iOS-Sources-App.OnboardingPresentationModifier -> Packages-LillistUI-Sources-LillistUI-Onboarding.ICloudUnavailableScreen (calls)`
- `Apps-Lillist-iOS-Sources-App.OnboardingPresentationModifier -> Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationRecoverySheet (calls)`
- `Apps-Lillist-iOS-Sources-App.MigrationJournal -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.MigrationJournal (extends)`

## Type notes

`AppEnvironment` is `@MainActor @Observable` and constructed via `async throws`
because `PersistenceController.init` loads the Core Data store and can fail
(`Apps/Lillist-iOS/Sources/App/AppEnvironment.swift:277`). It owns strong
references to every store and to `MetricKitObserver` because MetricKit retains
subscribers weakly (`Apps/Lillist-iOS/Sources/App/AppEnvironment.swift:79`).
Actor-held state (sync mode, account state, pause reason) is mirrored into
plain observable properties via `AsyncStream` bridges started in `bootstrap()`
(`Apps/Lillist-iOS/Sources/App/AppEnvironment.swift:439`, `:454`, `:470`).
The canary is NOT armed in `bootstrap()`; foreground/background lifecycle
observers own write/clear, while `CrashReporterHost` owns
detect-and-prompt — splitting the two avoids a false stale-crash on every
launch (`Apps/Lillist-iOS/Sources/App/AppEnvironment.swift:408`).
`MailComposerTransport` is `@unchecked Sendable`, serializing its `pending`
field through a private queue (`Apps/Lillist-iOS/Sources/App/MailComposerTransport.swift:19`).
`CrashReporterHost` uses `.sheet(item:)` so the sheet cannot present without a
non-nil model, structurally ruling out the empty-modal failure
(`Apps/Lillist-iOS/Sources/App/CrashReporterHost.swift:11`).

## External deps

- SwiftUI — `App`/`Scene`/`View` lifecycle, `@State`, `@AppStorage`, sheets
- UIKit — `UIApplication` lifecycle notifications, `UIDevice`, `UIPasteboard`
- CloudKit — `CKContainer` for the account-status provider
- BackgroundTasks — `BGTaskScheduler` registration + `BGProcessingTaskRequest`
- MetricKit — `MXMetricManager` subscription for crash/hang/launch summaries
- MessageUI — `MFMailComposeViewController` (gated by `canImport`/`canSendMail`)
- Observation — `@Observable` macro for the environment graph

## Gotchas

- `BGTaskScheduler.register` must run during app `init`; the launch closure is non-isolated, so MainActor work hops via `Task { @MainActor }` and only a `Bool` crosses (`Apps/Lillist-iOS/Sources/App/LillistApp.swift:44`).
- `--ui-test-bypass-gates` short-circuits both crash-prompt and onboarding evaluation (`Apps/Lillist-iOS/Sources/App/CrashReporterHost.swift:36`, `Apps/Lillist-iOS/Sources/App/LillistApp.swift:251`).
- Recovery is offered only for a stale (crashed) migration journal; a fresh in-flight journal is left alone to avoid racing another process (`Apps/Lillist-iOS/Sources/App/LillistApp.swift:261`).
