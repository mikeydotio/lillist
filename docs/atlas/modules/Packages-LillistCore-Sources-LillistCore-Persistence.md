---
module: Packages/LillistCore/Sources/LillistCore/Persistence
summary: "Core Data stack ownership, sync-mode store swapping, Trash purge, history tracking, and quarantine safety net"
read_when: "Touching the Core Data container, CloudKit store swap, persistent history, Trash purge, or quarantine backup"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/Persistence/AutoPurgeJob.swift
  - path: Packages/LillistCore/Sources/LillistCore/Persistence/BackgroundPurgeSchedule.swift
  - path: Packages/LillistCore/Sources/LillistCore/Persistence/CascadeReaper.swift
  - path: Packages/LillistCore/Sources/LillistCore/Persistence/CloudKitSchemaInitializer.swift
  - path: Packages/LillistCore/Sources/LillistCore/Persistence/DiskSpaceProbe.swift
  - path: Packages/LillistCore/Sources/LillistCore/Persistence/HistoryPruner.swift
  - path: Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift
  - path: Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift
  - path: Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceReconfiguring.swift
  - path: Packages/LillistCore/Sources/LillistCore/Persistence/PersistentHistoryTokenStore.swift
  - path: Packages/LillistCore/Sources/LillistCore/Persistence/QuarantineManager.swift
  - path: Packages/LillistCore/Sources/LillistCore/Persistence/RemoteChangeReconciler.swift
  - path: Packages/LillistCore/Sources/LillistCore/Persistence/StoreConfiguration.swift
references_modules: [Packages-LillistCore-Sources-LillistCore-Sync-chunk-1, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-ManagedObjects, Packages-LillistCore-Sources-LillistCore-Diagnostics, Packages-LillistCore-Sources-LillistCore-misc, Apps-Lillist-iOS-Sources-App]
generator: cartographer/1 model=claude-sonnet-4-6
---

# Module: Packages/LillistCore/Sources/LillistCore/Persistence

## Purpose

Owns the Core Data stack: it builds and loads the container, vends the shared
view context and background contexts, and is the single place that mutates the
persistent-store coordinator after bring-up. The design idea holding it together
is that a sync-mode change is a *store-level remove+re-add on one long-lived
container* (never a re-instantiation), so the on-disk path can flip between
iCloud-mirroring and local-only without tripping the `NSPersistentCloudKitContainer`
load races. If this module vanished, nothing else could open the database, swap
sync modes safely, or reconcile CloudKit imports.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AutoPurgeJob` | class | `Packages/LillistCore/Sources/LillistCore/Persistence/AutoPurgeJob.swift:6` | Hard-deletes soft-deleted tasks past retention; `run` returns count of top-level tasks purged |
| `BackgroundPurgeSchedule` | enum | `Packages/LillistCore/Sources/LillistCore/Persistence/BackgroundPurgeSchedule.swift:11` | Constants for the iOS `BGTaskScheduler` purge task id and earliest interval |
| `CascadeReaper` | enum | `Packages/LillistCore/Sources/LillistCore/Persistence/CascadeReaper.swift:29` | Expands a task delete to its full cascade closure, then batch-deletes per entity |
| `CloudKitSchemaInitializer` | enum | `Packages/LillistCore/Sources/LillistCore/Persistence/CloudKitSchemaInitializer.swift:16` | DEBUG-only bootstrap of the CloudKit dev schema; no-op in release / in-memory |
| `DiskSpaceProbing` | protocol | `Packages/LillistCore/Sources/LillistCore/Persistence/DiskSpaceProbe.swift:9` | Injectable free-space + store-footprint probe for the quarantine pre-flight |
| `FileManagerDiskSpaceProbe` | struct | `Packages/LillistCore/Sources/LillistCore/Persistence/DiskSpaceProbe.swift:24` | Production `DiskSpaceProbing` over `FileManager`/`URLResourceValues` |
| `HistoryPruner` | class | `Packages/LillistCore/Sources/LillistCore/Persistence/HistoryPruner.swift:20` | Sweeps persistent history for `.localOnly` stores; no-op under `.iCloudSync` |
| `MigrationPhase` | enum | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift:8` | Per-phase progress identifier emitted around a sync-mode swap |
| `PersistenceController` | class | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift:17` | Owns the container; vends `viewContext` + background contexts; static description/model factories |
| `PersistenceHost` | actor | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift:37` | Owns the controller + canonical `currentMode`; only mutator of the coordinator |
| `PersistenceReconfiguring` | protocol | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceReconfiguring.swift:18` | Minimal swap seam the migration coordinator depends on; fakeable under `swift test` |
| `PersistentHistoryTokenStore` | class | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistentHistoryTokenStore.swift:13` | App-Group-backed watermark for history diffing; keyed per consumer |
| `QuarantineManager` | struct | `Packages/LillistCore/Sources/LillistCore/Persistence/QuarantineManager.swift:9` | Filesystem-only store backup/restore + retention prune; never opens Core Data |
| `RemoteChangeReconciler` | class | `Packages/LillistCore/Sources/LillistCore/Persistence/RemoteChangeReconciler.swift:19` | Diffs history on remote change; reports tasks whose CloudKit import touched `lastFiredAt` |
| `StoreConfiguration` | struct | `Packages/LillistCore/Sources/LillistCore/Persistence/StoreConfiguration.swift:15` | Value type describing store kind, CloudKit container id, and sync mode |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `makeStoreDescription` | static func | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift:169` | Pure factory deciding when CloudKit options attach; the swap is a description mutation built from it |
| `makeContainer` | static func | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift:147` | Picks plain vs CloudKit container by store kind — the in-memory/on-disk asymmetry |
| `reconfigure` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift:123` | Public swap entry; idempotent guard then `flushAndSwap`, advances `currentMode` |
| `flushAndSwap` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift:139` | Transactional remove+re-add in one `perform`; rolls back to a *mirroring* store on add-failure |
| `addStore` | static func | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift:263` | Description-taking add so `cloudKitContainerOptions` round-trip; guards against async add |
| `makeBackgroundContext` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift:127` | Separate private-queue context for bulk work; same author/merge policy as `viewContext` |
| `processPendingHistory` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/RemoteChangeReconciler.swift:90` | Walks history since watermark, advances it, fires the affected-tasks callback |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceHost -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceReconfiguring (conforms-to)`
- `Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceHost -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceController (owns)`
- `Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceController -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.CloudKitEventBridge (owns)`
- `Packages-LillistCore-Sources-LillistCore-Persistence.StoreConfiguration -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.SyncMode (reads)`
- `Packages-LillistCore-Sources-LillistCore-Persistence.AutoPurgeJob -> Packages-LillistCore-Sources-LillistCore-Persistence.CascadeReaper (calls)`
- `Packages-LillistCore-Sources-LillistCore-Persistence.AutoPurgeJob -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.PreferencesStore (reads)`
- `Packages-LillistCore-Sources-LillistCore-Persistence.CascadeReaper -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.LillistTask (reads)`
- `Packages-LillistCore-Sources-LillistCore-Persistence.RemoteChangeReconciler -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.NotificationSpec (reads)`
- `Packages-LillistCore-Sources-LillistCore-Persistence.QuarantineManager -> Packages-LillistCore-Sources-LillistCore-Persistence.DiskSpaceProbing (calls)`
- `Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceController -> Packages-LillistCore-Sources-LillistCore-misc.LillistError (emits)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.MigrationCoordinator -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceReconfiguring (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.MigrationCoordinator -> Packages-LillistCore-Sources-LillistCore-Persistence.QuarantineManager (calls)`
- `Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticHistoryObserver -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistentHistoryTokenStore (owns)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceHost (owns)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Persistence.AutoPurgeJob (owns)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Persistence.RemoteChangeReconciler (owns)`

## Type notes

`PersistenceController` is `@unchecked Sendable`; the compiled `NSManagedObjectModel`
is cached once in `cachedModelResult` and reused so parallel test workers don't
re-register entities (`Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift:226`).
`PersistenceHost` is an `actor` and the only mutator of the coordinator post-init;
`reconfigure` is idempotent and `flushAndSwap` is transactional — on add-failure it
re-adds the *original* description so the store is never left store-less or silently
downgraded from iCloud to plain-local (`Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift:201`).
The view context survives a swap because it stays attached to the same coordinator.
`QuarantineManager`, `DiskSpaceProbing`, and `BackgroundPurgeSchedule` operate purely
on the filesystem / hold constants and never open Core Data. `CascadeReaper` and
`AutoPurgeJob` body work must run inside the owning context's `perform` queue.

## External deps

- CoreData — `NSPersistentContainer` / `NSPersistentCloudKitContainer`, history requests, batch delete
- CloudKit — `CKDatabase.Scope.private` for the mirrored store description and dev-schema init
- Foundation — `FileManager`, `URLResourceValues`, `UserDefaults` (App Group suites), `NSKeyedArchiver`

## Gotchas

- In-memory stores use plain `NSPersistentContainer`; instantiating `NSPersistentCloudKitContainer` 90+ times in parallel test workers triggers internal load races (`Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift:9`).
- `localTaskRowCount` fails closed — any error returns `0` so an uncertain count blocks the irreversible erase (`Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift:104`).
- `addStore` hard-guards `shouldAddStoreAsynchronously == false`; an async add would read a nil error inline and treat a failed rollback as success (`Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift:267`).
- Persistent history stays ON for `.localOnly` stores, so `HistoryPruner.sweep` must run or transactions accumulate unbounded (`Packages/LillistCore/Sources/LillistCore/Persistence/HistoryPruner.swift:4`).
- `NSBatchDeleteRequest(objectIDs:)` is single-entity; `CascadeReaper.batchDelete` groups IDs and deletes leaf-first to respect FK order (`Packages/LillistCore/Sources/LillistCore/Persistence/CascadeReaper.swift:99`).
