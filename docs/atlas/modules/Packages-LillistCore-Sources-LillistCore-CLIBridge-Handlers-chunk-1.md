---
module: "Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers (chunk 1)"
summary: "CLIBridge handlers (Add–Purge): caseless-enum namespaces that resolve tokens and dispatch to stores."
read_when: "Touching CLI / App Intents verbs (add–pin)"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/AddHandler.swift
    blob: 5436b7d736e7667127026b4a74916bbc699663c5
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
references_modules: [Packages-LillistCore-Sources-LillistCore-CLIBridge-misc, Packages-LillistCore-Sources-LillistCore-Export, Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistCore-Sources-LillistCore-Notifications, Packages-LillistCore-Sources-LillistCore-Rules, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers (chunk 1)

## Purpose

This chunk houses the static verb implementations for the first half of the CLIBridge alphabet (Add through Purge), serving both the lillist CLI and Shortcuts App Intents. Each handler is a caseless namespace enum with no stored state: it resolves a task token, delegates to the appropriate LillistCore store, and returns a DTO or throws. Without this layer, CLI commands and App Intents would need to directly orchestrate token resolution, store instantiation, and date parsing themselves, duplicating logic that the two consumers share.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AddHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/AddHandler.swift:4` | Caseless namespace for task creation; exposes run, status, and firstTagWithName as static async helpers. |
| `AttachHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/AttachHandler.swift:4` | Caseless namespace for file attachment; validates file existence on disk before writing any attachment row. |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/AddHandler.swift:3` | Extension grouping AddHandler into the CLIBridge namespace; no contract independent of the nested enum. |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/AttachHandler.swift:3` | Extension grouping AttachHandler into the CLIBridge namespace; no contract independent of the nested enum. |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/CountHandler.swift:3` | Extension grouping CountHandler into the CLIBridge namespace; no contract independent of the nested enum. |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/DeleteHandler.swift:3` | Extension grouping DeleteHandler into the CLIBridge namespace; no contract independent of the nested enum. |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/EditHandler.swift:3` | Extension grouping EditHandler into the CLIBridge namespace; no contract independent of the nested enum. |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/EvalHandler.swift:4` | Extension grouping EvalHandler into the CLIBridge namespace; no contract independent of the nested enum. |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/ExportHandler.swift:3` | Extension grouping ExportHandler into the CLIBridge namespace; no contract independent of the nested enum. |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/FiltersHandler.swift:3` | Extension grouping FiltersHandler into the CLIBridge namespace; no contract independent of the nested enum. |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/LinkHandler.swift:3` | Extension grouping LinkHandler into the CLIBridge namespace; no contract independent of the nested enum. |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/LsHandler.swift:4` | Extension grouping LsHandler into the CLIBridge namespace; no contract independent of the nested enum. |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/MoveHandler.swift:3` | Extension grouping MoveHandler into the CLIBridge namespace; no contract independent of the nested enum. |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/NoteHandler.swift:3` | Extension grouping NoteHandler into the CLIBridge namespace; no contract independent of the nested enum. |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/NudgeHandler.swift:3` | Extension grouping NudgeHandler into the CLIBridge namespace; no contract independent of the nested enum. |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/PinHandler.swift:3` | Extension grouping PinHandler into the CLIBridge namespace; no contract independent of the nested enum. |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/PurgeHandler.swift:3` | Extension grouping PurgeHandler into the CLIBridge namespace; no contract independent of the nested enum. |
| `CountHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/CountHandler.swift:4` | Thin wrapper over LsHandler.run; returns matching record count without materializing record fields beyond what LsHandler returns. |
| `DeleteHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/DeleteHandler.swift:4` | Caseless namespace for soft-deleting tasks; requires destructive token resolution before store call. |
| `EditHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/EditHandler.swift:4` | Caseless namespace for partial task field updates (title, notes, start, deadline); all fields optional. |
| `EvalHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/EvalHandler.swift:5` | Caseless namespace for evaluating a raw JSON PredicateGroup directly against the live Core Data view context. |
| `ExportHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/ExportHandler.swift:4` | Caseless namespace for backup export; ensures the output directory exists before delegating to Exporter. |
| `FiltersHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/FiltersHandler.swift:4` | CRUD namespace for SmartFilter records; wraps SmartFilterStore for list/show/save/delete and LsHandler for execution. |
| `LinkHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/LinkHandler.swift:4` | Caseless namespace for link-preview attachment creation with SSRF guard (URLPreviewPolicy) and best-effort unfurl. |
| `LsHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/LsHandler.swift:5` | Core listing engine: resolves predicates from flags or saved filters, fetches managed objects, projects to TaskRecord DTOs, sorts. |
| `MoveHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/MoveHandler.swift:4` | Caseless namespace for reparenting tasks; requires destructive token resolution on both child and parent tokens. |
| `NoteHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/NoteHandler.swift:4` | Caseless namespace for appending journal notes to tasks; validates body is non-empty before store call. |
| `NudgeHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/NudgeHandler.swift:4` | Caseless namespace for persisting nudge NotificationSpecs; deliberately does not schedule UNNotificationRequests. |
| `PinHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/PinHandler.swift:4` | Caseless namespace exposing pin and unpin as public entry points; both delegate to setPinned. |
| `PurgeHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/PurgeHandler.swift:4` | Caseless namespace for permanent task removal; requires destructive token resolution before hard-deleting. |
| `delete` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/FiltersHandler.swift:45` | Removes a saved smart filter by name via SmartFilterStore.delete; throws if the filter does not exist. |
| `fetchAllNonTrashedRecords` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/LsHandler.swift:38` | Direct fetch bypassing FilterFlags and predicate compilation; optionally includes trashed records; reused by EvalHandler. |
| `firstTagWithName` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/AddHandler.swift:91` | Searches the tag tree case/whitespace-insensitively for an existing tag; returns its UUID or nil; never creates tags. |
| `list` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/FiltersHandler.swift:5` | Returns all saved SmartFilterRecords from SmartFilterStore; callers receive an empty array when none exist. |
| `pin` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/PinHandler.swift:5` | Sets isPinned=true on the resolved task by delegating to setPinned; throws on unknown token. |
| `record` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/LsHandler.swift:52` | Projects a LillistTask managed object to a TaskStore.TaskRecord DTO; must be called inside ctx.perform to satisfy Sendable rules. |
| `run` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/AddHandler.swift:7` | Creates a task with optional dates, tags, parent, and status; returns the new UUID; throws on invalid tokens or unknown status. |
| `run` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/AttachHandler.swift:6` | Resolves token, validates each path exists on disk, writes a file attachment row per path; returns array of attachment UUIDs. |
| `run` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/CountHandler.swift:5` | Returns count of tasks matching the given filter flags by delegating list logic entirely to LsHandler.run. |
| `run` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/DeleteHandler.swift:5` | Moves a task to trash via TaskStore.softDelete after destructive token resolution; throws on unknown token. |
| `run` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/EditHandler.swift:5` | Applies non-nil field updates (title, notes, start, deadline) to an existing task; parses date tokens; throws on bad token or parse failure. |
| `run` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/EvalHandler.swift:6` | Decodes JSON to PredicateGroup, compiles to NSPredicate inside ctx.perform (Sendable boundary), returns matching TaskRecords. |
| `run` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/ExportHandler.swift:5` | Creates the destination directory if needed and drives Exporter.export to write backup files; throws on I/O or store errors. |
| `run` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/FiltersHandler.swift:13` | Executes a named saved filter by delegating to LsHandler.run with empty FilterFlags; returns sorted TaskRecords. |
| `run` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/LinkHandler.swift:6` | Validates URL scheme and policy, creates a link-preview attachment row, best-effort unfurls metadata; returns attachment UUID. |
| `run` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/LsHandler.swift:7` | Builds predicate from flags or saved filter, fetches inside ctx.perform, returns sorted TaskRecord array; primary CLI read path. |
| `run` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/MoveHandler.swift:5` | Reparents a task to a new parent token or root; destructive resolution on both sides; throws if neither parent nor --root is given. |
| `run` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/NoteHandler.swift:6` | Validates non-empty body, resolves token, appends note via JournalStore.appendNote; returns new journal entry UUID. |
| `run` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/NudgeHandler.swift:13` | Parses date token, persists a nudge NotificationSpec via NotificationSpecStore; the running app schedules it later. |
| `run` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/PurgeHandler.swift:5` | Permanently deletes a task via TaskStore.hardDelete after destructive token resolution; operation is irreversible. |
| `save` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/FiltersHandler.swift:31` | Creates a named SmartFilter with the given PredicateGroup and sort field, always ascending; returns the new UUID. |
| `setPinned` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/PinHandler.swift:11` | Shared implementation for pin/unpin: resolves token with readOnly scope and updates isPinned via TaskStore.update. |
| `show` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/FiltersHandler.swift:9` | Fetches a single SmartFilterRecord by name; throws if the filter is not found. |
| `sort` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/LsHandler.swift:73` | Pure stable sort of a TaskRecord array by SortField; no store access; nil dates sort to distant future/past per field semantics. |
| `status` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/AddHandler.swift:77` | Maps a string token (todo/started/blocked/closed, case-insensitive) to Status; returns nil for unrecognized tokens; never throws. |
| `unpin` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/PinHandler.swift:8` | Sets isPinned=false on the resolved task by delegating to setPinned; throws on unknown token. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.record -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskRecord (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.FilterFlags (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.toPredicateGroup (reads)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-Export.Exporter (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-Export.export (writes)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-LinkPreview.LinkPreviewUnfurler (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-LinkPreview.URLSessionLinkPreviewFetcher (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-LinkPreview.isAllowed (reads)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-LinkPreview.unfurl (writes)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-Notifications.NotificationSpecStore (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-Rules.compile (reads)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.AttachmentStore (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.JournalStore (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.addFile (writes)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.addLinkPreview (writes)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.appendNote (writes)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.assignTag (writes)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.hardDelete (writes)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.softDelete (writes)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.transition (writes)`

## Type notes

All handlers are `public enum` with no cases — instantiation is impossible; every method is `static async throws` (AddHandler.swift:4, LsHandler.swift:5). Each handler receives `PersistenceController` and constructs its own store instances per call — store init is lightweight (just holds a reference). AddHandler.run accepts an optional `DiagnosticSink?` (default nil) for App Intents callers that need task.create diagnostics; CLI callers pass nil and are unaffected (AddHandler.swift:16-24). EvalHandler.run and LsHandler.run build NSPredicate inside `ctx.perform` to satisfy strict concurrency — NSPredicate is not Sendable and may not be captured from the outer async scope (EvalHandler.swift:22-23, LsHandler.swift:24-26). Token resolution uses `destructiveness: .destructive` for DeleteHandler, PurgeHandler, and MoveHandler (DeleteHandler.swift:8, PurgeHandler.swift:8, MoveHandler.swift:14) and `.readOnly` for all other verbs, matching the store's soft-delete safety model.

## External deps

- CoreData — imported
- Foundation — imported

## Gotchas

NudgeHandler.run only persists a NotificationSpec — it intentionally does NOT schedule a UNNotificationRequest; the running app reconciles specs on its next launch or event-bridge fire. Wiring a scheduler in the short-lived CLI process would be wrong (NudgeHandler.swift:6-11). LinkHandler.run unfurls best-effort: failure leaves the attachment row with only the URL, so callers must not assume rich preview metadata is present after run returns (LinkHandler.swift:39-40). EvalHandler.run and LsHandler.run build NSPredicate inside ctx.perform because NSPredicate is not Sendable and cannot be captured across the closure boundary under strict concurrency (EvalHandler.swift:22-23, LsHandler.swift:24-26).
