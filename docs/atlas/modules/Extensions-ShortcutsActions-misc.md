---
module: "Extensions/ShortcutsActions (misc)"
summary: "App Intents extension: Siri/Shortcuts actions for task CRUD and quick-capture, backed by CLIBridge handlers"
read_when: "Touching App Intents or Shortcuts actions"
sources:
  - path: Extensions/ShortcutsActions/AddNoteIntent.swift
    blob: 5479c7b84089fb60435ccc3a69d7134c0a4003bb
  - path: Extensions/ShortcutsActions/AddNudgeIntent.swift
    blob: 9ef7abfdcea19ec80bead733408d60b241ae7661
  - path: Extensions/ShortcutsActions/AddTaskInput.swift
    blob: 0d52b0582d7d97cf5c26cdafe6778e6a25a2e8bc
  - path: Extensions/ShortcutsActions/AddTaskIntent.swift
    blob: 7905c08bc3612c2ba21d96712762297332c0781c
  - path: Extensions/ShortcutsActions/CompleteTaskIntent.swift
    blob: ee52ad97a2814037665355e4d61f48fefb0aebc2
  - path: Extensions/ShortcutsActions/Info.plist
    blob: 147d6215620e1469f86611a6ddcc14eca4a7a636
  - path: Extensions/ShortcutsActions/IntentSupport.swift
    blob: abb0b458501381ae340fec145f43f129ccab937a
  - path: Extensions/ShortcutsActions/Lillist.entitlements
    blob: c8ba24245a40abbf2f019ee0f30fad76a2e22056
  - path: Extensions/ShortcutsActions/LillistShortcuts.swift
    blob: 8fad2dc5e16fe94dbb34883fd958cbe02bbb7609
  - path: Extensions/ShortcutsActions/OpenTaskIntent.swift
    blob: a5525ff6de1796d9f8185c10e60ad343507e4c2f
  - path: Extensions/ShortcutsActions/PrivacyInfo.xcprivacy
    blob: 4e7e051bbe5e2753a0a80b85ae78289d250bdce7
  - path: Extensions/ShortcutsActions/QuickCaptureLockScreenIntent.swift
    blob: ccce46c0dd12ae976c269fb6eafda96b6d8fdc09
  - path: Extensions/ShortcutsActions/ReportCrashIntent.swift
    blob: b5cadb7d4c02e2e41c94ab25e6bd9d8517e006a7
  - path: Extensions/ShortcutsActions/SearchTasksIntent.swift
    blob: 33326bf5c2bdcae30181985681d13a70a9a69999
  - path: Extensions/ShortcutsActions/ToggleStatusIntent.swift
    blob: 6087eb324c84eccdf453f561995740af6c718cc4
references_modules: [Packages-LillistCore-Sources-LillistCore-CrashReporting, Packages-LillistCore-Sources-LillistCore-Diagnostics, Packages-LillistCore-Sources-LillistCore-Notifications, Packages-LillistCore-Sources-LillistCore-Persistence, Packages-LillistCore-Sources-LillistCore-Sync-chunk-1, Packages-LillistCore-Sources-LillistCore-misc, Packages-LillistUI-Sources-LillistUI-Accessibility, Packages-LillistUI-Sources-LillistUI-Recurrence]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Extensions/ShortcutsActions (misc)

## Purpose

This target is Lillist's App Intents extension — the bridge between the system's Shortcuts/Siri layer and LillistCore's data layer. It exposes intent structs for creating, completing, searching, and status-toggling tasks, adding journal notes and nudge notifications, triggering quick-capture handoff, and surfacing pending crash reports. The unifying idea is thin delegation: every `perform()` body resolves the shared persistence stack via `IntentSupport.makePersistence()` then routes through the same `CLIBridge` handlers the CLI uses, so the Shortcuts surface adds no business logic of its own. Remove this target and Lillist loses all Siri, Shortcuts, and Lock Screen widget integration.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AddNoteIntent` | struct | `Extensions/ShortcutsActions/AddNoteIntent.swift:4` | AppIntent that appends a journal note to a named task; requires `TaskEntity` and `body` string parameters; delegates to `CLIBridge.NoteHandler`. |
| `AddNudgeIntent` | struct | `Extensions/ShortcutsActions/AddNudgeIntent.swift:5` | AppIntent that schedules a one-off nudge notification on a task at a concrete `Date`; bypasses the CLI DSL parser by calling `NotificationSpecStore.add()` directly. |
| `AddTaskInput` | enum | `Extensions/ShortcutsActions/AddTaskInput.swift:6` | Namespace for title normalization helpers; extracted from `AddTaskIntent` for unit-testability without an AppIntents test host. |
| `AddTaskIntent` | struct | `Extensions/ShortcutsActions/AddTaskIntent.swift:5` | AppIntent that creates a task with title, optional deadline, tags, and notes; prompts via Siri if the title is blank; returns a `TaskEntity` with a confirmation dialog. |
| `CompleteTaskIntent` | struct | `Extensions/ShortcutsActions/CompleteTaskIntent.swift:4` | AppIntent that marks a named task `closed`; requires a `TaskEntity` parameter; delegates status change to `CLIBridge.StatusHandler`. |
| `IntentSupport` | enum | `Extensions/ShortcutsActions/IntentSupport.swift:6` | Namespace enum providing `makePersistence()`, `diagnosticLog()`, and the internal `Cache` actor; the sole shared bootstrap shim for all App Intent `perform()` bodies. |
| `LillistShortcuts` | struct | `Extensions/ShortcutsActions/LillistShortcuts.swift:5` | `AppShortcutsProvider` manifest wiring `AddTaskIntent`, `SearchTasksIntent`, and `QuickCaptureLockScreenIntent` to Siri trigger phrases for system registration. |
| `OpenTaskIntent` | struct | `Extensions/ShortcutsActions/OpenTaskIntent.swift:8` | AppIntent that brings Lillist to the foreground with a chosen task selected; no in-app deep-link navigation is performed yet (placeholder for future task-scroll surface). |
| `QuickCaptureLockScreenIntent` | struct | `Extensions/ShortcutsActions/QuickCaptureLockScreenIntent.swift:9` | AppIntent for Lock Screen and Shortcuts that stashes optional pre-fill text via `QuickCaptureHandoff`, then opens the app; the app drains the handoff on activation. |
| `ReportCrashIntent` | struct | `Extensions/ShortcutsActions/ReportCrashIntent.swift:11` | AppIntent that detects a pending crash canary and opens Lillist; actual report UI (sheet + mail composer) is deferred to the host app's `CrashReporterHost`. |
| `ReportCrashIntentResolver` | enum | `Extensions/ShortcutsActions/ReportCrashIntent.swift:29` | Pure-Swift helper extracted from `ReportCrashIntent.perform()` for unit-testability without AppIntents infra; reads a canary URL and returns a user-facing status string. |
| `SearchTasksIntent` | struct | `Extensions/ShortcutsActions/SearchTasksIntent.swift:4` | AppIntent that searches tasks by title or notes substring via `CLIBridge.SearchHandler` and returns a `[TaskEntity]` array to Shortcuts. |
| `ToggleStatusIntent` | struct | `Extensions/ShortcutsActions/ToggleStatusIntent.swift:4` | AppIntent that sets a task's status to any `StatusAppEnum` value via `CLIBridge.StatusHandler`; accepts both task and status as parameters. |
| `controller` | func | `Extensions/ShortcutsActions/IntentSupport.swift:27` | Returns a cached `PersistenceController` for the given `StoreConfiguration`, coalescing concurrent cold builds via `inFlight` Task to prevent duplicate CloudKit containers. |
| `diagnosticLog` | func | `Extensions/ShortcutsActions/IntentSupport.swift:89` | Returns a `DiagnosticLog` scoped to `.appIntents`, honoring the shared device toggle; reads `DevicePreferencesStore.diagnosticLoggingEnabled()` on every call. |
| `makePersistence` | func | `Extensions/ShortcutsActions/IntentSupport.swift:75` | Resolves the App-Group persistence stack via `GatedPersistenceResolver`; throws `LillistError.storeUnavailable` if App Group is absent or a sync-mode migration is in flight. |
| `normalizedTitle` | func | `Extensions/ShortcutsActions/AddTaskInput.swift:9` | Trims whitespace from `raw`; returns `nil` when blank or nil, signaling the intent to re-request the value from the user via Siri. |
| `perform` | func | `Extensions/ShortcutsActions/AddNoteIntent.swift:18` | Resolves persistence via `IntentSupport.makePersistence()`, calls `CLIBridge.NoteHandler.run`, returns `.result()`; throws on store or note errors. |
| `perform` | func | `Extensions/ShortcutsActions/AddNudgeIntent.swift:17` | Constructs `NotificationSpecStore` from the resolved persistence stack and calls `.add(taskID:kind:.nudge:offsetMinutes:nil:fireDate:)`; throws if store is unavailable. |
| `perform` | func | `Extensions/ShortcutsActions/AddTaskIntent.swift:29` | Guards blank title with `needsValueError`; creates via `CLIBridge.AddHandler`, applies deadline via `TaskStore.update`, fetches and returns entity + dialog; throws on store errors. |
| `perform` | func | `Extensions/ShortcutsActions/CompleteTaskIntent.swift:15` | Calls `CLIBridge.StatusHandler.run(token:to:.closed:note:nil:persistence:)`; returns `.result()` on success; throws on store errors. |
| `perform` | func | `Extensions/ShortcutsActions/OpenTaskIntent.swift:20` | Returns `.result()` immediately; foreground transition is provided entirely by `openAppWhenRun = true`; no persistence calls. |
| `perform` | func | `Extensions/ShortcutsActions/QuickCaptureLockScreenIntent.swift:23` | Calls `QuickCaptureHandoff.stash(text ?? "", appGroupID:)` to write pre-fill text to App Group storage; returns `.result()`; side-effect only. |
| `perform` | func | `Extensions/ShortcutsActions/ReportCrashIntent.swift:20` | Reads `CanaryFile.defaultURL(for: .iOSApp)` and delegates to `ReportCrashIntentResolver.resolve`; returns a status string; `openAppWhenRun = true` brings Lillist to foreground. |
| `perform` | func | `Extensions/ShortcutsActions/SearchTasksIntent.swift:15` | Calls `CLIBridge.SearchHandler.run(query:scopeToken:nil:persistence:)` and maps each result record to a `TaskEntity`; throws on store errors. |
| `perform` | func | `Extensions/ShortcutsActions/ToggleStatusIntent.swift:16` | Calls `CLIBridge.StatusHandler.run(token:to:status.coreStatus:note:nil:persistence:)`; returns `.result()` on success; throws on store errors. |
| `resolve` | func | `Extensions/ShortcutsActions/ReportCrashIntent.swift:30` | Constructs `CanaryFile(url:)` and calls `readIfPresent()`; returns "No pending crash" when nil, otherwise "Open Lillist to complete the crash report." |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

- `Extensions-ShortcutsActions-misc.AddTaskIntent -> Packages-LillistUI-Sources-LillistUI-Accessibility.value (calls)`
- `Extensions-ShortcutsActions-misc.controller -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceController (owns)`
- `Extensions-ShortcutsActions-misc.diagnosticLog -> Packages-LillistCore-Sources-LillistCore-Diagnostics.shared (reads)`
- `Extensions-ShortcutsActions-misc.diagnosticLog -> Packages-LillistCore-Sources-LillistCore-misc.DevicePreferencesStore (reads)`
- `Extensions-ShortcutsActions-misc.diagnosticLog -> Packages-LillistCore-Sources-LillistCore-misc.diagnosticLoggingEnabled (reads)`
- `Extensions-ShortcutsActions-misc.makePersistence -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.GatedPersistenceResolver (calls)`
- `Extensions-ShortcutsActions-misc.perform -> Packages-LillistCore-Sources-LillistCore-CrashReporting.defaultURL (reads)`
- `Extensions-ShortcutsActions-misc.perform -> Packages-LillistCore-Sources-LillistCore-Notifications.NotificationSpecStore (writes)`
- `Extensions-ShortcutsActions-misc.perform -> Packages-LillistCore-Sources-LillistCore-misc.stash (writes)`
- `Extensions-ShortcutsActions-misc.perform -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Extensions-ShortcutsActions-misc.resolve -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CanaryFile (calls)`
- `Extensions-ShortcutsActions-misc.resolve -> Packages-LillistCore-Sources-LillistCore-CrashReporting.readIfPresent (reads)`

## Type notes

`IntentSupport` is a namespace `enum` (never instantiated) that provides two public factory functions and houses the internal `Cache` actor; it is the single shared bootstrap shim all intent `perform()` bodies call (IntentSupport.swift:6). `Cache` is a `private actor` with a `static let shared` singleton keyed on `SyncMode`; it coalesces concurrent cold builds via an `inFlight` Task to prevent duplicate `NSPersistentCloudKitContainer` instances in the same extension process (IntentSupport.swift:19-61). All `perform()` methods carry `@MainActor` isolation — required by AppIntents even though actual work is async; this is enforced across every intent file (e.g. AddNoteIntent.swift:17, AddTaskIntent.swift:28). `AddTaskInput` and `ReportCrashIntentResolver` are pure-Swift value-type helpers extracted from their parent intents solely for unit-testability without an AppIntents test host (AddTaskInput.swift:3-5, ReportCrashIntent.swift:26-28). `IntentSupport.appGroupID` (`"group.app.lillist"`) is the single App Group constant shared by all intents; it is declared once and referenced everywhere (IntentSupport.swift:7).

## External deps

- AppIntents — imported
- Foundation — imported
- LillistCore — imported

## Gotchas

AppIntents prohibits free-text `String` parameters inline in spoken phrases — spoken task titles must be collected via `requestValueDialog`, not embedded in the phrase (LillistShortcuts.swift:12-16). `Cache` actor uses an `inFlight` Task to coalesce concurrent cold builds: without it, two callers entering while the container is still loading would both stand up a CloudKit mirroring subscription (IntentSupport.swift:38-43). `AddNudgeIntent.perform()` bypasses `NudgeHandler`'s DSL parser and calls `NotificationSpecStore.add()` directly because the intent receives a concrete `Date`, not a DSL token (AddNudgeIntent.swift:19-21).
