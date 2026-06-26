---
module: Packages/LillistCore/Sources/LillistCore/Backup
summary: "Live incremental backup package + daily zip snapshots + schema-gated destructive restore for all LillistCore data."
read_when: "Touching backup or restore logic"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/Backup/BackupPackageReader.swift
    blob: f0cebd445e82ac1c260ce56584ae66761ad7c667
  - path: Packages/LillistCore/Sources/LillistCore/Backup/BackupRecordProjector.swift
    blob: 873e36bb52c775e52ee8c97ee6adc970549ed9c9
  - path: Packages/LillistCore/Sources/LillistCore/Backup/BackupRestoreService.swift
    blob: 8c54f2f5444a6cc6c6a18192285f1877a83766f8
  - path: Packages/LillistCore/Sources/LillistCore/Backup/BackupSchema.swift
    blob: 21bcb00644785853c35f98bf8418b6d058744cc1
  - path: Packages/LillistCore/Sources/LillistCore/Backup/BackupSnapshotManager.swift
    blob: 7110e2368f0dfe184eaf3ef156d6088dc3fcb13d
  - path: Packages/LillistCore/Sources/LillistCore/Backup/CloudKitSchema.swift
    blob: 9625e1fb0287adeafd7ce71748890845970bc08a
  - path: Packages/LillistCore/Sources/LillistCore/Backup/LocalBackupCoordinator.swift
    blob: 77048a03279c866c5b2c49dbd84c90081c4e9fae
  - path: Packages/LillistCore/Sources/LillistCore/Backup/TaskBackupStore.swift
    blob: 24ef5a52b17dd6e1c32c83455fd53a119e396b18
references_modules: [Extensions-ShortcutsActions-Entities, Packages-LillistCore-Sources-LillistCore-Diagnostics, Packages-LillistCore-Sources-LillistCore-Export, Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistCore-Sources-LillistCore-Persistence, Packages-LillistUI-Sources-LillistUI-Components-chunk-1, Packages-LillistUI-Sources-LillistUI-Recurrence]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistCore/Sources/LillistCore/Backup

## Purpose

This module maintains a live, incremental filesystem mirror of every LillistTask and its owned journal entries, attachments, and sidecars (tags, preferences) in a structured package directory written by TaskBackupStore and kept current by LocalBackupCoordinator via NSManagedObjectContextDidSave and NSPersistentStoreRemoteChange observation. BackupSnapshotManager rolls that package into daily timestamped zip files for point-in-time recovery, and BackupRestoreService provides a schema-gated destructive restore path that wipes local and iCloud data before reimporting a package or snapshot. Without this module, a CloudKit zone deletion or accidental corruption would be unrecoverable.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `BackupDataResetting` | protocol | `Packages/LillistCore/Sources/LillistCore/Backup/BackupRestoreService.swift:7` | @MainActor-isolated — resetAllData() must wipe both local Core Data store and iCloud zone; tests may inject a fake conformer to avoid touching real CloudKit. |
| `BackupPackageReader` | struct | `Packages/LillistCore/Sources/LillistCore/Backup/BackupPackageReader.swift:7` | Read-only decoder for a backup package directory; initialized with a root URL and exposes readManifest, readTaskRecords, and assembleDocument — all are safe to call from any context. |
| `BackupPackageSchema` | enum | `Packages/LillistCore/Sources/LillistCore/Backup/BackupSchema.swift:10` | Namespace for on-disk package layout constants and two Codable types; version describes the directory/file layout only — distinct from ExportSchema.version and CloudKitSchema.currentVersion. |
| `BackupRecordProjector` | enum | `Packages/LillistCore/Sources/LillistCore/Backup/BackupRecordProjector.swift:13` | Namespace of pure static functions mapping Core Data managed objects into ExportSchema DTOs; every function must be called inside the owning context's perform block — no managed objects escape. |
| `BackupRestoreService` | class | `Packages/LillistCore/Sources/LillistCore/Backup/BackupRestoreService.swift:21` | @MainActor orchestrator for destructive restore; callers must call preflight first to obtain a Preflight, check isCompatible, and then call restore — which wipes all data before reimporting. |
| `BackupSnapshotManager` | struct | `Packages/LillistCore/Sources/LillistCore/Backup/BackupSnapshotManager.swift:12` | Sendable value type for creating, listing, and pruning timestamped zip snapshots; clock is injectable for testing; snapshots are standard zips the user can open anywhere. |
| `CloudKitSchema` | enum | `Packages/LillistCore/Sources/LillistCore/Backup/CloudKitSchema.swift:20` | Single-constant namespace; currentVersion is the CloudKit record schema version this build writes and the restore gate checks — bump only when the LillistTask CloudKit record shape changes in a backup-incompatible way. |
| `DataStoreResetService` | extension | `Packages/LillistCore/Sources/LillistCore/Backup/BackupRestoreService.swift:11` | Retroactive conformance of DataStoreResetService to BackupDataResetting; no added logic — the existing resetAllData() implementation satisfies the protocol requirement. |
| `LocalBackupCoordinator` | class | `Packages/LillistCore/Sources/LillistCore/Backup/LocalBackupCoordinator.swift:29` | @unchecked Sendable coordinator; callers call bootstrapAtLaunch() once at app start and start()/stop() for lifecycle management — all backup operations are best-effort and never surface errors to mutation callers. |
| `LocalChange` | struct | `Packages/LillistCore/Sources/LillistCore/Backup/LocalBackupCoordinator.swift:117` | Sendable snapshot of one Core Data save's task-relevant changes — UUID sets for upsert/delete and a sidecarsDirty flag; extracted synchronously on the context queue before any async hop. |
| `Manifest` | struct | `Packages/LillistCore/Sources/LillistCore/Backup/BackupSchema.swift:44` | Package-level summary written to manifest.json on every update; cloudKitSchemaVersion lets the restore preflight gate compatibility without scanning every per-task file. |
| `PendingAsset` | struct | `Packages/LillistCore/Sources/LillistCore/Backup/TaskBackupStore.swift:28` | Sendable value carrying one attachment blob's filename and bytes for staging under assets/; filename must match the AttachmentDTO.dataPath tail written by BackupRecordProjector.assetFilename. |
| `Preflight` | struct | `Packages/LillistCore/Sources/LillistCore/Backup/BackupRestoreService.swift:47` | Sendable, equatable report of a backup's schema version and task count; isCompatible is the boolean gate — restore must not proceed when false. |
| `RestoreSource` | enum | `Packages/LillistCore/Sources/LillistCore/Backup/BackupRestoreService.swift:40` | Discriminates .livePackage (the always-current file package) from .snapshotZip(URL) (a specific point-in-time zip); determines how BackupRestoreService resolves the reader and whether a temp directory is created. |
| `SnapshotInfo` | struct | `Packages/LillistCore/Sources/LillistCore/Backup/BackupSnapshotManager.swift:23` | Metadata for one snapshot file — URL, creation date parsed from the filename, and byte size; createdAt falls back to file modification date when the filename cannot be parsed. |
| `TaskBackupRecord` | struct | `Packages/LillistCore/Sources/LillistCore/Backup/BackupSchema.swift:17` | Self-contained per-task file record: the task DTO plus its owned journal entries and attachment metadata; cloudKitSchemaVersion is the value the restore gate compares against the current build. |
| `TaskBackupStore` | actor | `Packages/LillistCore/Sources/LillistCore/Backup/TaskBackupStore.swift:19` | Actor that serializes all disk mutations to the package directory; callers pass Sendable value types — never managed objects — so the Core Data context queue is never blocked on disk I/O. |
| `assembleDocument` | func | `Packages/LillistCore/Sources/LillistCore/Backup/BackupPackageReader.swift:58` | Returns a fully assembled ExportSchema.Document from the package; attachment bytes are not inlined — they remain on disk under assetsDirectory for the importer to consume. |
| `assetFilename` | func | `Packages/LillistCore/Sources/LillistCore/Backup/BackupRecordProjector.swift:17` | Returns a stable, UUID-deduped filename for an attachment blob under assets/; identical to the historical Exporter naming so existing asset paths are unchanged across package versions. |
| `attachmentDTO` | func | `Packages/LillistCore/Sources/LillistCore/Backup/BackupRecordProjector.swift:73` | Returns the DTO plus optionally the raw bytes to write under assets/; dto.dataPath is set only when the attachment carries binary data — link-preview-only attachments return nil bytes. |
| `bootstrapAtLaunch` | func | `Packages/LillistCore/Sources/LillistCore/Backup/LocalBackupCoordinator.swift:59` | One-call launch entry: starts observers, seeds the package if it has no task files, and rolls a daily snapshot if due; all steps are best-effort — backup must never block app launch. |
| `cleanup` | func | `Packages/LillistCore/Sources/LillistCore/Backup/BackupRestoreService.swift:106` | Deletes the temporary directory created for a snapshot-zip restore; no-op when tempDirectory is nil (live package path); always called via defer so cleanup is guaranteed. |
| `createSnapshot` | func | `Packages/LillistCore/Sources/LillistCore/Backup/BackupSnapshotManager.swift:54` | Zips packageDirectory to snapshotsDirectory/<ISO8601>.zip and prunes old snapshots to retentionCount (14); returns the new snapshot URL. |
| `createSnapshotIfDue` | func | `Packages/LillistCore/Sources/LillistCore/Backup/BackupSnapshotManager.swift:72` | Idempotent wrapper — creates a snapshot only when isSnapshotDue() is true; returns nil when nothing was due. |
| `date` | func | `Packages/LillistCore/Sources/LillistCore/Backup/BackupSnapshotManager.swift:131` | Parses the ISO-8601 timestamp encoded in a snapshot filename back to a Date; returns nil for filenames that do not conform to the snapshotFilename format. |
| `extractChange` | func | `Packages/LillistCore/Sources/LillistCore/Backup/LocalBackupCoordinator.swift:127` | Projects NSManagedObject change sets from a did-save notification into a Sendable LocalChange synchronously on the posting context queue; only reads id (UUID attribute) and entity names — never faults other attributes. |
| `isEmpty` | func | `Packages/LillistCore/Sources/LillistCore/Backup/TaskBackupStore.swift:74` | Returns true when the tasks/ directory contains no .json files; used to decide whether a first-run seed via reconcileFull is needed. |
| `isSnapshotDue` | func | `Packages/LillistCore/Sources/LillistCore/Backup/BackupSnapshotManager.swift:46` | Returns true when no snapshot exists yet or the newest is at least snapshotInterval (24h) old; uses the injected clock so tests can control time. |
| `journalEntryDTO` | func | `Packages/LillistCore/Sources/LillistCore/Backup/BackupRecordProjector.swift:56` | Projects a JournalEntry managed object into its DTO; all fields are value-copied; must be called inside the owning context's perform block. |
| `listSnapshots` | func | `Packages/LillistCore/Sources/LillistCore/Backup/BackupSnapshotManager.swift:78` | Returns all .zip files in snapshotsDirectory as SnapshotInfo sorted newest-first; returns an empty array when the directory is absent. |
| `preferencesDTO` | func | `Packages/LillistCore/Sources/LillistCore/Backup/BackupRecordProjector.swift:106` | Projects the value-type PreferencesStore.Prefs snapshot into the export DTO subset; only the fields present in ExportSchema.PreferencesDTO are carried. |
| `preflight` | func | `Packages/LillistCore/Sources/LillistCore/Backup/BackupRestoreService.swift:61` | Returns a Preflight report without mutating any data; callers must use this to show task count and gate the destructive restore confirmation UI. |
| `prepareDirectories` | func | `Packages/LillistCore/Sources/LillistCore/Backup/TaskBackupStore.swift:66` | Creates the tasks/ and assets/ subdirectories if absent; idempotent — safe to call before every write operation. |
| `processRemoteChange` | func | `Packages/LillistCore/Sources/LillistCore/Backup/LocalBackupCoordinator.swift:219` | Diffs persistent history for foreign-author changes, upserts changed tasks, and prunes package files for tasks deleted on other devices; advances the history token only after a successful apply. |
| `readManifest` | func | `Packages/LillistCore/Sources/LillistCore/Backup/BackupPackageReader.swift:33` | Returns the decoded Manifest or nil when the file is absent or empty; throws only on a malformed (non-empty, non-decodable) file. |
| `readTaskRecords` | func | `Packages/LillistCore/Sources/LillistCore/Backup/BackupPackageReader.swift:42` | Returns all TaskBackupRecords from tasks/*.json; returns an empty array when the directory is absent; order is filesystem-dependent — callers that care must sort downstream. |
| `reconcileFull` | func | `Packages/LillistCore/Sources/LillistCore/Backup/LocalBackupCoordinator.swift:322` | Rebuilds the entire package from the live store — clears and rewrites all task files, assets, sidecars, and manifest; use for first-run seed or to repair drift. |
| `remove` | func | `Packages/LillistCore/Sources/LillistCore/Backup/TaskBackupStore.swift:114` | Deletes each task's <id>.json plus any asset blobs it referenced; best-effort on asset removal — if the task file cannot be decoded, blobs are left behind without throwing. |
| `replaceAll` | func | `Packages/LillistCore/Sources/LillistCore/Backup/TaskBackupStore.swift:137` | Clears tasks/ and assets/ then rewrites the entire package with the provided records, assets, sidecars, and manifest; used for first-run seed and full drift repair. |
| `resetAllData` | func | `Packages/LillistCore/Sources/LillistCore/Backup/BackupRestoreService.swift:8` | @MainActor-isolated protocol requirement; implementing type must delete both the local Core Data store and the remote CloudKit zone and rebuild an empty container. |
| `restore` | func | `Packages/LillistCore/Sources/LillistCore/Backup/BackupRestoreService.swift:73` | Throws LillistError.schemaVersionMismatch if CloudKit schema versions differ (defense in depth — preflight should have gated this); on success the store holds exactly the backup's tasks, tags, journal entries, attachments, and preferences. |
| `runSnapshotIfDue` | func | `Packages/LillistCore/Sources/LillistCore/Backup/LocalBackupCoordinator.swift:68` | Best-effort async wrapper around createSnapshotIfDue; runs the zip in a detached Task so it never stalls the caller; no-op when no BackupSnapshotManager is configured. |
| `seedPackageIfEmpty` | func | `Packages/LillistCore/Sources/LillistCore/Backup/LocalBackupCoordinator.swift:316` | Idempotent first-run seed: calls reconcileFull only when the store has no task files; safe to call repeatedly. |
| `snapshotFilename` | func | `Packages/LillistCore/Sources/LillistCore/Backup/BackupSnapshotManager.swift:117` | Encodes a Date as a filesystem-safe ISO-8601 string with time colons replaced by hyphens (e.g. 2026-06-23T14-30-00Z.zip) so filenames sort chronologically. |
| `start` | func | `Packages/LillistCore/Sources/LillistCore/Backup/LocalBackupCoordinator.swift:76` | Installs NSManagedObjectContextDidSave and NSPersistentStoreRemoteChange observers; idempotent — repeated calls are guarded and do not install duplicate observers. |
| `stop` | func | `Packages/LillistCore/Sources/LillistCore/Backup/LocalBackupCoordinator.swift:104` | Removes both notification observers and nils the tokens; explicit call is required for deterministic test teardown in addition to deinit. |
| `tagDTO` | func | `Packages/LillistCore/Sources/LillistCore/Backup/BackupRecordProjector.swift:46` | Projects a Tag managed object into its DTO including parent ID and position; must be called inside the owning context's perform block. |
| `taskDTO` | func | `Packages/LillistCore/Sources/LillistCore/Backup/BackupRecordProjector.swift:21` | Projects a LillistTask into its DTO; tag IDs are sorted by UUID string for stable ordering; nil-safe via UUID()/empty-string defaults for missing optional fields. |
| `taskFileCount` | func | `Packages/LillistCore/Sources/LillistCore/Backup/TaskBackupStore.swift:79` | Returns the count of <id>.json files currently in tasks/; returns 0 when the directory is absent. |
| `taskFileIDs` | func | `Packages/LillistCore/Sources/LillistCore/Backup/TaskBackupStore.swift:86` | Returns the set of UUIDs derived from filenames in tasks/; used by the remote reconcile path to set-difference against the live store and prune files for tasks deleted on other devices. |
| `unzip` | func | `Packages/LillistCore/Sources/LillistCore/Backup/BackupSnapshotManager.swift:99` | Extracts a snapshot zip to destination with shouldKeepParent:false — entries land at the destination root yielding a ready-to-read package directory; creates destination if absent. |
| `upsert` | func | `Packages/LillistCore/Sources/LillistCore/Backup/TaskBackupStore.swift:100` | Writes or overwrites each task's <id>.json and stages attachment blobs under assets/ atomically (Data.write options: .atomic); a reader never sees a torn record. |
| `writeManifest` | func | `Packages/LillistCore/Sources/LillistCore/Backup/TaskBackupStore.swift:168` | Writes manifest.json atomically; callers must pass a fully constructed Manifest with current schema versions and task count. |
| `writeSidecars` | func | `Packages/LillistCore/Sources/LillistCore/Backup/TaskBackupStore.swift:160` | Writes tags.json and preferences.json atomically; both files are always written together to keep the sidecars consistent. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `dedupe` | func | `Packages/LillistCore/Sources/LillistCore/Backup/LocalBackupCoordinator.swift:180` | Deduplicates UUID arrays while preserving insertion order (LocalBackupCoordinator.swift:180-185); called on every upsert and delete batch before writing to prevent redundant writes when multiple child-object changes share the same parent task in one save notification. |
| `makeDecoder` | func | `Packages/LillistCore/Sources/LillistCore/Backup/BackupPackageReader.swift:26` | Configures ISO-8601 date decoding for every file the reader touches (manifest, task records, sidecars); used by both readManifest and the decoder in readTaskRecords (BackupPackageReader.swift:26-30). A wrong date strategy here would corrupt all date fields across the entire restore path. |
| `makeDecoder` | func | `Packages/LillistCore/Sources/LillistCore/Backup/TaskBackupStore.swift:56` | Configures ISO-8601 date decoding for task files during the remove path (TaskBackupStore.swift:56-60) — needed to decode a record and find its asset paths before deletion; if decoding fails assets are stranded. |
| `makeEncoder` | func | `Packages/LillistCore/Sources/LillistCore/Backup/TaskBackupStore.swift:49` | Sets the canonical on-disk format for all package files: prettyPrinted + sortedKeys + withoutEscapingSlashes + iso8601 (TaskBackupStore.swift:49-54); changes here silently alter file format for all package consumers without a schema version bump. |
| `preflight` | func | `Packages/LillistCore/Sources/LillistCore/Backup/BackupRestoreService.swift:123` | The single authoritative schema-gate implementation shared by both the public preflight and the defensive re-check inside restore (BackupRestoreService.swift:123-137). Centralizing it ensures both call sites can never drift apart, preserving the invariant that incompatible backups are always rejected. |
| `project` | func | `Packages/LillistCore/Sources/LillistCore/Backup/LocalBackupCoordinator.swift:392` | The single place where a live LillistTask managed object is materialized into a Sendable TaskBackupRecord plus attachment blobs (LocalBackupCoordinator.swift:392-423); all three write paths (local save, remote change, full reconcile) funnel through it, so correctness here is required by every backup update. |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-Backup.BackupPackageSchema -> Extensions-ShortcutsActions-Entities.entities (calls)`
- `Packages-LillistCore-Sources-LillistCore-Backup.DataStoreResetService -> Packages-LillistCore-Sources-LillistCore-Diagnostics.zip (calls)`
- `Packages-LillistCore-Sources-LillistCore-Backup.assembleDocument -> Packages-LillistCore-Sources-LillistCore-Export.Document (calls)`
- `Packages-LillistCore-Sources-LillistCore-Backup.attachmentDTO -> Packages-LillistCore-Sources-LillistCore-Export.AttachmentDTO (calls)`
- `Packages-LillistCore-Sources-LillistCore-Backup.date -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistCore-Sources-LillistCore-Backup.date -> Packages-LillistUI-Sources-LillistUI-Recurrence.index (calls)`
- `Packages-LillistCore-Sources-LillistCore-Backup.journalEntryDTO -> Packages-LillistCore-Sources-LillistCore-Export.JournalEntryDTO (calls)`
- `Packages-LillistCore-Sources-LillistCore-Backup.liveTaskIDs -> Packages-LillistCore-Sources-LillistCore-Persistence.makeBackgroundContext (reads)`
- `Packages-LillistCore-Sources-LillistCore-Backup.preferencesDTO -> Packages-LillistCore-Sources-LillistCore-Export.PreferencesDTO (calls)`
- `Packages-LillistCore-Sources-LillistCore-Backup.processRemoteChange -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1.closure (calls)`
- `Packages-LillistCore-Sources-LillistCore-Backup.projectRecords -> Packages-LillistCore-Sources-LillistCore-Persistence.makeBackgroundContext (reads)`
- `Packages-LillistCore-Sources-LillistCore-Backup.readPreferences -> Packages-LillistCore-Sources-LillistCore-Export.PreferencesDTO (reads)`
- `Packages-LillistCore-Sources-LillistCore-Backup.reconcileFull -> Packages-LillistCore-Sources-LillistCore-Persistence.makeBackgroundContext (reads)`
- `Packages-LillistCore-Sources-LillistCore-Backup.refreshSidecars -> Packages-LillistCore-Sources-LillistCore-Persistence.makeBackgroundContext (reads)`
- `Packages-LillistCore-Sources-LillistCore-Backup.resolveTaskIDs -> Packages-LillistCore-Sources-LillistCore-Persistence.makeBackgroundContext (reads)`
- `Packages-LillistCore-Sources-LillistCore-Backup.snapshotFilename -> Packages-LillistUI-Sources-LillistUI-Recurrence.index (calls)`
- `Packages-LillistCore-Sources-LillistCore-Backup.snapshotFilename -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Packages-LillistCore-Sources-LillistCore-Backup.updateManifest -> Packages-LillistCore-Sources-LillistCore-Export.PreferencesDTO (calls)`

## Type notes

TaskBackupStore (TaskBackupStore.swift:19) is an actor — all disk mutations are serialized on its executor so no two saves race the same <id>.json and a zip snapshot never captures a torn file. LocalBackupCoordinator (LocalBackupCoordinator.swift:29) is @unchecked Sendable: the only mutable state is two observer tokens touched on the main actor in start()/stop() (same justification as RemoteChangeReconciler). BackupRestoreService (BackupRestoreService.swift:21) is @MainActor because BackupDataResetting is @MainActor — the reset primitive drives SwiftUI-facing state. BackupPackageReader and BackupSnapshotManager are pure Sendable structs with no actor isolation; all their operations are synchronous. Three version constants exist in deliberate separation: BackupPackageSchema.version (directory layout), CloudKitSchema.currentVersion (CloudKit record shape, the restore gate), and ExportSchema.version (DTO contract) — CloudKitSchema.swift:9-16 documents the distinction explicitly.

## External deps

- CoreData — imported
- Foundation — imported
- ZIPFoundation — imported

## Gotchas

Three distinct version constants must never be conflated — CloudKitSchema.swift:9-16 documents all three explicitly: ExportSchema.version (DTO contract), BackupPackageSchema.version (directory layout), CloudKitSchema.currentVersion (CloudKit record shape / restore gate). assembleDocument falls back to Date() when no manifest exists (BackupPackageReader.swift:63) so pre-manifest packages silently report 'now' as the export timestamp. LocalBackupCoordinator.extractChange reads only id and entity names synchronously on the posting context queue (LocalBackupCoordinator.swift:86-87 comment) — accessing other attributes here is unsafe. createSnapshot passes shouldKeepParent: false (BackupSnapshotManager.swift:64) so the zip extracts as a flat package directory without an extra nesting level. TaskBackupStore.remove is best-effort on asset cleanup: if the task file cannot be decoded the blobs are left behind (TaskBackupStore.swift:119-130).
