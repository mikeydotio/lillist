---
module: "Extensions/ShortcutsActions (misc)"
summary: "App Intents extension exposing Lillist actions to Shortcuts, Siri, and Lock Screen widgets"
read_when: "App Intents / Shortcuts"
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
references_modules: [Extensions-ShortcutsActions-Entities, Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1, Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Notifications, Packages-LillistCore-Sources-LillistCore-Persistence, Packages-LillistCore-Sources-LillistCore-Sync-chunk-1, Packages-LillistCore-Sources-LillistCore-Diagnostics, Packages-LillistCore-Sources-LillistCore-CrashReporting, Packages-LillistCore-Sources-LillistCore-misc]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
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
| `ReportCrashIntent` | struct | `Extensions/ShortcutsActions/ReportCrashIntent.swift:11` | Public AppIntent; opens the app to finish a pending crash report, returns a status string |
| `ReportCrashIntentResolver` | enum | `Extensions/ShortcutsActions/ReportCrashIntent.swift:29` | Pure helper; `resolve(canaryURL:)` maps canary presence to a user-facing message, testable without an AppIntent |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `IntentSupport` | enum | `Extensions/ShortcutsActions/IntentSupport.swift:6` | Shared seam every mutating intent funnels through for persistence + diagnostics |
| `makePersistence` | func | `Extensions/ShortcutsActions/IntentSupport.swift:75` | Migration-gated resolve of the App-Group stack; throws `storeUnavailable` mid-swap |
| `IntentSupport.Cache` | actor | `Extensions/ShortcutsActions/IntentSupport.swift:19` | Per-process controller cache keyed on `SyncMode`; coalesces concurrent cold builds |
| `diagnosticLog` | func | `Extensions/ShortcutsActions/IntentSupport.swift:89` | Process-scoped `DiagnosticLog` for `.appIntents`, gated on the device toggle |
| `LillistShortcuts` | struct | `Extensions/ShortcutsActions/LillistShortcuts.swift:5` | `AppShortcutsProvider` registering Siri phrases for Add/Search/Quick Capture |
| `AddTaskIntent` | struct | `Extensions/ShortcutsActions/AddTaskIntent.swift:5` | Representative mutating intent; creates a task then patches deadline, returns `TaskEntity` |
| `ToggleStatusIntent` | struct | `Extensions/ShortcutsActions/ToggleStatusIntent.swift:4` | Sets task status via `StatusAppEnum.coreStatus` through `StatusHandler` |

## Relationships

- `Extensions-ShortcutsActions-misc.AddTaskIntent -> Extensions-ShortcutsActions-misc.IntentSupport (calls)`
- `Extensions-ShortcutsActions-misc.IntentSupport -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.GatedPersistenceResolver (calls)`
- `Extensions-ShortcutsActions-misc.IntentSupport -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceController (owns)`
- `Extensions-ShortcutsActions-misc.IntentSupport -> Packages-LillistCore-Sources-LillistCore-Persistence.StoreConfiguration (reads)`
- `Extensions-ShortcutsActions-misc.IntentSupport -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.SyncMode (reads)`
- `Extensions-ShortcutsActions-misc.IntentSupport -> Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticLog (calls)`
- `Extensions-ShortcutsActions-misc.IntentSupport -> Packages-LillistCore-Sources-LillistCore-misc.DevicePreferencesStore (reads)`
- `Extensions-ShortcutsActions-misc.AddTaskIntent -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.AddHandler (calls)`
- `Extensions-ShortcutsActions-misc.AddTaskIntent -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TaskStore (calls)`
- `Extensions-ShortcutsActions-misc.AddNoteIntent -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.NoteHandler (calls)`
- `Extensions-ShortcutsActions-misc.CompleteTaskIntent -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.StatusHandler (calls)`
- `Extensions-ShortcutsActions-misc.ToggleStatusIntent -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.StatusHandler (calls)`
- `Extensions-ShortcutsActions-misc.SearchTasksIntent -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.SearchHandler (calls)`
- `Extensions-ShortcutsActions-misc.AddNudgeIntent -> Packages-LillistCore-Sources-LillistCore-Notifications.NotificationSpecStore (calls)`
- `Extensions-ShortcutsActions-misc.ReportCrashIntentResolver -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CanaryFile (reads)`
- `Extensions-ShortcutsActions-misc.AddTaskIntent -> Extensions-ShortcutsActions-Entities.TaskEntity (owns)`
- `Extensions-ShortcutsActions-misc.ToggleStatusIntent -> Extensions-ShortcutsActions-Entities.StatusAppEnum (reads)`

## Type notes

`IntentSupport.Cache` is an actor caching one `PersistenceController` per process keyed on
`SyncMode` (`Extensions/ShortcutsActions/IntentSupport.swift:21`). Because building a
controller suspends across `loadPersistentStores`, an `inFlight` Task is registered
synchronously before the first await so concurrent cold callers join one build instead of
standing up duplicate CloudKit subscriptions (`Extensions/ShortcutsActions/IntentSupport.swift:25`).
Intent-authored writes are stamped with `PersistenceController.appIntentsTransactionAuthor`
so the host app's history observer attributes them. All `perform()` bodies are `@MainActor`.
`OpenTaskIntent` and `QuickCaptureLockScreenIntent` are open-app-only stubs — they bring
Lillist to the foreground and do no work (`Extensions/ShortcutsActions/OpenTaskIntent.swift:20`).

## External deps

- AppIntents — every intent conforms to `AppIntent`; `LillistShortcuts` is an `AppShortcutsProvider`
- App Group `group.io.mikeydotio.Lillist` — shared store path; CloudKit container in `Extensions/ShortcutsActions/Lillist.entitlements`

## Gotchas

- `AddNudgeIntent` bypasses `NudgeHandler`'s date-DSL parser and writes the concrete `Date` straight to `NotificationSpecStore` (`Extensions/ShortcutsActions/AddNudgeIntent.swift:19`).
- `makePersistence` consults `MigrationGate` on every call and throws `LillistError.storeUnavailable` mid sync-mode swap so Shortcuts surfaces a retry message (`Extensions/ShortcutsActions/IntentSupport.swift:76`).
