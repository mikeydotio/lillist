---
module: "Packages/LillistCore/Sources/LillistCore/Sync (chunk 1)"
summary: "Sync-mode state machine, store reset/recovery, CloudKit error classification, and migration gate for extensions/CLI"
read_when: "Touching sync-mode switching, migration state machine, or store reset/recovery"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift
    blob: 43ede62cf0943fa3e0a4003c0743463c9a98d778
  - path: Packages/LillistCore/Sources/LillistCore/Sync/CloudKitErrorClassifier.swift
    blob: 9a6bd3c37b7c8c7fba0073f43b87703601b72616
  - path: Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift
    blob: 4ef1e6a0d85c68c5bef05f4d359b09f99ab9a2b4
  - path: Packages/LillistCore/Sources/LillistCore/Sync/CloudKitZoneEraser.swift
    blob: ad119cf1626b1790cfe98a52a42155c6fb08ef9d
  - path: Packages/LillistCore/Sources/LillistCore/Sync/CloudKitZoneEraserImpl.swift
    blob: bbf1a0495a5e246ba2c26723d035b4647abe2fb6
  - path: Packages/LillistCore/Sources/LillistCore/Sync/DataStoreResetService.swift
    blob: 30bf806d41de4ccd7c42df78040e26d7da949ba9
  - path: Packages/LillistCore/Sources/LillistCore/Sync/GatedPersistenceResolver.swift
    blob: dd439297585e852a76724ec77944b8b3c9467faa
  - path: Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift
    blob: 96f92a594255c8db423651b69677465a2e3f96c0
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
references_modules: [Extensions-ShareExtension-iOS, Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistCore-Sources-LillistCore-Notifications, Packages-LillistCore-Sources-LillistCore-Persistence, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistCore-Sources-LillistCore-Sync-chunk-2, Packages-LillistUI-Sources-LillistUI-Components-chunk-1, Packages-LillistUI-Sources-LillistUI-DragReorder, Packages-LillistUI-Sources-LillistUI-Recurrence]
generator: cartographer/4
baseline: 99321d774840d17affd02fe2ac63b01b3d8cbec3
---

# Module: Packages/LillistCore/Sources/LillistCore/Sync (chunk 1)

## Purpose

This module is the sync-mode state machine and destructive-operation orchestrator for Lillist's Core Data / CloudKit layer. It owns every transition between localOnly and iCloudSync modes (MigrationCoordinator), local-store reset-and-redownload recovery (DataStoreResetService), CloudKit error classification and severity triage (CloudKitErrorClassifier), CloudKit event bridging into testable async streams (CloudKitEventBridge), sync-mode persistence (SyncModeStore), extension/CLI startup gate (MigrationGate), and sync-pause reason classification (PauseReasonClassifier). Without it, the app has no safe way to toggle iCloud sync, recover from a corrupt store, or surface intelligible CloudKit errors to the UI.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AccountStateMonitor` | actor | `Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift:23` | Callers subscribe via `stateStream` (replays current state on subscription) or call `refresh()` to poll CKContainer; actor isolation serializes all state mutations. |
| `AccountStatusProviding` | protocol | `Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift:5` | Conformers provide `accountStatus() async throws -> CKAccountStatus`; injected into `AccountStateMonitor` so tests control CloudKit responses without live network. |
| `CloudKitAccountStatusProvider` | struct | `Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift:10` | Production `AccountStatusProviding` that delegates directly to the held `CKContainer`; the `container` property is read-accessible for inspection by callers. |
| `CloudKitEraseSummary` | struct | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitZoneEraser.swift:6` | Carries the list of `CKRecordZone.ID` values deleted in one `eraseManagedZones` call; `count` is the number of zones removed. |
| `CloudKitErrorClassifier` | enum | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitErrorClassifier.swift:26` | Namespace of static classifiers; `classify(_:)` deterministically maps any `Error` to the `LillistError` taxonomy without retaining the original error object. |
| `CloudKitEventBridge` | actor | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift:42` | Actor that bridges `NSPersistentCloudKitContainer.eventChangedNotification` into a testable `AsyncStream`; attach to a live container with `attach(to:)` or inject events via `recordEvent(_:)` in tests; no initial-value replay on subscription. |
| `CloudKitSyncEvent` | struct | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift:11` | Sendable, Equatable snapshot of one CloudKit sync operation; `started == true` when `endedAt == nil`; `error` is pre-classified through `LillistError` taxonomy. |
| `CloudKitZoneEraser` | protocol | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitZoneEraser.swift:24` | Conformers delete all Core Data–managed CloudKit zones in one call; `progress` receives fractional progress 0–1; the caller (`MigrationCoordinator`) treats any thrown error as a hard failure. |
| `ConstantNetworkReachability` | struct | `Packages/LillistCore/Sources/LillistCore/Sync/PauseReasonClassifier.swift:15` | Returns the fixed `reachable` Bool from `init` for any `isReachable()` call; used in tests and truth-table stubs to control pause-reason evaluation without live network. |
| `DataStoreResetService` | class | `Packages/LillistCore/Sources/LillistCore/Sync/DataStoreResetService.swift:27` | `@MainActor` service exposing `resetAllData()`; reuses MigrationCoordinator's building blocks but does NOT touch the `MigrationJournal`; reentrancy-guarded (a second call while one is running throws immediately). |
| `Decision` | enum | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationGate.swift:10` | Two cases: `.proceed(mode:)` signals safe to open the store with the given `SyncMode`; `.abort(message:)` signals a migration is in flight with a user-facing message. |
| `DisableStrategy` | enum | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift:14` | Two cases (`syncFirst`, `now`) controlling whether a disable-sync migration waits for a final sync before disconnecting; passed to `MigrationCoordinator.beginDisable`. |
| `EnableDirection` | enum | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift:6` | Two cases (`replaceICloud`, `replaceLocal`) determining which data wins in the enable-sync transition; passed to `MigrationCoordinator.beginEnable`. |
| `EventType` | enum | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift:12` | Three cases mirroring `NSPersistentCloudKitContainer.Event.EventType` (setup, import, export); `@unknown default` in `translate` collapses unrecognized Apple-added cases to `.setup`. |
| `FileMigrationJournalStore` | struct | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournalStore.swift:18` | Writes with `Data.write(to:options:.atomic)` (rename-install) so cross-process readers never observe a partial file; the App Group path is `<container>/Lillist/migration.json`; returns `.idle` when absent or empty. |
| `GatedPersistenceResolver` | struct | `Packages/LillistCore/Sources/LillistCore/Sync/GatedPersistenceResolver.swift:21` | Gate-aware factory for the App Group on-disk persistence; throws `LillistError.storeUnavailable` when a migration is in flight; production `init?(appGroupID:)` is failable (nil when App Group container is unreachable). |
| `InMemoryMigrationJournalStore` | class | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournalStore.swift:70` | Thread-safe via `NSLock`; `@unchecked Sendable`; intended for unit tests; `clear()` resets to `.idle`; always succeeds (no I/O). |
| `LiveCloudKitZoneEraser` | struct | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitZoneEraserImpl.swift:21` | Production `CloudKitZoneEraser` that resolves `CKContainer(identifier:)`, enumerates all non-default custom zones, filters to Core Data–managed zones, and deletes each; errors propagate to the caller. |
| `MigrationCoordinator` | class | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift:39` | `@MainActor` state machine for sync-mode migrations; emits `MigrationPhase` events via `progressStream`; reentrancy-guarded at both the persisted-journal and in-process-flag levels; callers use `beginEnable`/`beginDisable`/`resumeOrRecover`/`restoreFromBackup`. |
| `MigrationGate` | struct | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationGate.swift:9` | Evaluates journal + modeStore to produce a `Decision`; `resolveStoreConfiguration` wraps it into a usable `StoreConfiguration` or throws; headless callers abort on any non-idle journal regardless of staleness. |
| `MigrationJournal` | struct | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournal.swift:40` | Durable record of an in-progress migration; `isInFlight` is `state != .idle`; `quarantineFolderName` ties recovery to a specific archive; custom `Codable` handles legacy `quarantineBackupID` with tolerant decode and no forward write. |
| `MigrationJournalStore` | protocol | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournalStore.swift:9` | Three synchronous methods — `read()`, `write(_:)`, `clear()` — all throwing; implementations must guarantee atomic writes so cross-process readers always see complete state. |
| `ModeTransitionOp` | enum | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournal.swift:6` | Four cases encoding the four possible sync-mode-change directions; raw `String` values are stable storage literals in the journal JSON — renaming requires a migration. |
| `NetworkReachabilityProviding` | protocol | `Packages/LillistCore/Sources/LillistCore/Sync/PauseReasonClassifier.swift:8` | Single `async` method `isReachable() -> Bool`; deliberately thin so the real NWPathMonitor implementation lives in app targets (NWPathMonitor does not compile cleanly into the strict-concurrency LillistCore source target). |
| `PauseReason` | enum | `Packages/LillistCore/Sources/LillistCore/Sync/PauseReason.swift:8` | Six-case Equatable/Sendable enum expressing why iCloud sync is paused; `nil` from `PauseReasonClassifier.currentReason()` means sync is active; priority order is accountChanged > noAccount > restricted > iCloudDriveDisabled > noNetwork. |
| `PauseReasonClassifier` | actor | `Packages/LillistCore/Sources/LillistCore/Sync/PauseReasonClassifier.swift:32` | Priority-ordered actor that maps account state + iCloud Drive flag + network reachability to a single `PauseReason?`; `nil` means sync is active; `setICloudDriveDisabled` lets app targets inject drive status without coupling LillistCore to NWPathMonitor. |
| `Severity` | enum | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitErrorClassifier.swift:52` | Two cases only — `.recoverable` (mirror retries without user action) or `.structural` (user or schema change required); Sendable and Equatable so it crosses actor boundaries and drives conditional logic safely. |
| `State` | enum | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournal.swift:41` | Eight states covering the migration phase sequence from `.idle` through `.failed`; `isInFlight` is `state != .idle`; `.failed` is terminal until the recovery sheet calls `journal.clear()`. |
| `SyncMode` | enum | `Packages/LillistCore/Sources/LillistCore/Sync/SyncMode.swift:14` | Two cases with stable raw-value strings (`"localOnly"`, `"iCloudSync"`) used in App Group UserDefaults and the journal JSON; `default` is `.iCloudSync`; renaming a case requires a storage migration. |
| `SyncModeStore` | actor | `Packages/LillistCore/Sources/LillistCore/Sync/SyncModeStore.swift:14` | Actor that persists `SyncMode` in App Group UserDefaults; `setMode` is idempotent (no-ops on same-value writes); `modeStream` replays the current value on subscription; UserDefaults is the sole source of truth. |
| `accountStatus` | func | `Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift:6` | Protocol requirement: returns the current `CKAccountStatus`; throws on network or account-query failures; must be `Sendable`-safe. |
| `accountStatus` | func | `Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift:13` | Delegates to `container.accountStatus()`; throws when CloudKit is unreachable or the account query fails; no caching. |
| `attach` | func | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift:89` | Registers a `NotificationCenter` observer on `eventChangedNotification` for the given container; the observer token is stored synchronously (not via Task) so a subsequent `detach()` cannot race past a deferred write and leak the observer. |
| `beginDisable` | func | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift:140` | Maps `DisableStrategy` to a `ModeTransitionOp` and runs the migration toward `.localOnly`; throws on failure, leaving the journal in `.failed` for the recovery sheet. |
| `beginEnable` | func | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift:133` | Maps `EnableDirection` to a `ModeTransitionOp` and runs the migration toward `.iCloudSync`; throws on failure, leaving the journal in `.failed` for the recovery sheet. |
| `classify` | func | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitErrorClassifier.swift:27` | Maps any `Error` to a `LillistError`; quotaExceeded, requestRateLimited, serverRejectedRequest, zoneBusy, and partialFailure are special-cased; all other codes collapse to `.syncFailure(underlying:)`. |
| `clear` | func | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournalStore.swift:12` | Protocol requirement: removes the journal, restoring the no-migration-in-flight state; throws on I/O failure. |
| `clear` | func | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournalStore.swift:59` | `FileMigrationJournalStore` impl: removes the file if it exists; silently no-ops when absent; throws on `FileManager` removal failure. |
| `clear` | func | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournalStore.swift:90` | `InMemoryMigrationJournalStore` impl: resets `current` to `.idle` by delegating to `write(.idle)` under the lock; always succeeds. |
| `currentMode` | func | `Packages/LillistCore/Sources/LillistCore/Sync/SyncModeStore.swift:30` | Returns the persisted mode or `.default` (`.iCloudSync`) when absent; synchronous; actor-isolated on `SyncModeStore`. |
| `currentReason` | func | `Packages/LillistCore/Sources/LillistCore/Sync/PauseReasonClassifier.swift:58` | Reads account state from `AccountStateMonitor`, applies iCloudDriveDisabled, then checks network reachability in priority order; returns the highest-priority active pause reason or `nil`; never throws. |
| `detach` | func | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift:52` | Removes the `NotificationCenter` observer if one is registered; idempotent; safe to call without a prior `attach(to:)`. |
| `encode` | func | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournal.swift:109` | Custom encoder that writes `quarantineFolderName` but intentionally omits `quarantineBackupID`, so journals decoded from pre-hardening builds are not re-written with the old field on the next save. |
| `eraseManagedZones` | func | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitZoneEraser.swift:25` | Deletes all `com.apple.coredata.cloudkit.zone`-prefixed zones in the named container's private database; `progress` is called as each zone is deleted; returns a summary of deleted zone IDs. |
| `eraseManagedZones` | func | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitZoneEraserImpl.swift:24` | Fetches all non-default custom zones via `allRecordZones()`, filters to the `com.apple.coredata.cloudkit.zone` prefix, deletes each in sequence, and reports per-zone fractional progress; throws on any CK error. |
| `evaluate` | func | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationGate.swift:27` | Reads the journal (treating read errors as `.idle`); returns `.abort` when non-idle, else `.proceed(mode:)` with the current persisted mode. |
| `isReachable` | func | `Packages/LillistCore/Sources/LillistCore/Sync/PauseReasonClassifier.swift:10` | Protocol requirement: returns `true` when a usable internet path is available; `async` to accommodate NWPathMonitor's async path lookup. |
| `isReachable` | func | `Packages/LillistCore/Sources/LillistCore/Sync/PauseReasonClassifier.swift:18` | `ConstantNetworkReachability` impl: returns the `reachable` constant from `init`; never suspends. |
| `isStale` | func | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournal.swift:147` | Returns `false` for `.idle`; measures staleness from `lastHeartbeatAt ?? startedAt`; a journal with no timestamp is always stale; threshold defaults to 600s (2× the quiesce ceiling). |
| `logRawError` | func | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift:147` | Logs raw CloudKit error codes and per-item partial-failure details at `.error` level before they are collapsed into `LillistError`; only codes and CloudKit-generated descriptions are logged, never user-authored content. |
| `makePersistence` | func | `Packages/LillistCore/Sources/LillistCore/Sync/GatedPersistenceResolver.swift:59` | Resolves gate + config, then calls the supplied `build` closure; lets tests substitute an in-memory controller while still exercising the full gate resolution path. |
| `makePersistence` | func | `Packages/LillistCore/Sources/LillistCore/Sync/GatedPersistenceResolver.swift:72` | Production convenience: resolves gate + config and constructs a `PersistenceController` with the given `transactionAuthor`; defaults to `localTransactionAuthor` so existing callers are unchanged. |
| `name` | func | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitErrorClassifier.swift:112` | Maps a raw `CKError.Code` integer to its symbolic name string for log messages and partial-failure summaries; unknown codes return `"code \(raw)"`. |
| `read` | func | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournalStore.swift:10` | Protocol requirement: returns the current journal or throws; when the backing store is absent, must return `.idle` (not throw). |
| `read` | func | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournalStore.swift:37` | `FileMigrationJournalStore` impl: deserializes JSON with ISO8601 dates; returns `.idle` when absent or empty; propagates `DecodingError` on corrupt data. |
| `read` | func | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournalStore.swift:78` | `InMemoryMigrationJournalStore` impl: acquires the lock, copies `current`, releases; always succeeds. |
| `recordEvent` | func | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift:81` | Pushes a `CloudKitSyncEvent` to all current stream subscribers; does not persist; the test seam for driving events without `NotificationCenter`. |
| `refresh` | func | `Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift:35` | Queries the provider, maps `CKAccountStatus` to `iCloudAccountState`, updates `currentState`, and pushes to all subscribers; throws if the underlying `accountStatus()` call throws. |
| `resetAllData` | func | `Packages/LillistCore/Sources/LillistCore/Sync/DataStoreResetService.swift:78` | Irreversible six-step wipe: cancel notifications, account-changed pre-flight, tear-down + quarantine backup, zone erase (iCloudSync only), rebuild empty store, quiesce wait; on zone-erase failure, re-attaches the original store before re-throwing. |
| `resetAndRedownload` | func | `Packages/LillistCore/Sources/LillistCore/Sync/DataStoreResetService.swift:93` | Destroys the local store and lets the rebuilt empty store re-import from the intact CloudKit zone; throws LillistError.storeUnavailable when not in iCloudSync mode (nothing to download in local-only mode). |
| `resolveStoreConfiguration` | func | `Packages/LillistCore/Sources/LillistCore/Sync/GatedPersistenceResolver.swift:51` | Consults `MigrationGate` and returns the App Group on-disk `StoreConfiguration`; throws `LillistError.storeUnavailable` when the gate aborts or the container is unreachable. |
| `resolveStoreConfiguration` | func | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationGate.swift:41` | Calls `evaluate()` and either throws `LillistError.storeUnavailable` on abort or returns the App Group on-disk `StoreConfiguration`; also throws when the container is unreachable. |
| `restoreFromBackup` | func | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift:170` | Reads the journal, resolves the recorded quarantine folder (falling back to the most-recent archive), restores the SQLite backup to `targetURL`, reverts `syncModeStore` to `previousMode`, reconfigures the host, and clears the journal; emits `.completed` on success. |
| `resumeOrRecover` | func | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift:151` | Reads the journal on launch; emits `.failed(reason:)` if the journal is non-idle; returns the current journal entry for the recovery sheet to inspect; does not modify the journal. |
| `setICloudDriveDisabled` | func | `Packages/LillistCore/Sources/LillistCore/Sync/PauseReasonClassifier.swift:52` | Sets the internal `iCloudDriveDisabled` flag; subsequent `currentReason()` calls see the new value; called by the app when it detects Drive is off for Lillist in Settings. |
| `setMode` | func | `Packages/LillistCore/Sources/LillistCore/Sync/SyncModeStore.swift:40` | Writes the new mode to UserDefaults and notifies all subscribers; no-ops when the new mode equals the current; callers include `MigrationCoordinator` and `restoreFromBackup`. |
| `severity` | func | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitErrorClassifier.swift:72` | Returns .recoverable for network blips, conflicts, rate-limit, and busy-zone codes that NSPersistentCloudKitContainer handles itself; a bare .partialFailure (no per-item dict) is always .recoverable; non-CloudKit errors are always .structural. |
| `simulateAccountChange` | func | `Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift:45` | Forces state to `.accountChanged` without querying CloudKit; intended for `CKAccountChanged` notification handlers and tests; never throws. |
| `translate` | func | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift:118` | Pure static function; converts one `NSPersistentCloudKitContainer.Event` to a `CloudKitSyncEvent`, classifying any error via `CloudKitErrorClassifier`; `@unknown default` event types collapse to `.setup`. |
| `write` | func | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournalStore.swift:11` | Protocol requirement: persists the journal atomically; implementations must guarantee cross-process readers see a complete file. |
| `write` | func | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournalStore.swift:49` | `FileMigrationJournalStore` impl: encodes to pretty-printed + sorted-keys JSON with ISO8601 dates and writes atomically; creates intermediate directories if needed; throws on encode or I/O failure. |
| `write` | func | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournalStore.swift:84` | `InMemoryMigrationJournalStore` impl: acquires the lock, sets `current` to the given journal, releases; always succeeds. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `CodingKeys` | enum | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournal.swift:84` | Custom `CodingKey` enum that includes `quarantineBackupID` for tolerant decoding of pre-hardening journals while ensuring the legacy key is never written forward; without it, decoding old journals would either crash or silently drop the migration record. (Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournal.swift:84-107) |
| `Scope` | enum | `Packages/LillistCore/Sources/LillistCore/Sync/DataStoreResetService.swift:65` | Guards two distinct reset semantics — `.everywhere` (erase CloudKit zone on every device) vs `.redownload` (leave zone intact, re-import) — without exposing the distinction to callers of the public API. The `.redownload` guard at DataStoreResetService.swift:124-128 prevents an accidental full wipe when the caller meant a local-only rebuild. |
| `breadcrumb` | func | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift:106` | Emits a named breadcrumb to the `BreadcrumbBuffer` at every phase boundary of the migration; awaited inline so phase crumbs land in operation order (not via a detached Task that could reorder them). (Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift:106-109) |
| `broadcast` | func | `Packages/LillistCore/Sources/LillistCore/Sync/SyncModeStore.swift:71` | Fans the new `SyncMode` to all registered continuations after a `setMode` write that actually changed the value; the sole notification path from a persisted mode change to stream subscribers. (Packages/LillistCore/Sources/LillistCore/Sync/SyncModeStore.swift:71-75) |
| `emit` | func | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift:125` | The sole write point for `MigrationCoordinator.progressContinuations`; fans the current `MigrationPhase` to every progress-sheet subscriber; without it the UI receives no live updates during migration. (Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift:125-129) |
| `publish` | func | `Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift:76` | The sole write point for `AccountStateMonitor.currentState`; fans out to every registered subscriber continuation; without it no account state change — including the notification-driven `.accountChanged` — reaches observers. (Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift:76-81) |
| `register` | func | `Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift:66` | Adds the continuation to the UUID dict and immediately replays `currentState` so late subscribers never miss the current value; called synchronously inside the actor-isolated `stateStream` getter to close the pre-subscription drop race. (Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift:66-70) |
| `register` | func | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift:110` | Adds the continuation to `CloudKitEventBridge`'s UUID dict; called synchronously inside the actor-isolated `eventStream` getter, closing the pre-subscription event-drop race documented in `.rca/sync-status-monitor-event-drop/`. (Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift:105-107) |
| `register` | func | `Packages/LillistCore/Sources/LillistCore/Sync/SyncModeStore.swift:63` | Adds a continuation to `SyncModeStore`'s UUID dict; called synchronously inside the actor-isolated `modeStream` getter before the initial-value yield, ensuring subscribers are registered before the stream is returned. (Packages/LillistCore/Sources/LillistCore/Sync/SyncModeStore.swift:63-65) |
| `runMigration` | func | `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift:193` | The 170-line core state machine that implements every sync-mode transition: two reentrancy guards, journal heartbeats at each phase, notification cancel before any destructive op, copy-before-erase ordering, account-changed pre-flight, optional CloudKit zone erase, quiesce wait, and notification restore on success. All correctness invariants live here. (Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift:193-365) |
| `unregister` | func | `Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift:72` | Removes a continuation from the dict on stream termination; prevents the continuation dict from growing unboundedly and stops yielding to dead subscribers. (Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift:72-74) |
| `unregister` | func | `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift:114` | Removes a continuation from `CloudKitEventBridge`'s dict on stream termination; prevents the dict from growing unboundedly. (Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift:109-111) |
| `unregister` | func | `Packages/LillistCore/Sources/LillistCore/Sync/SyncModeStore.swift:67` | Removes a continuation from `SyncModeStore`'s dict on stream termination; prevents the dict from growing unboundedly and avoids yielding to dead subscribers. (Packages/LillistCore/Sources/LillistCore/Sync/SyncModeStore.swift:67-69) |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.State -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.archive (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.currentMode -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.logRawError -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.makePersistence -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceController (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.performReset -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.performReset -> Packages-LillistCore-Sources-LillistCore-Notifications.cancelAllPending (writes)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.performReset -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-2.waitForQuiesce (reads)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.performReset -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1.settle (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.resetAndRedownload -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1.settle (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.resolveStoreConfiguration -> Packages-LillistCore-Sources-LillistCore-Persistence.appGroupOnDisk (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.restoreFromBackup -> Packages-LillistCore-Sources-LillistCore-Persistence.latestQuarantinedStore (reads)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.restoreFromBackup -> Packages-LillistCore-Sources-LillistCore-Persistence.quarantinedStore (reads)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.runMigration -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.runMigration -> Packages-LillistCore-Sources-LillistCore-Notifications.cancelAllPending (writes)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.runMigration -> Packages-LillistCore-Sources-LillistCore-Notifications.restoreSteadyState (writes)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.runMigration -> Packages-LillistCore-Sources-LillistCore-Persistence.copyStore (owns)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.runMigration -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-2.waitForQuiesce (reads)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.runMigration -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1.settle (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.simulateAccountChange -> Extensions-ShareExtension-iOS.next (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.translate -> Packages-LillistUI-Sources-LillistUI-DragReorder.depth (calls)`

## Type notes

MigrationCoordinator and DataStoreResetService are both @MainActor final classes — callers are SwiftUI views, and internal work hops onto embedded actors (MigrationCoordinator.swift:38, DataStoreResetService.swift:26). CloudKitEventBridge and AccountStateMonitor are actors; SyncModeStore and PauseReasonClassifier are actors. MigrationGate and CloudKitErrorClassifier are value types (struct / enum) with no mutable state — safe to pass freely. SyncMode raw values are stable storage literals appearing in App Group UserDefaults and the MigrationJournal JSON; renaming a case requires a migration (SyncMode.swift:13-14). CloudKitErrorClassifier.recoverableCodes is an internal Set<CKError.Code> (not public) that SyncStatusMonitor relies on indirectly via the .recoverable/.structural Severity enum (CloudKitErrorClassifier.swift:56-60). DataStoreResetService.isResetting and MigrationCoordinator.isMigrating are in-process reentrancy flags that complement the persisted journal guard; they must be set synchronously before the first suspension (DataStoreResetService.swift:41-42, MigrationCoordinator.swift:72).

## External deps

- CloudKit — imported
- CoreData — imported
- Foundation — imported
- os — imported

## Gotchas

MigrationCoordinator has two reentrancy guards: a journal-state check (synchronous before first await) and an `isMigrating` bool flag, because the journal isn't written until several awaits later — a second concurrent begin* call could slip through the first guard alone (MigrationCoordinator.swift:200-214). DataStoreResetService similarly has `isResetting` for the same reason (DataStoreResetService.swift:39-42). CloudKitErrorClassifier.severity treats a bare .partialFailure (no CKPartialErrorsByItemIDKey dict) as .recoverable, not .structural — a real diagnostic package showed a single bare partialFailure latching the red badge permanently before this fix (CloudKitErrorClassifier.swift:64-71). DataStoreResetService deliberately does NOT touch the MigrationJournal — a reset is not a mode transition, and the journal's previousMode invariant must not be disturbed (DataStoreResetService.swift:17-22).
