---
module: Packages/LillistCore/Sources/LillistCore/Export
summary: "Versioned JSON+assets backup bundle writer/reader for the full Core Data store"
read_when: "backup/restore + export"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/Export/ExportSchema.swift
    blob: 910872fc86a1d4636fd80e144664dbedcfbb3f2a
  - path: Packages/LillistCore/Sources/LillistCore/Export/Exporter.swift
    blob: c79c28caee95ab53be9d287223098c4ebc11defb
  - path: Packages/LillistCore/Sources/LillistCore/Export/Importer.swift
    blob: 35b5ecabbe116205844cab3557936a43eaf469a7
references_modules: [Packages-LillistCore-Sources-LillistCore-Persistence, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-ManagedObjects, Packages-LillistCore-Sources-LillistCore-misc]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
---

# Module: Packages/LillistCore/Sources/LillistCore/Export

## Purpose

Full-store backup and restore as a portable, versioned bundle: a `lillist.json`
document plus an `assets/` folder. `Exporter` serializes every entity (including
trashed rows) into value-type DTOs; `Importer` reads them back with a choice of
conflict policy. This is the manual-merge escape hatch the destructive sync-mode
swap deliberately omits, so it is the only path that round-trips the store across
devices or schema versions without going through CloudKit.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `Exporter` | class | `Packages/LillistCore/Sources/LillistCore/Export/Exporter.swift:4` | Writes a backup bundle; constructed with a persistence + preferences pair |
| `Exporter.export(to:)` | func | `Packages/LillistCore/Sources/LillistCore/Export/Exporter.swift:15` | Writes `lillist.json` + `assets/` under `dir`; `dir` must exist and be empty |
| `ExportSchema` | enum | `Packages/LillistCore/Sources/LillistCore/Export/ExportSchema.swift:4` | Namespace + `version` constant; bump `version` for incompatible changes |
| `ExportSchema.AttachmentDTO` | struct | `Packages/LillistCore/Sources/LillistCore/Export/ExportSchema.swift:54` | Attachment row; `dataPath` is relative under `assets/`, nil for link previews |
| `ExportSchema.Document` | struct | `Packages/LillistCore/Sources/LillistCore/Export/ExportSchema.swift:7` | Codable top-level bundle: version, tasks, tags, journal, attachments, prefs |
| `ExportSchema.JournalEntryDTO` | struct | `Packages/LillistCore/Sources/LillistCore/Export/ExportSchema.swift:44` | Journal row; `taskID` ties it to an owning task |
| `ExportSchema.PreferencesDTO` | struct | `Packages/LillistCore/Sources/LillistCore/Export/ExportSchema.swift:68` | Snapshot of device preferences carried in the bundle |
| `ExportSchema.TagDTO` | struct | `Packages/LillistCore/Sources/LillistCore/Export/ExportSchema.swift:36` | Tag row with optional `parentID` for hierarchy |
| `ExportSchema.TaskDTO` | struct | `Packages/LillistCore/Sources/LillistCore/Export/ExportSchema.swift:17` | Task row; `tagIDs`/`parentID` are UUID references resolved on import |
| `Importer` | actor | `Packages/LillistCore/Sources/LillistCore/Export/Importer.swift:19` | Reads a bundle back into the store; constructed with a persistence controller |
| `Importer.ConflictPolicy` | enum | `Packages/LillistCore/Sources/LillistCore/Export/Importer.swift:26` | `skipExisting` / `replaceExisting` / `recencyWins` |
| `Importer.ImportSummary` | struct | `Packages/LillistCore/Sources/LillistCore/Export/Importer.swift:32` | Per-entity inserted/updated/skipped counts plus `errors`; valid only on success |
| `Importer.apply(document:policy:)` | func | `Packages/LillistCore/Sources/LillistCore/Export/Importer.swift:96` | All-or-nothing apply of a decoded document; throws leave the store unchanged |
| `Importer.importBundle(at:conflictPolicy:)` | func | `Packages/LillistCore/Sources/LillistCore/Export/Importer.swift:72` | Decodes `lillist.json` under `bundleURL` then delegates to `apply` |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `Importer.decideAction` | func | `Packages/LillistCore/Sources/LillistCore/Export/Importer.swift:250` | Single place where a conflict policy becomes a skip/update; `recencyWins` compares `modifiedAt` then `createdAt` |
| `Exporter.buildDocument` | func | `Packages/LillistCore/Sources/LillistCore/Export/Exporter.swift:39` | Builds the `Document` and stages assets inside one `perform`; defines the read-then-write-outside-perform discipline |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-Export.Exporter -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceController (reads)`
- `Packages-LillistCore-Sources-LillistCore-Export.Exporter -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.PreferencesStore (reads)`
- `Packages-LillistCore-Sources-LillistCore-Export.Exporter -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.LillistTask (reads)`
- `Packages-LillistCore-Sources-LillistCore-Export.Exporter -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.Attachment (reads)`
- `Packages-LillistCore-Sources-LillistCore-Export.Exporter -> Packages-LillistCore-Sources-LillistCore-misc.LillistError (emits)`
- `Packages-LillistCore-Sources-LillistCore-Export.Importer -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceController (reads)`
- `Packages-LillistCore-Sources-LillistCore-Export.Importer -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.LillistTask (writes)`
- `Packages-LillistCore-Sources-LillistCore-Export.Importer -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.Tag (writes)`
- `Packages-LillistCore-Sources-LillistCore-Export.Importer -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.JournalEntry (writes)`
- `Packages-LillistCore-Sources-LillistCore-Export.Importer -> Packages-LillistCore-Sources-LillistCore-misc.LillistError (emits)`

## Type notes

DTOs are the module's boundary: no `NSManagedObject` crosses it. `Exporter` and the
`PendingAsset` helper read attachment bytes into value types *inside* `ctx.perform`,
then write files to disk *outside* it, so no file I/O holds the Core Data context
queue (`Packages/LillistCore/Sources/LillistCore/Export/Exporter.swift:43`).

`Importer` is an `actor`, but its apply/fetch helpers are `nonisolated` and touch
Core Data only through the passed `ctx`; the whole apply runs in one
background-context `perform` block (`Packages/LillistCore/Sources/LillistCore/Export/Importer.swift:107`).
Import is **all-or-nothing**: a single `ctx.save()` commits everything, and a throw
triggers `ctx.rollback()`, discarding staged rows *and* the `ImportSummary` —
`errors`/`*Skipped` are meaningful only on a successful return
(`Packages/LillistCore/Sources/LillistCore/Export/Importer.swift:96`).

Referential integrity is rebuilt in two passes: rows are inserted/updated keyed by
UUID, then `parent` links are wired once all rows exist
(`Packages/LillistCore/Sources/LillistCore/Export/Importer.swift:150`,
`Packages/LillistCore/Sources/LillistCore/Export/Importer.swift:185`). Journal
entries with a nil or unresolved `taskID` are skipped rather than orphaned
(`Packages/LillistCore/Sources/LillistCore/Export/Importer.swift:196`).

Forward-incompatible bundles (a newer `Document.version` than `ExportSchema.version`)
are rejected up front; equal and older bundles apply because every since-added DTO
field has a safe default (`Packages/LillistCore/Sources/LillistCore/Export/Importer.swift:101`).

## External deps

- Foundation — `JSONEncoder`/`JSONDecoder` with ISO-8601 dates; `FileManager` for bundle I/O
- CoreData — `NSFetchRequest`, background contexts, `perform`/`save`/`rollback`

## Gotchas

- Attachments are exported but NOT imported in this revision; copy-back is deferred (`Packages/LillistCore/Sources/LillistCore/Export/Importer.swift:16`).
- `recencyWins` on tags falls back to "incoming wins" because tags carry no `modifiedAt` (`Packages/LillistCore/Sources/LillistCore/Export/Importer.swift:131`).
- `apply` deliberately uses a background context, not `viewContext` — a Wave-4 seam flagged "do not revert" (`Packages/LillistCore/Sources/LillistCore/Export/Importer.swift:107`).
