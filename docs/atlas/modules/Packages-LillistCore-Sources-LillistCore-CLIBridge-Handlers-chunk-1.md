---
module: "Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers (chunk 1)"
summary: "Stateless CLIBridge command handlers translating tokenized intents into store mutations and DTO reads"
read_when: CLI task command handlers
sources:
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/AddHandler.swift
    blob: ad229604e848b080167fb5143cbf2a2e69bb971b
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/AttachHandler.swift
    blob: eded77747680c5577ccefbde43cac1851d253c42
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/CountHandler.swift
    blob: 3672518f651534a19075e57c04c701921e79aaf3
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/DeleteHandler.swift
    blob: 458b4876b22e1d6a5ad985d13b826542cc8f94af
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/EditHandler.swift
    blob: 9c4f282ee4b580b7823d6c9d55da9fedb330bc2a
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/EvalHandler.swift
    blob: e6abcfafe279ea31ab920c4e231f72e8fd3a85ea
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/ExportHandler.swift
    blob: 73a3743f5f294b95a912be44ac2dbd7e653189ca
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/FiltersHandler.swift
    blob: 42221eb81deb1f2aee907240a0e6869fb8fdbc32
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/LinkHandler.swift
    blob: 7de8ab03712224c1854bef490a9ff9cfc00ef5a7
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/LsHandler.swift
    blob: 192754aeeda1b620b2bd60745e2b6dbe6876c9c3
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/MoveHandler.swift
    blob: 406f775d8b674f480531ea7ccfe3add93fd56302
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/NoteHandler.swift
    blob: 2636c60994789aae317319f897cd5d595b118332
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/NudgeHandler.swift
    blob: c64410299f77fdbf3716634b151aeef057e2880b
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/PinHandler.swift
    blob: 845931cf4fbe1add526c17176e2825d59c79e774
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/PurgeHandler.swift
    blob: 946f138edf9a34b1ea75996454db62a4d885993c
references_modules: [Packages-LillistCore-Sources-LillistCore-CLIBridge-misc, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistCore-Sources-LillistCore-Notifications, Packages-LillistCore-Sources-LillistCore-Rules, Packages-LillistCore-Sources-LillistCore-Model, Packages-LillistCore-Sources-LillistCore-ManagedObjects, Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistCore-Sources-LillistCore-Export, Packages-LillistCore-Sources-LillistCore-Persistence, Packages-LillistCore-Sources-LillistCore-Diagnostics, Packages-LillistCore-Sources-LillistCore-misc]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
---

# Module: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers (chunk 1)

## Purpose

The verb layer of the CLI/App-Intent surface: one stateless `enum` per command,
each a `CLIBridge` extension with `static func run`. Handlers translate string
tokens (task references, dates, statuses) into `Resolver`/`DateParsing` lookups,
drive the appropriate store, and return value-type DTOs or UUIDs — never Core
Data objects. They are the single point where out-of-process callers (the
`lillist` CLI and the Shortcuts App-Intents extension) reach `LillistCore`, so
the same parsing and resolution rules converge regardless of entry point. If
this layer vanished, both the CLI and Shortcuts would lose every task verb.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AddHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/AddHandler.swift:4` | `run` creates a task (tags/dates/status/parent), returns its UUID |
| `AddHandler.status` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/AddHandler.swift:77` | Maps a status token to `Status?`; nil for unknown tokens |
| `AttachHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/AttachHandler.swift:4` | `run` attaches files to a resolved task; returns attachment UUIDs |
| `CountHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/CountHandler.swift:4` | `run` returns the count of records matching flags/saved filter |
| `DeleteHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/DeleteHandler.swift:4` | `run` soft-deletes the resolved task (recoverable trash) |
| `EditHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/EditHandler.swift:4` | `run` patches title/notes/start/deadline on a resolved task |
| `EvalHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/EvalHandler.swift:5` | `run` evaluates ad-hoc predicate JSON; returns matching `TaskRecord`s |
| `ExportHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/ExportHandler.swift:4` | `run` writes a full export to a directory via `Exporter` |
| `FiltersHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/FiltersHandler.swift:4` | `list`/`show`/`run`/`save`/`delete` over saved smart filters |
| `LinkHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/LinkHandler.swift:4` | `run` validates a URL, creates a link attachment, best-effort unfurls |
| `LsHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/LsHandler.swift:5` | `run` returns sorted `TaskRecord`s for flags/saved filter |
| `LsHandler.fetchAllNonTrashedRecords` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/LsHandler.swift:38` | Returns all (optionally trashed) records; reused by other handlers |
| `MoveHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/MoveHandler.swift:4` | `run` reparents a task to another task or to root (`--root`) |
| `NoteHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/NoteHandler.swift:4` | `run` appends a journal note; rejects empty bodies; returns note UUID |
| `NudgeHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/NudgeHandler.swift:4` | `run` persists a nudge `NotificationSpec`; does not schedule it |
| `PinHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/PinHandler.swift:4` | `pin`/`unpin` set the resolved task's pinned flag |
| `PurgeHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/PurgeHandler.swift:4` | `run` hard-deletes the resolved task (irreversible) |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `LsHandler.record` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/LsHandler.swift:52` | Single map from `LillistTask` MO to `TaskRecord` DTO; reused by `EvalHandler` |
| `LsHandler.sort` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/LsHandler.swift:73` | Centralizes `SortField` ordering for every list/filter read |
| `AddHandler.firstTagWithName` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/AddHandler.swift:91` | Case/whitespace-insensitive tag tree walk so CLI and Quick Capture share a tag |
| `PinHandler.setPinned` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/PinHandler.swift:11` | Shared resolve+update body behind `pin`/`unpin` |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.AddHandler -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.CLIBridge (extends)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.AddHandler -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.Resolver (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.AddHandler -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.DateParsing (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.AddHandler -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.AddHandler -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TagStore (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.AddHandler -> Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticSink (writes)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.AttachHandler -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.AttachmentStore (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.CountHandler -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.LsHandler (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.EvalHandler -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.LsHandler (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.FiltersHandler -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.LsHandler (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.LsHandler -> Packages-LillistCore-Sources-LillistCore-Rules.NSPredicateCompiler (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.LsHandler -> Packages-LillistCore-Sources-LillistCore-Rules.PredicateGroup (reads)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.LsHandler -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SmartFilterStore (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.LsHandler -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.LillistTask (reads)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.LsHandler -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (reads)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.LsHandler -> Packages-LillistCore-Sources-LillistCore-Model.SortField (reads)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.LinkHandler -> Packages-LillistCore-Sources-LillistCore-LinkPreview.URLPreviewPolicy (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.LinkHandler -> Packages-LillistCore-Sources-LillistCore-LinkPreview.LinkPreviewUnfurler (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.NoteHandler -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.JournalStore (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.NudgeHandler -> Packages-LillistCore-Sources-LillistCore-Notifications.NotificationSpecStore (writes)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.ExportHandler -> Packages-LillistCore-Sources-LillistCore-Export.Exporter (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.ExportHandler -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.PreferencesStore (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.AddHandler -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceController (reads)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.AddHandler -> Packages-LillistCore-Sources-LillistCore-misc.LillistError (emits)`

## Type notes

Every handler is a caseless `public enum` extending `CLIBridge` with only
`static` members — they hold no state and are never instantiated; the caller
supplies a `PersistenceController` (and, where time matters, `now`/`calendar`)
per call. Stores are constructed fresh inside each `run`, so handlers own no
lifecycle. `EvalHandler` and `LsHandler` build the `NSPredicate` *inside*
`context.perform` because `NSPredicate` is not `Sendable` and cannot cross into
the closure; `PredicateGroup` is `Sendable` and is captured instead
(`Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/LsHandler.swift:24`).
`NudgeHandler` deliberately persists a spec without owning a scheduler — a
short-lived offline process never schedules notifications; the running app
reconciles later (`Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/NudgeHandler.swift:7`).

## External deps

- Foundation — `URL`, `Data`, `FileManager`, `JSONDecoder`, `Calendar`, `Date`
- CoreData — `NSFetchRequest`/`NSPredicate` for the `LsHandler`/`EvalHandler` fetches

## Gotchas

- `AddHandler.firstTagWithName` matches `TagStore.findOrCreate` (case/whitespace-insensitive) so Quick Capture, CLI, and App-Intent paths converge on one tag (`Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/AddHandler.swift:87`).
- `LinkHandler` enforces the SSRF ingest guard before any attachment row is created — non-http(s)/private/loopback hosts are rejected (`Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/LinkHandler.swift:15`).
