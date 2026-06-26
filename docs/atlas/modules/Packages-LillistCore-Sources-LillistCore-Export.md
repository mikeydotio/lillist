---
module: Packages/LillistCore/Sources/LillistCore/Export
summary: "Versioned JSON backup/restore: Exporter writes lillist.json; Importer replays into Core Data."
read_when: "Touching JSON export/import format"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/Export/ExportSchema.swift
    blob: 129f8086721cee514e2898ac269f195e558b8937
  - path: Packages/LillistCore/Sources/LillistCore/Export/Exporter.swift
    blob: 74d6817a09767b5d689789a217c8c0038b62c287
  - path: Packages/LillistCore/Sources/LillistCore/Export/Importer.swift
    blob: 4946ca0dd73ac9dcac11d0a40df0cd06e20a1502
references_modules: [Packages-LillistCore-Sources-LillistCore-Backup, Packages-LillistCore-Sources-LillistCore-ManagedObjects, Packages-LillistCore-Sources-LillistCore-Persistence, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistCore/Sources/LillistCore/Export

## Purpose

The Export module is the portable backup/restore seam for Lillist: Exporter serializes all store content (tasks, tags, journal entries, attachments, preferences) into a versioned JSON bundle on disk; Importer reads that bundle back into Core Data under a configurable conflict policy. The schema namespace (ExportSchema) versions the interchange format and holds every DTO type, giving the pipeline a single place to manage backward compatibility. Without this module there is no user-controlled escape hatch from destructive sync-mode changes and no path to migrate data across reinstalls or devices.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AttachmentDTO` | struct | `Packages/LillistCore/Sources/LillistCore/Export/ExportSchema.swift:60` | Portable attachment record; `dataPath` is nil for link-preview attachments (no binary blob); `byteSize` is always present even when blob is absent. |
| `ConflictPolicy` | enum | `Packages/LillistCore/Sources/LillistCore/Export/Importer.swift:27` | Three-case policy governing UUID collision behavior; callers may rely on `recencyWins` using `modifiedAt ?? createdAt` with the incoming record winning when it is strictly newer. |
| `Document` | struct | `Packages/LillistCore/Sources/LillistCore/Export/ExportSchema.swift:7` | Top-level export container written as `lillist.json`; callers may rely on `version` being `ExportSchema.version` on export and forward-incompatible bundles being rejected by Importer before any store writes. |
| `ExportSchema` | enum | `Packages/LillistCore/Sources/LillistCore/Export/ExportSchema.swift:4` | Namespace for all export DTOs and the `version` constant (currently 1); callers may rely on `ExportSchema.version` as the canonical schema level for version-guard checks. |
| `ExportSchema` | extension | `Packages/LillistCore/Sources/LillistCore/Export/ExportSchema.swift:85` | Provides a backward-compatible `init(from:)` for TaskDTO; callers may rely on bundles lacking `schemaVersion` decoding cleanly with value 0 rather than throwing `keyNotFound`. |
| `Exporter` | class | `Packages/LillistCore/Sources/LillistCore/Export/Exporter.swift:4` | Async `@unchecked Sendable` serializer; callers may rely on `export(to:)` writing `lillist.json` + `assets/` under an empty directory and throwing `LillistError.validationFailed` on a non-empty target. |
| `ImportSummary` | struct | `Packages/LillistCore/Sources/LillistCore/Export/Importer.swift:33` | All-fields-zero-defaulted result value; `errors` contains absorbed per-row failure descriptions; the entire struct is only meaningful when `apply` returns without throwing. |
| `Importer` | actor | `Packages/LillistCore/Sources/LillistCore/Export/Importer.swift:20` | Actor owning the import pipeline; callers may rely on `importBundle` as the bundle-URL entry point and `apply` for in-memory document replay, both all-or-nothing against the store. |
| `JournalEntryDTO` | struct | `Packages/LillistCore/Sources/LillistCore/Export/ExportSchema.swift:50` | Portable journal entry; `taskID` may be nil (CloudKit delivery artifact); callers must not assume owner resolution succeeds — orphan entries are skipped by the importer. |
| `PendingAsset` | struct | `Packages/LillistCore/Sources/LillistCore/Export/Exporter.swift:47` | Internal staging value (local to buildDocument) that carries an attachment filename and bytes between the Core Data fetch phase and the disk-write phase; not addressable by external callers. |
| `PreferencesDTO` | struct | `Packages/LillistCore/Sources/LillistCore/Export/ExportSchema.swift:74` | Snapshot of user preferences at export time; all fields are value types; callers may rely on direct memberwise access with no optional fields. |
| `TagDTO` | struct | `Packages/LillistCore/Sources/LillistCore/Export/ExportSchema.swift:42` | Portable tag with optional `parentID`; parent-child wiring is deferred to a second pass in Importer.apply after all tag rows are inserted. |
| `TaskDTO` | struct | `Packages/LillistCore/Sources/LillistCore/Export/ExportSchema.swift:17` | Portable task value; `schemaVersion` defaults to 0 for pre-versioning bundles; `tagIDs` is a list of UUIDs resolved to Tag objects by the importer in a second pass. |
| `apply` | func | `Packages/LillistCore/Sources/LillistCore/Export/Importer.swift:101` | All-or-nothing import; callers may rely on the store being unchanged if this throws, and on ImportSummary being valid only when it returns normally; attachment rows require a non-nil `assetsDirectory`. |
| `export` | func | `Packages/LillistCore/Sources/LillistCore/Export/Exporter.swift:15` | Writes a complete snapshot to `dir`; callers may rely on `dir` being empty on entry (enforced), `lillist.json` being the last file written, and all attachment blobs landing under `assets/`. |
| `importBundle` | func | `Packages/LillistCore/Sources/LillistCore/Export/Importer.swift:73` | Decodes `lillist.json` from `bundleURL` using iso8601 dates and delegates to `apply`; rejects forward-incompatible bundles before any store writes. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `CodingKeys` | enum | `Packages/LillistCore/Sources/LillistCore/Export/ExportSchema.swift:86` | Guards backward compatibility for TaskDTO deserialization: by explicitly listing `schemaVersion` in CodingKeys and using `decodeIfPresent` in the custom `init(from:)`, bundles written before that field existed decode to 0 rather than throwing keyNotFound. Without it Swift's synthesized decoder would reject any pre-existing export bundle (ExportSchema.swift:86-116). |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-Export.Action -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.stampCurrentSchemaVersion (writes)`
- `Packages-LillistCore-Sources-LillistCore-Export.Action -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.fetchTag (calls)`
- `Packages-LillistCore-Sources-LillistCore-Export.PendingAsset -> Packages-LillistCore-Sources-LillistCore-Backup.attachmentDTO (calls)`
- `Packages-LillistCore-Sources-LillistCore-Export.PendingAsset -> Packages-LillistCore-Sources-LillistCore-Backup.journalEntryDTO (calls)`
- `Packages-LillistCore-Sources-LillistCore-Export.PendingAsset -> Packages-LillistCore-Sources-LillistCore-Backup.preferencesDTO (calls)`
- `Packages-LillistCore-Sources-LillistCore-Export.PendingAsset -> Packages-LillistCore-Sources-LillistCore-Backup.tagDTO (calls)`
- `Packages-LillistCore-Sources-LillistCore-Export.PendingAsset -> Packages-LillistCore-Sources-LillistCore-Backup.taskDTO (calls)`
- `Packages-LillistCore-Sources-LillistCore-Export.apply -> Packages-LillistCore-Sources-LillistCore-Persistence.makeBackgroundContext (reads)`
- `Packages-LillistCore-Sources-LillistCore-Export.apply -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.fetchTag (calls)`
- `Packages-LillistCore-Sources-LillistCore-Export.buildDocument -> Packages-LillistCore-Sources-LillistCore-Persistence.makeBackgroundContext (reads)`

## Type notes

Exporter is `@unchecked Sendable` (Exporter.swift:4) because it holds a PersistenceController reference; thread safety is manually ensured by keeping all Core Data work inside `ctx.perform` blocks. Importer is an `actor` (Importer.swift:20), giving it automatic isolation; its apply helpers are `nonisolated` (Importer.swift:289-401) so they can be called from inside the `ctx.perform` closure without re-crossing the actor boundary. ExportSchema.TaskDTO carries a `schemaVersion` field that defaults to 0 and uses a custom `init(from:)` with `decodeIfPresent` (ExportSchema.swift:116) so bundles written before that field existed decode without throwing. `apply` stages all rows and commits in a single `ctx.save()` (Importer.swift:268); on failure it calls `ctx.rollback()` and rethrows — the ImportSummary is discarded, leaving the store unchanged (Importer.swift:267-284). Attachment bytes are captured inside the `ctx.perform` fetch phase but written to disk outside it (Exporter.swift:89-93) to avoid file I/O while holding the Core Data context queue.

## External deps

- CoreData — imported
- Foundation — imported

## Gotchas

Exporter's two-phase attachment handling (bytes read inside `ctx.perform`, written to disk outside) is intentional and load-bearing — do not collapse into one phase (Exporter.swift:42-93, inline comment). `applyTask` stamps `stampCurrentSchemaVersion()` on every restored row rather than copying `dto.schemaVersion` (Importer.swift:334); this ensures restored data conforms to the current CloudKit field shape regardless of the bundle's recorded version. The `apply` doc comment explicitly warns that `ImportSummary.errors` and `*Skipped` counts are discarded on a `ctx.save()` throw and are only meaningful on a non-throwing return (Importer.swift:84-96). Orphan journal entries (taskID absent or unresolvable) are silently counted as skipped rather than errored, because CloudKit can deliver dangling relationships (Importer.swift:206-210).
