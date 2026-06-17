---
module: "Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers (chunk 2)"
summary: "CLIBridge command handlers for restore, search, show, status, tag, tags, and watch flows"
read_when: "CLI restore/search/tag/watch verbs or the live watch event stream"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/RestoreHandler.swift
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/SearchHandler.swift
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/ShowHandler.swift
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/StatusHandler.swift
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/TagHandler.swift
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/TagsHandler.swift
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/WatchHandler.swift
references_modules:
  - Packages-LillistCore-Sources-LillistCore-CLIBridge-misc
  - Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1
  - Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers
  - Packages-LillistCore-Sources-LillistCore-Stores-chunk-1
  - Packages-LillistCore-Sources-LillistCore-Stores-chunk-2
  - Packages-LillistCore-Sources-LillistCore-Model
  - Packages-LillistCore-Sources-LillistCore-Rules
  - Packages-LillistCore-Sources-LillistCore-ManagedObjects
  - Packages-LillistCore-Sources-LillistCore-misc
generator: cartographer/1 model=claude-sonnet-4-6
---

# Module: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers (chunk 2)

## Purpose

Stateless `CLIBridge` command handlers, each a `public enum` of `static`
functions that wire CLI verbs to the value-type store layer. This chunk covers
the read/mutate verbs that are not core list/add: restore-from-trash, full-text
search, task detail (`show`), status transitions, per-task tagging, the tag
hierarchy CRUD, and the long-lived `watch` event stream. Handlers resolve a
token to a task via `Resolver`, call the appropriate store, and return DTOs;
they never expose `NSManagedObject`s (except `SearchHandler`'s direct fetch
inside a confined `ctx.perform` block).

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `RestoreHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/RestoreHandler.swift:5` | Restores one trashed task resolved by UUID or exact title |
| `RestoreHandler.preflight` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/RestoreHandler.swift:16` | Validates a token is restorable without restoring; enables all-or-nothing batch |
| `RestoreHandler.run` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/RestoreHandler.swift:6` | Resolves token against the trash list and restores it |
| `SearchHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/SearchHandler.swift:5` | Substring search over title/notes, optionally scoped to a subtree |
| `SearchHandler.run` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/SearchHandler.swift:6` | Returns matching non-deleted `TaskRecord`s; honors an optional scope token |
| `ShowHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/ShowHandler.swift:4` | Fetches one task plus its journal and tag ids |
| `ShowHandler.Result` | struct | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/ShowHandler.swift:5` | `Sendable` bundle of task, journal entries, tag ids, and silent-pick flag |
| `ShowHandler.run` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/ShowHandler.swift:12` | Resolves token read-only, returns full task detail |
| `StatusHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/StatusHandler.swift:4` | Transitions a task's status, optionally appending a journal note |
| `StatusHandler.run` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/StatusHandler.swift:5` | Resolves token (destructive iff to `.closed`), transitions, appends note |
| `TagHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/TagHandler.swift:4` | Adds/removes tags on one task from `+#`/`-#`/`#` tokens |
| `TagHandler.run` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/TagHandler.swift:5` | Creates tags on demand, then assigns/unassigns each parsed token |
| `TagsHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/TagsHandler.swift:4` | Tag-hierarchy CRUD: list, add, rename, move, delete, tint |
| `TagsHandler.add` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/TagsHandler.swift:21` | Creates a tag under an optional named parent; returns its id |
| `TagsHandler.delete` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/TagsHandler.swift:46` | Deletes the tag matched by exact name |
| `TagsHandler.list` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/TagsHandler.swift:5` | Returns the full tag tree in depth-first order |
| `TagsHandler.move` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/TagsHandler.swift:36` | Reparents a named tag under an optional named parent |
| `TagsHandler.rename` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/TagsHandler.swift:30` | Renames the tag matched by exact name |
| `TagsHandler.tint` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/TagsHandler.swift:52` | Sets a named tag's tint color to a hex string |
| `WatchHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/WatchHandler.swift:5` | Streams deduped insert/update events for a filter; never returns normally |
| `WatchHandler.Event` | struct | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/WatchHandler.swift:6` | `Codable`/`Sendable` event: kind, task DTO, timestamp |
| `WatchHandler.run` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/WatchHandler.swift:97` | Emits initial inserts, then debounced re-evaluations via `emit`/`onError` |
| `WatchHandler.snapshotStep` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/WatchHandler.swift:27` | Pure dedup step: diffs current vs previous snapshot, returns emits + next |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `RestoreHandler.resolveTrashed` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/RestoreHandler.swift:22` | Trash-scoped token resolution; both `run` and `preflight` route through it |
| `TagsHandler.findTag` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/TagsHandler.swift:58` | Name->id lookup backing every mutating `TagsHandler` verb; throws on ambiguity |
| `TagsHandler.walk` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/TagsHandler.swift:10` | Recursive depth-first tree flatten powering both `list` and `findTag` |
| `TagHandler.parseToken` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/TagHandler.swift:33` | Parses `+#`/`-#`/`#` tag tokens into add/remove ops; throws on malformed input |
| `WatchHandler.Coalescer` | actor | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/WatchHandler.swift:49` | Serializes burst notifications into one drain loop; prevents interleaved tasks |
| `WatchHandler.SnapshotBox` | actor | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/WatchHandler.swift:77` | Actor-isolated last-emitted snapshot enabling safe drain-loop read/write |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.RestoreHandler -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.CLIBridge (extends)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.RestoreHandler -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.RestoreHandler -> Packages-LillistCore-Sources-LillistCore-misc.LillistError (emits)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.SearchHandler -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.Resolver (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.SearchHandler -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.LillistTask (reads)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.SearchHandler -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.LsHandler (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.SearchHandler -> Packages-LillistCore-Sources-LillistCore-Rules.PredicateLimits (reads)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.ShowHandler -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.Resolver (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.ShowHandler -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.ShowHandler -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.JournalStore (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.StatusHandler -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.Resolver (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.StatusHandler -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.StatusHandler -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.JournalStore (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.StatusHandler -> Packages-LillistCore-Sources-LillistCore-Model.Status (reads)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.TagHandler -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.Resolver (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.TagHandler -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.AddHandler (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.TagHandler -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TagStore (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.TagsHandler -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TagStore (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.TagsHandler -> Packages-LillistCore-Sources-LillistCore-misc.LillistError (emits)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.WatchHandler -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.LsHandler (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.WatchHandler -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers.TaskRenderer (calls)`

## Type notes

All handlers are uninstantiable `public enum`s declared as `extension CLIBridge`
members; they hold no state and take a `PersistenceController` per call, so each
invocation constructs fresh `TaskStore`/`TagStore`/`JournalStore` instances.
Public APIs return value-type DTOs (`TaskStore.TaskRecord`,
`JournalStore.JournalRecord`, `TaskRenderer.TaskDTO`) — no `NSManagedObject`
crosses the boundary, except `SearchHandler` which fetches `LillistTask`
directly inside `ctx.perform` and maps each hit through `LsHandler.record`.
`WatchHandler.run` parks forever (`Task.sleep(nanoseconds: .max)` at
`Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/WatchHandler.swift:161`);
it serializes burst re-evaluations through one drain loop guarded by the private
`Coalescer` actor and reads/writes the last snapshot through the private
`SnapshotBox` actor, so strict concurrency holds without detached per-event
Tasks. `snapshotStep` is pure and `Sendable`-safe — it is the unit-testable seam
for dedup logic. `ShowHandler.Result` and `WatchHandler.Event` are `Sendable`
value bundles for crossing back to the CLI process.

## External deps

- Foundation — `UUID`, `Date`, `Calendar`, `Duration`, string normalization
- CoreData — `NSFetchRequest`/`NSPredicate` in `SearchHandler`, change notifications in `WatchHandler`

## Gotchas

- Trashed tasks are outside the default scope, so `RestoreHandler.run` resolves through `TaskStore.trashed()` not `Resolver` (`Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/RestoreHandler.swift:7`).
- `StatusHandler` treats only transitions to `.closed` as destructive (`Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/StatusHandler.swift:12`).
- `SearchHandler` scope ancestry walk is capped at `PredicateLimits.maxAncestorDepth` to bound cycles (`Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/SearchHandler.swift:34`).
