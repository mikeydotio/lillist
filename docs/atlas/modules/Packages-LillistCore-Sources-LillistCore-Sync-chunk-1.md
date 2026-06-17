---
module: "Packages/LillistCore/Sources/LillistCore/Sync (chunk 1)"
summary: "Sync-mode model, in-flight-migration journal/gate, and the mode-change migration coordinator"
read_when: "iCloud sync-mode migrations"
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
references_modules: [Packages-LillistCore-Sources-LillistCore-Sync-chunk-2, Packages-LillistCore-Sources-LillistCore-Persistence, Packages-LillistCore-Sources-LillistCore-Notifications, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-CrashReporting, Packages-LillistCore-Sources-LillistCore-misc, Extensions-ShareExtension-iOS, Extensions-ShortcutsActions-misc, Packages-LillistCore-Sources-LillistCore-CLIBridge-misc, Apps-Lillist-iOS-Sources-App]
generator: cartographer/1
baseline: 34dfea7772679dbabc08fabd6fbba53f6ad5856b
---

# Module: Packages/LillistCore/Sources/LillistCore/Sync (chunk 1)

## Purpose

This chunk owns Plan 21's user-controlled iCloud sync mode and the machinery that safely
switches between modes. `SyncMode` (the persisted localOnly/iCloudSync choice) and the
file-backed `MigrationJournal` form a cross-process protocol: any headless caller consults
the journal through `MigrationGate` before opening the store, while `MigrationCoordinator`
drives the phased, recoverable store swap. The design idea is that a half-completed mode
change must never corrupt data — the journal makes interrupted migrations recoverable and
the gate makes them visible to extensions and the CLI.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AccountStateMonitor` | actor | `Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift:23` | Observes iCloud account state; `refresh()`/`stateStream` publish changes |
| `AccountStatusProviding` | protocol | `Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift:5` | Testable seam over `CKContainer.accountStatus()` |
| `AccountStateProviding` | typealias | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift:36` | `@Sendable` probe injected so the coordinator avoids a direct CloudKit dep |
| `CloudKitAccountStatusProvider` | struct | `Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift:10` | Production `AccountStatusProviding` over a real `CKContainer` |
| `CloudKitEraseSummary` | struct | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitZoneEraser.swift:6` | Zone IDs deleted in one erase call |
| `CloudKitErrorClassifier` | enum | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitErrorClassifier.swift:18` | `classify(_:)` maps a CK/NSError to the `LillistError` taxonomy |
| `CloudKitEventBridge` | actor | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift:35` | Bridges `eventChangedNotification` into a testable `eventStream` |
| `CloudKitSyncEvent` | struct | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift:9` | Internal mirror of `NSPersistentCloudKitContainer.Event` |
| `CloudKitZoneEraser` | protocol | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitZoneEraser.swift:24` | `eraseManagedZones(in:progress:)` wipes the Core Data mirror zone |
| `ConstantNetworkReachability` | struct | `Packages/LillistCore/Sources/LillistCore/Sync/PauseReasonClassifier.swift:15` | Fixed-answer reachability for tests/truth tables |
| `DisableStrategy` | enum | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift:14` | `syncFirst` vs `now` for disabling iCloud |
| `EnableDirection` | enum | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift:6` | `replaceICloud` vs `replaceLocal` when enabling iCloud |
| `FileMigrationJournalStore` | struct | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournalStore.swift:18` | Atomic JSON journal in the App Group container |
| `GatedPersistenceResolver` | struct | `Packages/LillistCore/Sources/LillistCore/Sync/GatedPersistenceResolver.swift:21` | Gate-aware store resolution shared by extensions; `makePersistence` builds the controller |
| `InMemoryMigrationJournalStore` | class | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournalStore.swift:70` | Lock-guarded in-memory journal for tests |
| `LiveCloudKitZoneEraser` | struct | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitZoneEraserImpl.swift:21` | Production eraser deleting `com.apple.coredata.cloudkit.zone` zones |
| `MigrationCoordinator` | class | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift:39` | `@MainActor` orchestrator of the phased mode-change migration |
| `MigrationGate` | struct | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationGate.swift:9` | `evaluate()`/`resolveStoreConfiguration` decide open-store vs abort |
| `MigrationJournal` | struct | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournal.swift:40` | Codable in-flight record; `isInFlight`/`isStale` drive recovery |
| `MigrationJournalStore` | protocol | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournalStore.swift:9` | Atomic read/write/clear of the journal across processes |
| `ModeTransitionOp` | enum | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournal.swift:6` | The four high-level mode transitions recorded in the journal |
| `NetworkReachabilityProviding` | protocol | `Packages/LillistCore/Sources/LillistCore/Sync/PauseReasonClassifier.swift:8` | Testable seam over network reachability |
| `PauseReason` | enum | `Packages/LillistCore/Sources/LillistCore/Sync/PauseReason.swift:8` | Why iCloud sync is paused; keys the status badge + explainer |
| `PauseReasonClassifier` | actor | `Packages/LillistCore/Sources/LillistCore/Sync/PauseReasonClassifier.swift:32` | `currentReason()` collapses account/network/drive state to a `PauseReason` |
| `QuiesceResult` | enum | `Packages/LillistCore/Sources/LillistCore/Sync/SyncQuiesceMonitor.swift:4` | `quiesced` vs `timedOut` outcome of a quiesce wait |
| `SyncMode` | enum | `Packages/LillistCore/Sources/LillistCore/Sync/SyncMode.swift:14` | localOnly/iCloudSync; raw values are stable storage literals |
| `SyncModeStore` | actor | `Packages/LillistCore/Sources/LillistCore/Sync/SyncModeStore.swift:14` | Persists `SyncMode` in App Group defaults; `modeStream` broadcasts changes |
| `SyncQuiesceMonitor` | actor | `Packages/LillistCore/Sources/LillistCore/Sync/SyncQuiesceMonitor.swift:28` | `waitForQuiesce` returns once CloudKit events go quiet |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `runMigration` | func | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift:193` | The phased state machine; ordering of its steps is the module's core invariant |
| `evaluate` | func | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationGate.swift:27` | Single decision point: abort on any in-flight journal, else proceed |
| `translate` | func | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift:111` | Converts Apple's `Event` to `CloudKitSyncEvent`, routing errors via the classifier |
| `isInFlight` | property | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournal.swift:127` | `state != .idle`; the gate's and coordinator's reentrancy predicate |
| `currentMode` | func | `Packages/LillistCore/Sources/LillistCore/Sync/SyncModeStore.swift:30` | Resolves the persisted mode or the documented default |

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

- `MigrationCoordinator` is `@MainActor` (callers are SwiftUI views); it hops onto embedded
  actors for phase work. Concurrency is guarded twice: a persisted-journal check at
  `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift:200` plus the
  synchronous `isMigrating` flag at `:214` that closes the same-process window before the
  first `await`.
- `runMigration` step order is load-bearing: notifications cancelled first, structural swap
  before the on-disk quarantine copy, disk-space pre-flight ahead of the irreversible
  CloudKit erase, and an account-changed abort before erase
  (`Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift:299`).
- `SyncMode` raw values are stable storage literals shared by App Group `UserDefaults` and
  the journal JSON; renaming a case needs a schema bump
  (`Packages/LillistCore/Sources/LillistCore/Sync/SyncMode.swift:11`).
- `AccountStateMonitor` and `CloudKitEventBridge` register stream continuations
  *synchronously* on the actor before the getter returns, deliberately avoiding a
  `Task`-deferred write that would drop pre-subscription events
  (`Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift:66`).
- `MigrationJournal.isStale` is consumed only by the main-app recovery sheet; `MigrationGate`
  ignores staleness and aborts on any non-idle journal
  (`Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournal.swift:147`).

## External deps

- CloudKit — `CKContainer`/`CKAccountStatus`, `CKRecordZone`, `CKError`/`CKErrorDomain`
- CoreData — `NSPersistentCloudKitContainer.Event` and its change notification
- Foundation — `UserDefaults`, `FileManager` App Group container, `AsyncStream`, JSON coders
- os — signposts and `LillistLog` logging in the migration runner

## Gotchas

- `NSPersistentCloudKitContainer` emits no terminal "done" event, so `SyncQuiesceMonitor`
  uses a quiet-window heuristic, not a completion signal
  (`Packages/LillistCore/Sources/LillistCore/Sync/SyncQuiesceMonitor.swift:21`).
- The journal tolerates a legacy `quarantineBackupID` key on read but never writes it; old
  journals fall back to the most-recent quarantine backup
  (`Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournal.swift:84`).
- `staleThreshold` is set to 600s (2x the 300s quiesce ceiling) so a live `.awaitingSync`
  migration is never misclassified as crashed
  (`Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournal.swift:135`).
