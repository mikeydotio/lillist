---
module: "Packages/LillistCore/Sources/LillistCore/Sync (chunk 1)"
summary: "Sync-mode migration engine, gate guard, journal, CloudKit event bridge, and iCloud account/status primitives"
read_when: "Touching sync-mode changes"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift
    blob: 43ede62cf0943fa3e0a4003c0743463c9a98d778
  - path: Packages/LillistCore/Sources/LillistCore/Sync/CloudKitErrorClassifier.swift
    blob: d0c27352b128e8c7a0c0e3a340a0efe0d6eaa0a1
  - path: Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift
    blob: 51f39616ad7eb6960aaa54fc1ae71388b7b089ba
  - path: Packages/LillistCore/Sources/LillistCore/Sync/CloudKitZoneEraser.swift
    blob: ad119cf1626b1790cfe98a52a42155c6fb08ef9d
  - path: Packages/LillistCore/Sources/LillistCore/Sync/CloudKitZoneEraserImpl.swift
    blob: bbf1a0495a5e246ba2c26723d035b4647abe2fb6
  - path: Packages/LillistCore/Sources/LillistCore/Sync/GatedPersistenceResolver.swift
    blob: dd439297585e852a76724ec77944b8b3c9467faa
  - path: Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift
    blob: 8f41de1325769ca05f8f9eed3915f96399084c6d
  - path: Packages/LillistCore/Sources/LillistCore/Sync/MigrationGate.swift
    blob: fd1c5076844276dea05bc94f398c46feb2366c81
  - path: Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournal.swift
    blob: 33c6d7934e71807ed5cc9ae81d38e338c1171d82
  - path: Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournalStore.swift
    blob: 7573e9327e0629237b53d89e1bb746965d2c2e37
  - path: Packages/LillistCore/Sources/LillistCore/Sync/PauseReason.swift
    blob: 5f5f1025b26851f66bcd2cc10181047dbf6eb2e6
  - path: Packages/LillistCore/Sources/LillistCore/Sync/PauseReasonClassifier.swift
    blob: 8b6d341bd0b2774e8d55e4f3056606a0cbf75f48
  - path: Packages/LillistCore/Sources/LillistCore/Sync/SyncMode.swift
    blob: 166a5b012d34db879015f01f7634e7c80c4d969f
  - path: Packages/LillistCore/Sources/LillistCore/Sync/SyncModeStore.swift
    blob: e091111832b444bedd2bd2d0272c0bebbaca9a40
  - path: Packages/LillistCore/Sources/LillistCore/Sync/SyncQuiesceMonitor.swift
    blob: ad9399267df89701c33893a29e31d3be9950bcce
references_modules: [Packages-LillistCore-Sources-LillistCore-Persistence, Packages-LillistCore-Sources-LillistCore-Notifications, Packages-LillistCore-Sources-LillistCore-Sync-chunk-2, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-CrashReporting, Packages-LillistCore-Sources-LillistCore-misc, Extensions-ShortcutsActions-misc, Extensions-ShareExtension-iOS, Packages-LillistCore-Sources-LillistCore-CLIBridge-misc, Apps-Lillist-iOS-Sources-App]
generator: cartographer/1
baseline: 1a1562b636e43ebbdc35c7939ab6989b387f50e9
verified: true
---

# Module: Packages/LillistCore/Sources/LillistCore/Sync (chunk 1)

## Purpose

This chunk owns the sync-mode migration state machine and the gate primitives that protect every headless store opener. `MigrationCoordinator` sequences the eight-phase LocalOnly↔iCloudSync swap, writing a crash-survivable `MigrationJournal` at every step and emitting `MigrationPhase` events for the progress sheet. `MigrationGate` + `GatedPersistenceResolver` let the Share Extension, App Intents, and CLI consult the journal before opening the store, aborting with a user-facing message when a migration is in flight. The supporting cast — `AccountStateMonitor`, `CloudKitEventBridge`, `SyncModeStore`, `SyncQuiesceMonitor`, `PauseReasonClassifier`, `CloudKitErrorClassifier` — forms the observability seam between Core Data's opaque CloudKit events and the typed status surface consumed by chunk-2 and the UI.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AccountStateMonitor` | actor | `Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift:23` | Publishes `iCloudAccountState` via replay-capable `AsyncStream`; wraps injected `AccountStatusProviding` |
| `AccountStateProviding` | typealias | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift:36` | `@Sendable` async probe injected so the coordinator avoids a direct CloudKit dep |
| `AccountStatusProviding` | protocol | `Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift:5` | Testable seam around `CKContainer.accountStatus()` |
| `CloudKitAccountStatusProvider` | struct | `Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift:10` | Production `AccountStatusProviding` over a real `CKContainer` |
| `CloudKitEraseSummary` | struct | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitZoneEraser.swift:6` | Value returned by `eraseManagedZones`; lists deleted zone IDs |
| `CloudKitErrorClassifier` | enum | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitErrorClassifier.swift:18` | Maps raw `CKError` codes to `LillistError`; collapses unmapped codes to `.syncFailure` |
| `CloudKitEventBridge` | actor | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift:35` | Bridges `eventChangedNotification` to a testable `AsyncStream<CloudKitSyncEvent>`; test seam via `recordEvent(_:)` |
| `CloudKitSyncEvent` | struct | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift:9` | Lillist-internal mirror of `NSPersistentCloudKitContainer.Event`; constructible in tests |
| `CloudKitZoneEraser` | protocol | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitZoneEraser.swift:24` | `eraseManagedZones(in:progress:)` wipes Core Data mirror zones; injected into `MigrationCoordinator` |
| `ConstantNetworkReachability` | struct | `Packages/LillistCore/Sources/LillistCore/Sync/PauseReasonClassifier.swift:15` | Stub `NetworkReachabilityProviding` for tests and truth-table cases |
| `DisableStrategy` | enum | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift:14` | `.syncFirst` or `.now` for iCloudSync→LocalOnly transitions |
| `EnableDirection` | enum | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift:6` | `.replaceICloud` or `.replaceLocal` for LocalOnly→iCloudSync transitions |
| `FileMigrationJournalStore` | struct | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournalStore.swift:18` | Atomic-write file-backed `MigrationJournalStore`; absent file reads as `.idle` |
| `GatedPersistenceResolver` | struct | `Packages/LillistCore/Sources/LillistCore/Sync/GatedPersistenceResolver.swift:21` | Gate-aware store resolution for extensions and CLI; `makePersistence` builds the controller |
| `InMemoryMigrationJournalStore` | class | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournalStore.swift:70` | Lock-guarded in-memory `MigrationJournalStore` for unit tests |
| `LiveCloudKitZoneEraser` | struct | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitZoneEraserImpl.swift:21` | Production eraser fetching and deleting `com.apple.coredata.cloudkit.zone` zones |
| `MigrationCoordinator` | class | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift:39` | `@MainActor` orchestrator of the phased sync-mode swap; emits `MigrationPhase` events |
| `MigrationGate` | struct | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationGate.swift:9` | `evaluate()` returns `.proceed(mode:)` or `.abort(message:)` from journal + mode store |
| `MigrationJournal` | struct | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournal.swift:40` | Codable crash-survivable record; `isInFlight`/`isStale` drive the recovery sheet |
| `MigrationJournalStore` | protocol | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournalStore.swift:9` | Atomic read/write/clear contract for the journal across processes |
| `ModeTransitionOp` | enum | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournal.swift:6` | Four named transitions encoded into the journal for crash recovery |
| `NetworkReachabilityProviding` | protocol | `Packages/LillistCore/Sources/LillistCore/Sync/PauseReasonClassifier.swift:8` | Testable seam; production impl lives in the app target |
| `PauseReason` | enum | `Packages/LillistCore/Sources/LillistCore/Sync/PauseReason.swift:8` | Five named sync-paused reasons; keys the status badge and explainer dialog |
| `PauseReasonClassifier` | actor | `Packages/LillistCore/Sources/LillistCore/Sync/PauseReasonClassifier.swift:32` | `currentReason()` reduces account/network/drive state to a single `PauseReason?` |
| `QuiesceResult` | enum | `Packages/LillistCore/Sources/LillistCore/Sync/SyncQuiesceMonitor.swift:4` | `.quiesced` or `.timedOut` outcome of `waitForQuiesce` |
| `SyncMode` | enum | `Packages/LillistCore/Sources/LillistCore/Sync/SyncMode.swift:14` | `.localOnly` / `.iCloudSync`; raw values are stable storage literals |
| `SyncModeStore` | actor | `Packages/LillistCore/Sources/LillistCore/Sync/SyncModeStore.swift:14` | Persists `SyncMode` in App Group `UserDefaults`; `modeStream` broadcasts changes |
| `SyncQuiesceMonitor` | actor | `Packages/LillistCore/Sources/LillistCore/Sync/SyncQuiesceMonitor.swift:28` | `waitForQuiesce` polls `CloudKitEventBridge` until quiet window or hard timeout |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `runMigration` | func | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift:193` | The 8-phase state machine; step ordering is the module's core safety invariant |
| `evaluate` | func | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationGate.swift:27` | Single chokepoint for all headless store openers; aborts on any non-idle journal |
| `makePersistence` | func | `Packages/LillistCore/Sources/LillistCore/Sync/GatedPersistenceResolver.swift:59` | Resolve + build entry point for extensions and CLI; injectable build closure for tests |
| `isInFlight` | property | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournal.swift:127` | `state != .idle`; the gate and coordinator's shared reentrancy predicate |
| `currentMode` | func | `Packages/LillistCore/Sources/LillistCore/Sync/SyncModeStore.swift:30` | Reads App Group defaults; fallback to `SyncMode.default` when key absent |
| `translate` | func | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift:111` | Converts Apple's `Event` to `CloudKitSyncEvent`, routing errors via the classifier |
| `breadcrumb` | func | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift:106` | Awaited inline (not detached) to preserve phase ordering in the breadcrumb buffer |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.AccountStateMonitor -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-2.iCloudAccountState (owns)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.PauseReasonClassifier -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.AccountStateMonitor (reads)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.SyncQuiesceMonitor -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.CloudKitEventBridge (reads)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.CloudKitEventBridge -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.CloudKitErrorClassifier (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.MigrationCoordinator -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceReconfiguring (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.MigrationCoordinator -> Packages-LillistCore-Sources-LillistCore-Persistence.QuarantineManager (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.MigrationCoordinator -> Packages-LillistCore-Sources-LillistCore-Notifications.NotificationScheduler (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.MigrationCoordinator -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.PreferencesStore (reads)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.MigrationCoordinator -> Packages-LillistCore-Sources-LillistCore-CrashReporting.BreadcrumbBuffer (writes)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.MigrationCoordinator -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.SyncQuiesceMonitor (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.MigrationGate -> Packages-LillistCore-Sources-LillistCore-Persistence.StoreConfiguration (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.MigrationCoordinator -> Packages-LillistCore-Sources-LillistCore-misc.LillistLog (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.GatedPersistenceResolver -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.MigrationGate (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.GatedPersistenceResolver -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceController (calls)`
- `Extensions-ShareExtension-iOS.ShareRootView -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.GatedPersistenceResolver (calls)`
- `Extensions-ShortcutsActions-misc.IntentSupport -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.GatedPersistenceResolver (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.StoreLocator -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.MigrationGate (calls)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.MigrationCoordinator (owns)`
- `Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceController -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.SyncMode (reads)`

## Type notes

`MigrationCoordinator` is `@MainActor` (callers are SwiftUI views); it hops onto embedded actors for phase work. Concurrency is guarded twice: a persisted-journal check at `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift:200` plus the synchronous `isMigrating` flag at `:209` that closes the same-process window before the first `await`.

`runMigration` step ordering is load-bearing: notifications cancelled first, structural swap before the on-disk quarantine copy, disk-space pre-flight ahead of the irreversible CloudKit erase, and an account-changed abort immediately before that erase at `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift:299`.

`SyncMode` raw values are stable storage literals shared by App Group `UserDefaults` and the journal JSON; renaming a case requires a schema bump (`Packages/LillistCore/Sources/LillistCore/Sync/SyncMode.swift:11`).

`AccountStateMonitor` and `CloudKitEventBridge` register stream continuations synchronously on the actor before the getter returns, deliberately avoiding a `Task`-deferred write that would drop pre-subscription events (`Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift:66`).

`MigrationJournal.isStale` is consumed only by the main-app recovery sheet; `MigrationGate` ignores staleness and aborts on any non-idle journal (`Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournal.swift:147`).

## External deps

- CloudKit — `CKContainer`, `CKAccountStatus`, `CKRecordZone`, `CKError`/`CKErrorDomain`
- CoreData — `NSPersistentCloudKitContainer.Event` and its `eventChangedNotification`
- Foundation — `UserDefaults` App Group suite, `FileManager`, `AsyncStream`, JSON coders
- os — signposts and `LillistLog` logging in the migration runner

## Gotchas

- `NSPersistentCloudKitContainer` emits no terminal "done" event; `SyncQuiesceMonitor` uses a quiet-window heuristic instead (`Packages/LillistCore/Sources/LillistCore/Sync/SyncQuiesceMonitor.swift:21`).
- `MigrationJournal` tolerates the legacy `quarantineBackupID` UUID key on read but never writes it; journals using the old key fall back to the most-recent quarantine backup (`Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournal.swift:84`).
- `staleThreshold` is 600s (2× the 300s quiesce ceiling) so a live `.awaitingSync` migration is never misclassified as crashed (`Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournal.swift:135`).
- `NetworkReachabilityProviding` is not implemented inside `LillistCore` — `NWPathMonitor` doesn't compile cleanly under strict concurrency; the production impl lives in the app target (`Packages/LillistCore/Sources/LillistCore/Sync/PauseReasonClassifier.swift:7`).
