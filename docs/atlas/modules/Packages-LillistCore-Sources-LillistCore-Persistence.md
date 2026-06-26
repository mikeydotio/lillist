---
module: Packages/LillistCore/Sources/LillistCore/Persistence
summary: "Core Data container lifecycle: sync-mode swapping, remote-change reconciliation, and store-recovery."
read_when: "Touching Core Data container or sync swap"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/Persistence/AutoPurgeJob.swift
    blob: 98b3ec158aff941f4eca3fd7d7f8bfc994495fbc
  - path: Packages/LillistCore/Sources/LillistCore/Persistence/BackgroundPurgeSchedule.swift
    blob: b9cfcbfeba30b4008ecdbe69405f0a38501fb455
  - path: Packages/LillistCore/Sources/LillistCore/Persistence/CascadeReaper.swift
    blob: 4ac9cbee9e72909b142862e76dd1ddce5afdb49a
  - path: Packages/LillistCore/Sources/LillistCore/Persistence/CloudKitSchemaInitializer.swift
    blob: a1429f8ddbeb6b8be958d6ae09286788853c4ef2
  - path: Packages/LillistCore/Sources/LillistCore/Persistence/DiskSpaceProbe.swift
    blob: f9c68ab9c461c0f98677f45285a79dcbd9254841
  - path: Packages/LillistCore/Sources/LillistCore/Persistence/HistoryPruner.swift
    blob: 844e0a20282d6cd7fc420a1a522af0326751efb5
  - path: Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift
    blob: 2d4b47fd93c289592437720aee3d03917f2c7a93
  - path: Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift
    blob: b0107ef2a557f52b7152088ef184839a9e430046
  - path: Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceReconfiguring.swift
    blob: 4250478520895ef87f47c2f434a18cad0ff9d2c9
  - path: Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceResetting.swift
    blob: 5fd81673ea1c6cff09d9e9d06fa1f6ad59f25cf5
  - path: Packages/LillistCore/Sources/LillistCore/Persistence/PersistentHistoryTokenStore.swift
    blob: 93b66accc3ac506ac79595cb2102d2d45d97bdb8
  - path: Packages/LillistCore/Sources/LillistCore/Persistence/QuarantineManager.swift
    blob: ac21b6021fe13c001d2c704218672f4aea0d6477
  - path: Packages/LillistCore/Sources/LillistCore/Persistence/RemoteChangeReconciler.swift
    blob: a22bbf2eb5f6ddcc8cb57ade1affb0cdbd7b6a8b
  - path: Packages/LillistCore/Sources/LillistCore/Persistence/StoreConfiguration.swift
    blob: c59a31ce239ef8e8be01059899ace8e4d95e631d
references_modules: [Apps-Lillist-macOS-Sources-Hotkey, Extensions-ShortcutsActions-misc, Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2, Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistCore-Sources-LillistCore-Notifications, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Sync-chunk-1, Packages-LillistUI-Sources-LillistUI-Components-chunk-1]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistCore/Sources/LillistCore/Persistence

## Purpose

This module is the persistence substrate for all of LillistCore: it owns the NSPersistentContainer/NSPersistentCloudKitContainer lifecycle (PersistenceController), executes live sync-mode swaps by removing and re-adding the underlying store on the same container instance rather than re-instantiating it (PersistenceHost), and drives remote-change history reconciliation to prevent duplicate notifications after CloudKit imports (RemoteChangeReconciler). The organizing invariant is that the container instance is permanent — re-instantiating NSPersistentCloudKitContainer triggers internal setup races — so every mode change, destructive reset, and rollback flows through PersistenceHost's actor-serialized store-swap machinery. Remove this module and every Store, the CLI, the extensions, and the sync-mode migration machinery lose their database handle and all recovery safety guarantees.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AutoPurgeJob` | class | `Packages/LillistCore/Sources/LillistCore/Persistence/AutoPurgeJob.swift:6` | Hard-deletes trashed tasks past configured retention; callers inject PersistenceController and PreferencesStore; run() returns count of top-level tasks deleted. |
| `BackgroundPurgeSchedule` | enum | `Packages/LillistCore/Sources/LillistCore/Persistence/BackgroundPurgeSchedule.swift:11` | BGTaskScheduler task ID ("app.lillist.autopurge") and 24h minimum interval; values must match Info.plist entry and submitted BGProcessingTaskRequest verbatim. |
| `CascadeReaper` | enum | `Packages/LillistCore/Sources/LillistCore/Persistence/CascadeReaper.swift:29` | Stateless cascade-walker; must be invoked on the context's queue; returns all cascade-closure IDs for given LillistTask roots. |
| `CloudKitSchemaInitializer` | enum | `Packages/LillistCore/Sources/LillistCore/Persistence/CloudKitSchemaInitializer.swift:16` | DEBUG-only namespace; pushes Core Data model record types to CloudKit development environment; no-ops in Release; never call in production. |
| `DiskSpaceProbing` | protocol | `Packages/LillistCore/Sources/LillistCore/Persistence/DiskSpaceProbe.swift:9` | Injectable protocol; availableCapacity returns volumeAvailableCapacityForImportantUsage; footprint sums .sqlite+.wal+.shm bytes, returns 0 if absent. |
| `Error` | enum | `Packages/LillistCore/Sources/LillistCore/Persistence/CloudKitSchemaInitializer.swift:17` | schemaInitializationFailed(String): thrown when initializeCloudKitSchema fails in DEBUG; message is NSError localizedDescription. |
| `FileManagerDiskSpaceProbe` | struct | `Packages/LillistCore/Sources/LillistCore/Persistence/DiskSpaceProbe.swift:24` | Production DiskSpaceProbing conformer backed by FileManager/URLResourceValues; probes parent directory when url doesn't exist yet (e.g., target restore location). |
| `HistoryPruner` | class | `Packages/LillistCore/Sources/LillistCore/Persistence/HistoryPruner.swift:20` | Prunes persistent history for .localOnly stores; sweep() is a no-op for .iCloudSync; inject any UserDefaults suite for testing. |
| `MigrationPhase` | enum | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift:8` | Phase enum for MigrationCoordinator's UI progress; erasingICloud and uploading/downloading carry Double progress; failed carries a reason string. |
| `PersistenceController` | class | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift:17` | Async throws init; on success container viewContext and cloudKitEventBridge are ready, transactionAuthor stamped; in-memory config uses plain NSPersistentContainer. |
| `PersistenceHost` | actor | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift:37` | Actor owning PersistenceController and currentMode; reconfigure(to:) swaps sync modes; tearDown/rebuild/reattach drive destructive resets; make() is the async factory. |
| `PersistenceReconfiguring` | protocol | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceReconfiguring.swift:18` | Mode-swap seam for MigrationCoordinator; Sendable so @MainActor callers hold it; reconfigure(to:) must be transactional (no store-less coordinator on failure). |
| `PersistenceResetting` | protocol | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceResetting.swift:18` | Destructive-reset protocol (ISP: segregated from PersistenceReconfiguring); consumed only by DataStoreResetService; Sendable for @MainActor callers. |
| `PersistentHistoryTokenStore` | class | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistentHistoryTokenStore.swift:13` | Persists NSPersistentHistoryToken in App Group UserDefaults (NSKeyedArchiver); three keys (defaultKey, diagnosticsKey, backupKey) keep consumer watermarks independent. |
| `QuarantineManager` | struct | `Packages/LillistCore/Sources/LillistCore/Persistence/QuarantineManager.swift:9` | Filesystem-only (never opens Core Data); copies or moves SQLite + sidecars into timestamped quarantine folders; injectable DiskSpaceProbing; 30-day retention. |
| `QuarantinedBackup` | struct | `Packages/LillistCore/Sources/LillistCore/Persistence/QuarantineManager.swift:15` | Equatable Sendable value type with folderName (timestamped subfolder) and storeURL; folderName is recorded in migration journal for exact restore. |
| `RemoteChangeReconciler` | class | `Packages/LillistCore/Sources/LillistCore/Persistence/RemoteChangeReconciler.swift:19` | Watches NSPersistentStoreRemoteChange; diffs history for foreign-author NotificationSpec.lastFiredAt changes; fires onAffectedTasks with affected task UUIDs. |
| `StoreConfiguration` | struct | `Packages/LillistCore/Sources/LillistCore/Persistence/StoreConfiguration.swift:15` | Sendable config (storeKind, syncMode, cloudKitContainerIdentifier); modified copies via withCloudKitContainer(_:) and withSyncMode(_:). |
| `StoreKind` | enum | `Packages/LillistCore/Sources/LillistCore/Persistence/StoreConfiguration.swift:20` | .inMemory = plain NSPersistentContainer (no CloudKit mirroring); .onDisk(url:) = NSPersistentCloudKitContainer; in-memory never mirrors regardless of syncMode. |
| `SyntheticChange` | struct | `Packages/LillistCore/Sources/LillistCore/Persistence/RemoteChangeReconciler.swift:23` | Sendable persistent-history change snapshot; decouples RemoteChangeReconciler's diffing core from live Core Data types so tests can inject history without a real store. |
| `appGroupOnDisk` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/StoreConfiguration.swift:73` | Returns on-disk config at <AppGroupContainer>/Lillist/Lillist.sqlite; nil when group container is unreachable (missing entitlement or unsigned context). |
| `availableCapacity` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/DiskSpaceProbe.swift:15` | Protocol requirement: returns free bytes for 'important' usage on the volume containing url via volumeAvailableCapacityForImportantUsageKey. |
| `availableCapacity` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/DiskSpaceProbe.swift:27` | Probes parent directory if url has no directory path; throws LillistError.storeUnavailable when the volume capacity key is absent. |
| `batchDelete` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/CascadeReaper.swift:122` | Executes per-entity NSBatchDeleteRequests leaf-first; returns deleted IDs for viewContext merge via NSDeletedObjectsKey; must run on context's queue. |
| `cleanupExpired` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/QuarantineManager.swift:133` | Deletes quarantine subfolders older than retentionInterval (30 days) by modification date; safe to call when no store is open. |
| `copyStore` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/QuarantineManager.swift:89` | Copies SQLite + sidecars into quarantine (originals stay); pre-flights disk space (2x footprint) before any write; returns QuarantinedBackup. |
| `footprint` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/DiskSpaceProbe.swift:20` | Protocol requirement: returns total on-disk bytes for storeURL including -wal and -shm sidecars; returns 0 if the main file is absent. |
| `footprint` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/DiskSpaceProbe.swift:39` | Sums totalFileAllocatedSize (preferred) or fileSize for .sqlite, .wal, .shm; returns 0 if the main .sqlite file is absent. |
| `initializeIfNeeded` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/CloudKitSchemaInitializer.swift:24` | No-ops in Release; in DEBUG calls initializeCloudKitSchema on NSPersistentCloudKitContainer; dryRun skips CloudKit for test verification. |
| `latestQuarantinedStore` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/QuarantineManager.swift:192` | Returns most-recently-modified quarantine folder's .sqlite URL, or nil; fallback when migration journal's exact folderName is unavailable. |
| `localTaskRowCount` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift:104` | Non-trashed task count from viewContext; fails closed (any error returns 0, blocking the destructive iCloud-erase guard in MigrationCoordinator). |
| `make` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift:84` | Async factory building PersistenceController for initialMode at storeURL and wrapping it in a host; cloudKitContainerIdentifier defaults to production container. |
| `makeBackgroundContext` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift:127` | Private-queue context with auto-merge, matching mergePolicy, and same transactionAuthor as viewContext so history diffs classify bulk writes as local. |
| `makeContainer` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift:147` | Returns NSPersistentContainer (inMemory) or NSPersistentCloudKitContainer (onDisk) without loading stores; throws LillistError.modelUnavailable if model is absent. |
| `makeStoreDescription` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift:169` | Always enables persistent-history and remote-change tracking; cloudKitContainerOptions attached only for onDisk+iCloudSync; usable from tests without a live container. |
| `objectIDs` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/CascadeReaper.swift:39` | Returns deduplicated NSManagedObjectIDs covering the full cascade subtree of task roots (tasks, journal entries, attachments, notification specs); must run on context's queue. |
| `onDisk` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/StoreConfiguration.swift:49` | Factory returning an on-disk StoreConfiguration at the given URL; syncMode defaults to .default (resolves to .iCloudSync in production). |
| `processPendingHistory` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/RemoteChangeReconciler.swift:90` | Advances tokenStore watermark and fires onAffectedTasks; public for launch catch-up; transient store errors are swallowed (next remote-change notification retries). |
| `quarantineStore` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/QuarantineManager.swift:60` | Moves SQLite + sidecars into a timestamped quarantine folder (destructive — original location vacated); returns destination URL. |
| `quarantinedStore` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/QuarantineManager.swift:124` | Resolves .sqlite URL for a named quarantine folder; returns nil if absent; prefer over latestQuarantinedStore when migration journal recorded the exact folderName. |
| `reattachStore` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift:354` | Re-adds the original store (files still on disk) for currentMode; idempotent — no-op when a store is already attached to the coordinator. |
| `reattachStore` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceResetting.swift:45` | Protocol requirement: re-adds original store so coordinator is never store-less after a failed step between tearDownStore and rebuildEmptyStore. |
| `rebuildEmptyStore` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift:329` | Destroys torn-down store files via destroyPersistentStore, adds a fresh empty store for currentMode, and resets viewContext; must follow tearDownStore. |
| `rebuildEmptyStore` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceResetting.swift:39` | Protocol requirement: destroys torn-down store files and adds a fresh empty store for currentMode; resets viewContext; must follow tearDownStore. |
| `reconfigure` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift:123` | Idempotent sync-mode swap (no-op when mode unchanged); transactional — rolls back to original description preserving CloudKit options on add failure. |
| `reconfigure` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceReconfiguring.swift:26` | Transactional sync-mode swap; implementations must leave the store in pre-call mode on any failure (never leave the coordinator store-less). |
| `requiredBytesForQuarantine` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/QuarantineManager.swift:51` | Returns quarantineHeadroomFactor (2x) times the live store's on-disk footprint; minimum free bytes required before copyStore will proceed. |
| `restore` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/QuarantineManager.swift:164` | Copies quarantined backup to targetURL; existing file at target is quarantined first (recoverable in turn); returns restored targetURL. |
| `rollbackDescriptionForTesting` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift:104` | Test seam returning the NSPersistentStoreDescription the last rollback re-added; lets tests assert CloudKit options survived without inspecting live container internals. |
| `run` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/AutoPurgeJob.swift:16` | Returns count of top-level tasks hard-deleted; merges deletions into viewContext; throws on Core Data errors; now param is injectable for testing. |
| `sharedModel` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift:222` | Cached NSManagedObjectModel; tries LillistModel.momd then LillistModel.spm.momd; throws LillistError.modelUnavailable if neither is found. |
| `simulateAddFailureOnNextSwap` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift:97` | Test seam: arms a single simulated addPersistentStore failure on the next reconfigure to exercise the rollback path; auto-resets after one use. |
| `start` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/RemoteChangeReconciler.swift:64` | Registers NSPersistentStoreRemoteChange observer; idempotent (guard observer == nil); must be called once at bootstrap. |
| `stop` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/RemoteChangeReconciler.swift:78` | Removes the observer; optional in production (weak ref makes stale token harmless); required for deterministic test teardown. |
| `sweep` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/HistoryPruner.swift:53` | Prunes history up to current token and persists token to UserDefaults; returns true if pruned, false if skipped (.iCloudSync); idempotent. |
| `tearDownStore` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift:303` | Discards pending writes, removes live store from coordinator, copies to quarantine (pre-flight throws on low disk space); returns backup descriptor or nil. |
| `tearDownStore` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceResetting.swift:33` | Protocol requirement: removes live store (closes SQLite), optionally quarantines (pre-flight throws on low disk); returns backup or nil; throws before caller's irreversible ops. |
| `withCloudKitContainer` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/StoreConfiguration.swift:86` | Returns a copy with a substituted cloudKitContainerIdentifier; used to target non-production containers in tests and schema-init builds. |
| `withSyncMode` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/StoreConfiguration.swift:95` | Returns a copy with substituted syncMode; used in PersistenceHost.make and tests to parameterize descriptions without mutating shared configs. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `configuration` | func | `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift:279` | Single reconstruction point for StoreConfiguration from the actor's stored storeURL, cloudKitContainerIdentifier, and a target SyncMode. All four store-mutation paths (forward swap, rollback re-add inside flushAndSwap, rebuildEmptyStore, reattachStore) call this function to obtain the description they pass to addStore(_:to:). Without this centralisation any one path could silently omit cloudKitContainerOptions and downgrade the store from iCloud to plain local — the 'Roadmap #1' invariant the rollback path was designed to preserve. [Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift:279-290, 160-161, 338, 360] |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceController -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.CloudKitEventBridge (owns)`
- `Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceController -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.attach (calls)`
- `Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceResetting -> Apps-Lillist-macOS-Sources-Hotkey.place (calls)`
- `Packages-LillistCore-Sources-LillistCore-Persistence.StoreConfiguration -> Packages-LillistCore-Sources-LillistCore-Notifications.identifier (calls)`
- `Packages-LillistCore-Sources-LillistCore-Persistence.SyntheticChange -> Extensions-ShortcutsActions-misc.controller (calls)`
- `Packages-LillistCore-Sources-LillistCore-Persistence.copyStore -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistCore-Sources-LillistCore-Persistence.flushAndSwap -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1.closure (calls)`
- `Packages-LillistCore-Sources-LillistCore-Persistence.localTaskRowCount -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.count (calls)`
- `Packages-LillistCore-Sources-LillistCore-Persistence.sharedModel -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.get (calls)`

## Type notes

PersistenceController is @unchecked Sendable (not an actor); thread safety is delegated to Core Data's context queue APIs. NSManagedObjectModel is cached in a nonisolated(unsafe) static let cachedModelResult — loading a fresh model per constructor causes Core Data to warn about duplicate Swift class registrations in parallel test workers. [Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift:17, 226]

PersistenceHost is a Swift actor conforming to both PersistenceReconfiguring and PersistenceResetting; the actor boundary is why all protocol members are async. The store swap runs inside a single viewContext.perform critical section so the coordinator is never left store-less mid-flight. [Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift:37, 174]

flushAndSwap hoists actor-isolated writes (lastRollbackDescription) out of the @Sendable perform closure — strict concurrency forbids mutating actor-isolated state inside a @Sendable closure. The RollbackOccurred error carries no NSPersistentStoreDescription payload (not Sendable); the description is rebuilt from a Sendable StoreConfiguration after the closure returns. [Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift:164-233]

RemoteChangeReconciler is @unchecked Sendable; its mutable observer token is only touched in start()/stop(). NSPersistentHistoryToken is not Sendable — it is archived to Data entirely inside ctx.perform; only Data crosses the closure boundary. [Packages/LillistCore/Sources/LillistCore/Persistence/RemoteChangeReconciler.swift:19]

PersistentHistoryTokenStore is @unchecked Sendable wrapping thread-safe UserDefaults. Three distinct static keys (defaultKey, diagnosticsKey, backupKey) prevent history consumers from clobbering each other's watermarks. [Packages/LillistCore/Sources/LillistCore/Persistence/PersistentHistoryTokenStore.swift:13, 18-25]

QuarantineManager is a pure Sendable struct that never opens Core Data; injectable DiskSpaceProbing enables disk-full test paths. retentionInterval is 30 days. [Packages/LillistCore/Sources/LillistCore/Persistence/QuarantineManager.swift:9-10]

## External deps

- CloudKit — imported
- CoreData — imported
- Foundation — imported
- changes: — imported

## Gotchas

1. NSPersistentCloudKitContainer is never re-instantiated across sync-mode swaps — only the underlying store is removed and re-added on the same coordinator. Re-instantiation triggers races in _loadStoreDescriptions/PFCloudKitSetupAssistant. [Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift:27-31]
2. addPersistentStore(with:completionHandler:) is NS_SWIFT_DISABLE_ASYNC; addStore(_:to:) bridges it via a completion handler read inline. The synchronous-add assumption is enforced by a hard guard: shouldAddStoreAsynchronously == true throws immediately — an async add would silently treat a failed rollback re-add as success on the data-loss recovery path. [Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift:263-276]
3. NSBatchDeleteRequest bypasses Core Data cascade rules. CascadeReaper manually expands the cascade closure and issues one request per entity leaf-first because passing mixed-entity IDs to a single request throws NSInvalidArgumentException. [Packages/LillistCore/Sources/LillistCore/Persistence/CascadeReaper.swift:8-14]
4. sharedModel() caches NSManagedObjectModel in a nonisolated(unsafe) static let — loading fresh per constructor causes Core Data to warn about duplicate Swift class registrations across parallel test workers. [Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift:207-216]
5. HistoryPruner.sweep() is a deliberate no-op for .iCloudSync because NSPersistentCloudKitContainer owns its own history pruning — the guard is explicit to prevent silent double-pruning. [Packages/LillistCore/Sources/LillistCore/Persistence/HistoryPruner.swift:13-15]
