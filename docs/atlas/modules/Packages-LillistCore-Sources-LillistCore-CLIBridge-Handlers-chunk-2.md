---
module: "Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers (chunk 2)"
summary: "CLIBridge handlers for restore, search, show, status, tag, tags, and watch verbs"
read_when: "CLI verbs (restore–watch) or event stream"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/RestoreHandler.swift
    blob: 5fb928949c1e57886767e94329b7720eb70b8fe0
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/SearchHandler.swift
    blob: f88c2be42dca13fbdc685967a9ee4f8c242f9c0d
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/ShowHandler.swift
    blob: 6615a48fb355d8fd5307dc672ce8b5a5611a503f
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/StatusHandler.swift
    blob: fccb6c4b458311f04ebd4cd9a7e0ba74739847d9
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/TagHandler.swift
    blob: b4b1b66dc267a4988498e85d57b835d7ab4c2217
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/TagsHandler.swift
    blob: ebee6ca1c1b39ed1d4db22dde1e7f532d05ea4f2
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/WatchHandler.swift
    blob: 4304202cc87835019cdbaef8e1db3ff84e1c88c0
references_modules: [Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1, Packages-LillistCore-Sources-LillistCore-CrashReporting, Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers (chunk 2)

## Purpose

This chunk implements the second half of the CLIBridge handler vocabulary: restore-from-trash, full-text search, single-task detail display, status transitions, per-task tag assignment, tag CRUD, and a live change-stream watcher. Each handler is a caseless enum whose static methods thin-wrap the underlying stores and the shared Resolver, adding only the command-specific logic — token syntax parsing, destructiveness classification, change diffing. Without this chunk, the CLI and Shortcuts extension lose all read-detail, mutation, and streaming capabilities.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/RestoreHandler.swift:4` | Extends CLIBridge namespace with RestoreHandler; callers access the handler as CLIBridge.RestoreHandler. |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/SearchHandler.swift:4` | Extends CLIBridge namespace with SearchHandler; callers access the handler as CLIBridge.SearchHandler. |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/ShowHandler.swift:3` | Extends CLIBridge namespace with ShowHandler; callers access the handler as CLIBridge.ShowHandler. |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/StatusHandler.swift:3` | Extends CLIBridge namespace with StatusHandler; callers access the handler as CLIBridge.StatusHandler. |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/TagHandler.swift:3` | Extends CLIBridge namespace with TagHandler; callers access the handler as CLIBridge.TagHandler. |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/TagsHandler.swift:3` | Extends CLIBridge namespace with TagsHandler; callers access the handler as CLIBridge.TagsHandler. |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/WatchHandler.swift:4` | Extends CLIBridge namespace with WatchHandler; callers access the handler as CLIBridge.WatchHandler. |
| `Event` | struct | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/WatchHandler.swift:6` | Codable, Sendable stream payload carrying an event kind, a rendered TaskDTO, and the wall-clock timestamp of the change. |
| `Kind` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/WatchHandler.swift:7` | Discriminant for watch stream events: insert (initial or new), update (changed record), delete (defined but not emitted by run). |
| `Op` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/TagHandler.swift:31` | Internal discriminant for tag mutation direction: .add maps to assignTag, .remove maps to unassignTag. |
| `RestoreHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/RestoreHandler.swift:5` | Namespace enum for trash-restore logic; callers invoke run or preflight as static methods, never instantiate. |
| `Result` | struct | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/ShowHandler.swift:5` | Sendable bundle of a resolved task, its journal entries, its tag IDs, and the pickedSilently flag from the resolver. |
| `SearchHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/SearchHandler.swift:5` | Namespace enum for full-text search; callers invoke run as a static method, never instantiate. |
| `ShowHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/ShowHandler.swift:4` | Namespace enum for single-task detail display; callers invoke run and receive a ShowHandler.Result, never instantiate. |
| `StatusHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/StatusHandler.swift:4` | Namespace enum for status-transition logic; callers invoke run as a static method, never instantiate. |
| `TagHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/TagHandler.swift:4` | Namespace enum for per-task tag assignment and removal; callers pass +#name/-#name token strings to run, never instantiate. |
| `TagsHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/TagsHandler.swift:4` | Namespace enum for tag CRUD operations (list, add, rename, move, delete, tint); callers invoke individual static methods, never instantiate. |
| `WatchHandler` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/WatchHandler.swift:5` | Namespace enum for the live task-change stream; callers invoke run, which never returns under normal conditions. |
| `add` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/TagsHandler.swift:21` | Creates a new tag with optional hex tint and optional named parent; returns the new tag's UUID. |
| `consume` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/WatchHandler.swift:64` | Drains the Coalescer's pending flag; returns true to continue the loop, false when the queue is empty (and clears running). |
| `delete` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/TagsHandler.swift:46` | Finds a tag by exact name and deletes it; throws .notFound or .ambiguous if the name does not resolve to exactly one tag. |
| `findTag` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/TagsHandler.swift:58` | Resolves a tag name across the full depth-first tree; throws .notFound or .ambiguous — used internally by add, rename, move, delete, and tint. |
| `get` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/WatchHandler.swift:84` | Actor-isolated read of the SnapshotBox's current UUID→TaskRecord map; safe to call from any async context. |
| `list` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/TagsHandler.swift:5` | Returns the full tag tree in depth-first order, roots first; delegates to walk with a nil parent seed. |
| `move` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/TagsHandler.swift:36` | Reparents a named tag under a new named parent, or promotes it to root when newParent is nil. |
| `parseToken` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/TagHandler.swift:33` | Parses +#name, -#name, or #name into (Op, tagName); throws .validationFailed on any other prefix. |
| `preflight` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/RestoreHandler.swift:16` | Validates that token resolves to exactly one trashed task; throws before any mutation so batch callers can check all tokens atomically. |
| `rename` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/TagsHandler.swift:30` | Renames a tag identified by its current exact name; throws if the name is not found or is ambiguous. |
| `requestAndShouldStart` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/WatchHandler.swift:55` | Marks a re-evaluation pass pending; returns true iff the caller must start the drain loop (no drain already running). |
| `resolveTrashed` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/RestoreHandler.swift:22` | Resolves token against a caller-supplied trash list by full UUID or case-insensitive title; throws .notFound or .ambiguous. |
| `run` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/RestoreHandler.swift:6` | Fetches trashed tasks, resolves token to a UUID, and restores the matching record; throws on not-found or ambiguous token. |
| `run` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/SearchHandler.swift:6` | Returns non-deleted tasks whose title or notes contain query (localizedStandardContains), optionally restricted to descendants of a resolved scope token. |
| `run` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/ShowHandler.swift:12` | Resolves token anywhere including closed tasks, then fetches the task, its journal entries, and tag IDs together; returns ShowHandler.Result. |
| `run` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/StatusHandler.swift:5` | Transitions a resolved task to newStatus and optionally appends a journal note; classifies closing as destructive resolution per design §6. |
| `run` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/TagHandler.swift:5` | Applies a list of +#name/-#name tokens to a resolved task, creating tags on demand for names not yet in the store. |
| `run` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/WatchHandler.swift:97` | Streams matching tasks as Events via an emit closure; parks indefinitely and never returns; re-evaluations are serialized and debounced through Coalescer. |
| `snapshotStep` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/WatchHandler.swift:27` | Pure function: diffs current records against the previous snapshot and returns only changed or new records to emit, plus the updated snapshot map. |
| `swap` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/WatchHandler.swift:80` | Actor-isolated write replacing the SnapshotBox's UUID→TaskRecord map; called after each drain evaluation to advance the baseline. |
| `tint` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/TagsHandler.swift:52` | Sets the hex tint color on a tag identified by exact name; throws if the name does not resolve uniquely. |
| `walk` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/TagsHandler.swift:10` | Recursive depth-first walk of tag children; returns all descendants of parent in pre-order, with no depth cap. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.Kind -> Packages-LillistCore-Sources-LillistCore-CrashReporting.snapshot (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.parseToken -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.firstTagWithName (reads)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.JournalStore (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.appendNote (writes)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.entries (reads)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.assignTag (writes)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.transition (writes)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.trashed (reads)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.unassignTag (writes)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.tint -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.setTintColor (writes)`

## Type notes

All handlers are caseless enums (no instances, purely static surface). WatchHandler nests two private actors — Coalescer (WatchHandler.swift:49) serializes burst re-evaluation requests into a single drain loop, and SnapshotBox (WatchHandler.swift:77) holds the last-emitted snapshot in actor-isolated state to avoid strict-concurrency capture violations. ShowHandler.Result (ShowHandler.swift:5) is a Sendable value bundle that co-returns task, journal entries, and tag IDs from a single async call. WatchHandler.Event (WatchHandler.swift:6) is Codable+Sendable and is the stream payload encoded to stdout. RestoreHandler.preflight (RestoreHandler.swift:16) enables all-or-nothing batch restore: it validates every token before any write is attempted. TagsHandler.walk (TagsHandler.swift:10) is a recursive depth-first traversal used by both list and findTag; it has no depth guard, unlike SearchHandler's ancestor walk which caps at PredicateLimits.maxAncestorDepth (SearchHandler.swift:34).

## External deps

- CoreData — imported
- Foundation — imported

## Gotchas

WatchHandler.run never returns normally; it parks indefinitely via `Task.sleep(nanoseconds: UInt64.max)` and relies on SIGINT/SIGTERM to terminate the process (WatchHandler.swift:161). WatchHandler.Kind declares a `.delete` case (WatchHandler.swift:7) but the run loop only emits `.insert` and `.update`; `.delete` is never produced. Trashed tasks are excluded from TaskStore's default fetch scope; RestoreHandler must call a separate `.trashed()` query rather than a normal task lookup (RestoreHandler.swift:7-8). StatusHandler classifies transition-to-closed as `.destructive` per design §6 (StatusHandler.swift:12), which NARROWS token matching: a substring-only match throws rather than resolving (Resolver.swift:82-86); the closed-task widening is orthogonal — `scope: .anywhereIncludingClosed` (StatusHandler.swift:15) is what includes closed tasks in the search pool.
