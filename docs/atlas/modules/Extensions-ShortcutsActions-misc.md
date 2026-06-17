---
module: "Extensions/ShortcutsActions (misc)"
summary: "App Intents extension exposing Lillist actions to Shortcuts, Siri, and Lock Screen widgets"
read_when: "Touching App Intents, Shortcuts actions, or the extension's persistence/diagnostic wiring"
sources:
  - path: Extensions/ShortcutsActions/AddNoteIntent.swift
    blob: 5479c7b84089fb60435ccc3a69d7134c0a4003bb
  - path: Extensions/ShortcutsActions/AddNudgeIntent.swift
    blob: 9ef7abfdcea19ec80bead733408d60b241ae7661
  - path: Extensions/ShortcutsActions/AddTaskIntent.swift
    blob: a282eecc4ca5781082558d429106ef4b965e4ec6
  - path: Extensions/ShortcutsActions/CompleteTaskIntent.swift
    blob: ee52ad97a2814037665355e4d61f48fefb0aebc2
  - path: Extensions/ShortcutsActions/Info.plist
    blob: bb54fe71bb383ecfa907d8e1e62c0b2bd15fe749
  - path: Extensions/ShortcutsActions/IntentSupport.swift
    blob: 0d89cca032cb960afe49d9e56244d5a1f43e7dca
  - path: Extensions/ShortcutsActions/Lillist.entitlements
    blob: dc82d6a78df2d35115ff154e8888e3d7e0ef3469
  - path: Extensions/ShortcutsActions/LillistShortcuts.swift
    blob: 2b8bf798b2b60e4b69191a5eabd0283f4325a529
  - path: Extensions/ShortcutsActions/OpenTaskIntent.swift
    blob: a5525ff6de1796d9f8185c10e60ad343507e4c2f
  - path: Extensions/ShortcutsActions/PrivacyInfo.xcprivacy
    blob: 4e7e051bbe5e2753a0a80b85ae78289d250bdce7
  - path: Extensions/ShortcutsActions/QuickCaptureLockScreenIntent.swift
    blob: ff2cfee19b0ce40fd1261905003b826cff34f3b4
  - path: Extensions/ShortcutsActions/ReportCrashIntent.swift
    blob: b5cadb7d4c02e2e41c94ab25e6bd9d8517e006a7
  - path: Extensions/ShortcutsActions/SearchTasksIntent.swift
    blob: 33326bf5c2bdcae30181985681d13a70a9a69999
  - path: Extensions/ShortcutsActions/ToggleStatusIntent.swift
    blob: 6087eb324c84eccdf453f561995740af6c718cc4
references_modules: [Extensions-ShortcutsActions-Entities, Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1, Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistCore-Sources-LillistCore-Notifications, Packages-LillistCore-Sources-LillistCore-Persistence, Packages-LillistCore-Sources-LillistCore-Diagnostics, Packages-LillistCore-Sources-LillistCore-CrashReporting, Packages-LillistCore-Sources-LillistCore-misc]
generator: cartographer/1
baseline: 34dfea7772679dbabc08fabd6fbba53f6ad5856b
---

# Module: Extensions/ShortcutsActions (misc)

## Purpose

The App Intents extension target (`com.apple.appintents-extension`) that publishes
Lillist's task actions to Shortcuts, Siri, and Lock Screen widgets. Each intent is a
thin adapter: it resolves a shared App-Group persistence stack, then delegates the
actual mutation to a LillistCore `CLIBridge` handler or store so the extension never
reimplements business logic. `IntentSupport` is the load-bearing seam — it owns the
per-process `PersistenceController` cache and the migration-gated resolve so intents
don't race a foreground sync-mode swap.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AddNoteIntent` | struct | `Extensions/ShortcutsActions/AddNoteIntent.swift:4` | AppIntent; adds a journal entry to a task via `CLIBridge.NoteHandler` |
| `AddNudgeIntent` | struct | `Extensions/ShortcutsActions/AddNudgeIntent.swift:5` | AppIntent; schedules a one-off nudge notification via `NotificationSpecStore` |
| `AddTaskIntent` | struct | `Extensions/ShortcutsActions/AddTaskIntent.swift:5` | AppIntent; creates a task via `CLIBridge.AddHandler`; applies deadline via `TaskStore.update`; returns `TaskEntity` |
| `CompleteTaskIntent` | struct | `Extensions/ShortcutsActions/CompleteTaskIntent.swift:4` | AppIntent; sets task status to `.closed` via `CLIBridge.StatusHandler` |
| `IntentSupport` | enum | `Extensions/ShortcutsActions/IntentSupport.swift:6` | Shared seam every mutating intent funnels through for persistence and diagnostics |
| `LillistShortcuts` | struct | `Extensions/ShortcutsActions/LillistShortcuts.swift:5` | `AppShortcutsProvider`; registers Siri phrases for Add Task, Search Tasks, Quick Capture |
| `OpenTaskIntent` | struct | `Extensions/ShortcutsActions/OpenTaskIntent.swift:8` | AppIntent; opens Lillist foreground only; task parameter reserved for future deep-link |
| `QuickCaptureLockScreenIntent` | struct | `Extensions/ShortcutsActions/QuickCaptureLockScreenIntent.swift:7` | AppIntent; Lock Screen entry point; opens app foreground; no in-extension capture |
| `ReportCrashIntent` | struct | `Extensions/ShortcutsActions/ReportCrashIntent.swift:11` | Public AppIntent; checks canary file for a pending crash; opens app so `CrashReporterHost` can present the sheet; returns status string |
| `ReportCrashIntentResolver` | enum | `Extensions/ShortcutsActions/ReportCrashIntent.swift:29` | Pure helper; `resolve(canaryURL:)` maps canary presence to a user-facing message; extracted for unit-testability |
| `SearchTasksIntent` | struct | `Extensions/ShortcutsActions/SearchTasksIntent.swift:4` | AppIntent; runs `CLIBridge.SearchHandler`; returns `[TaskEntity]` |
| `ToggleStatusIntent` | struct | `Extensions/ShortcutsActions/ToggleStatusIntent.swift:4` | AppIntent; sets arbitrary status via `CLIBridge.StatusHandler` with `StatusAppEnum` input |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `makePersistence` | func | `Extensions/ShortcutsActions/IntentSupport.swift:75` | Migration-gated App-Group stack resolve; throws `storeUnavailable` mid sync-mode swap so Shortcuts shows a retry message |
| `IntentSupport.Cache` | actor | `Extensions/ShortcutsActions/IntentSupport.swift:19` | Per-process `PersistenceController` cache keyed on `SyncMode`; coalesces concurrent cold builds via `inFlight` Task to prevent duplicate CloudKit subscriptions |
| `diagnosticLog` | func | `Extensions/ShortcutsActions/IntentSupport.swift:89` | Returns process-scoped `DiagnosticLog` for `.appIntents`, gated on the shared device toggle |

## Relationships

- `Extensions-ShortcutsActions-misc.IntentSupport -> Packages-LillistCore-Sources-LillistCore-Persistence.GatedPersistenceResolver (calls)` — `Extensions/ShortcutsActions/IntentSupport.swift:76`
- `Extensions-ShortcutsActions-misc.IntentSupport -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceController (owns)` — `Extensions/ShortcutsActions/IntentSupport.swift:46`
- `Extensions-ShortcutsActions-misc.IntentSupport -> Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticLog (calls)` — `Extensions/ShortcutsActions/IntentSupport.swift:90`
- `Extensions-ShortcutsActions-misc.IntentSupport -> Packages-LillistCore-Sources-LillistCore-misc.DevicePreferencesStore (reads)` — `Extensions/ShortcutsActions/IntentSupport.swift:93`
- `Extensions-ShortcutsActions-misc.AddTaskIntent -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.CLIBridge.AddHandler (calls)` — `Extensions/ShortcutsActions/AddTaskIntent.swift:26`
- `Extensions-ShortcutsActions-misc.CompleteTaskIntent -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.CLIBridge.StatusHandler (calls)` — `Extensions/ShortcutsActions/CompleteTaskIntent.swift:17`
- `Extensions-ShortcutsActions-misc.ToggleStatusIntent -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.CLIBridge.StatusHandler (calls)` — `Extensions/ShortcutsActions/ToggleStatusIntent.swift:18`
- `Extensions-ShortcutsActions-misc.AddNoteIntent -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.CLIBridge.NoteHandler (calls)` — `Extensions/ShortcutsActions/AddNoteIntent.swift:20`
- `Extensions-ShortcutsActions-misc.SearchTasksIntent -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.CLIBridge.SearchHandler (calls)` — `Extensions/ShortcutsActions/SearchTasksIntent.swift:17`
- `Extensions-ShortcutsActions-misc.AddTaskIntent -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (calls)` — `Extensions/ShortcutsActions/AddTaskIntent.swift:40`
- `Extensions-ShortcutsActions-misc.AddNudgeIntent -> Packages-LillistCore-Sources-LillistCore-Notifications.NotificationSpecStore (calls)` — `Extensions/ShortcutsActions/AddNudgeIntent.swift:23`
- `Extensions-ShortcutsActions-misc.ReportCrashIntent -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CanaryFile (reads)` — `Extensions/ShortcutsActions/ReportCrashIntent.swift:21`
- `Extensions-ShortcutsActions-misc.AddTaskIntent -> Extensions-ShortcutsActions-Entities.TaskEntity (owns)` — `Extensions/ShortcutsActions/AddTaskIntent.swift:47`
- `Extensions-ShortcutsActions-misc.ToggleStatusIntent -> Extensions-ShortcutsActions-Entities.StatusAppEnum (reads)` — `Extensions/ShortcutsActions/ToggleStatusIntent.swift:9`

## Type notes

`IntentSupport.Cache` is an actor caching one `PersistenceController` per process keyed on
`SyncMode` (`Extensions/ShortcutsActions/IntentSupport.swift:21`). Because building a
controller suspends across `loadPersistentStores`, an `inFlight` Task is registered
synchronously before the first await so concurrent cold callers join one build instead of
standing up duplicate CloudKit subscriptions (`Extensions/ShortcutsActions/IntentSupport.swift:25`).
Intent-authored writes are stamped with `PersistenceController.appIntentsTransactionAuthor`
so the host app's history observer attributes them correctly (`Extensions/ShortcutsActions/IntentSupport.swift:46`).
All `perform()` bodies are `@MainActor`. `OpenTaskIntent` and `QuickCaptureLockScreenIntent`
are open-app-only stubs — they bring Lillist to the foreground and do no data work
(`Extensions/ShortcutsActions/OpenTaskIntent.swift:20`, `Extensions/ShortcutsActions/QuickCaptureLockScreenIntent.swift:15`).

## External deps

- AppIntents — every intent conforms to `AppIntent`; `LillistShortcuts` is an `AppShortcutsProvider`
- App Group `group.io.mikeydotio.Lillist` — shared store path; CloudKit container declared in `Extensions/ShortcutsActions/Lillist.entitlements`

## Gotchas

- `AddNudgeIntent` bypasses `NudgeHandler`'s date-DSL parser and writes the concrete `Date` straight to `NotificationSpecStore` because the intent receives a real `Date`, not a DSL token (`Extensions/ShortcutsActions/AddNudgeIntent.swift:19`).
- `AddTaskIntent.perform()` applies `deadline` in a second `TaskStore.update` call after `CLIBridge.AddHandler` returns because `AddHandler`'s `deadlineToken` parameter is a DSL string (`Extensions/ShortcutsActions/AddTaskIntent.swift:39`).
- `makePersistence` consults `GatedPersistenceResolver` (and thus `MigrationGate`) on every call — not cached — so a sync-mode migration in flight always yields a clean retry error (`Extensions/ShortcutsActions/IntentSupport.swift:76`).
