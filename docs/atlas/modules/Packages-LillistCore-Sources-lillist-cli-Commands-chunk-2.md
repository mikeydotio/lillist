---
module: "Packages/LillistCore/Sources/lillist-cli/Commands (chunk 2)"
summary: "CLI command structs (purge–watch); each delegates to a CLIBridge handler."
read_when: "Touching CLI verbs (purge–watch)"
sources:
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/PurgeCommand.swift
    blob: 159cefdc40da3abbf80c9a4149c3ea8fc61eaff6
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/ReportCrashCommand.swift
    blob: fdeaeb26f6aa029d639546fed7d50ecec4b88d9a
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/RestoreCommand.swift
    blob: e5b33199c792c34fd1538baf016b12b7d295da8b
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/SearchCommand.swift
    blob: ac683f734781214fb0cfe5bf1b3f65cbde2e386f
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/ShowCommand.swift
    blob: 0f84799cb374b93130fb2f28613b8f1136515418
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/StatusCommand.swift
    blob: cab9236d53fefbb14e6f657f59e7faf5d6757b07
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/TagCommand.swift
    blob: b664d7c9d82b8dcdc67f0ce37ea2118a3b7d51d5
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/TagsCommand.swift
    blob: 805074eab490a961e307c1d6c6dd22cc5741d6ea
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/UnpinCommand.swift
    blob: e3cd905d77bf86c6e1588d2d2c932c6dc0554f40
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/VersionCommand.swift
    blob: 44292568f9ab6968ef4f4c996972bef54956a8c5
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/WatchCommand.swift
    blob: e011e2d70efe07d24161dbd5a2f7c51c0a2f9be4
references_modules: [Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1, Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2, Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers, Packages-LillistCore-Sources-LillistCore-CLIBridge-misc, Packages-LillistCore-Sources-LillistCore-CrashReporting, Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistCore-Sources-LillistCore-Notifications, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistCore-Sources-lillist-cli-Support]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistCore/Sources/lillist-cli/Commands (chunk 2)

## Purpose

This chunk defines the second half of the lillist CLI command surface: the destructive verbs (purge, restore), the query verbs (search, show), the mutation verbs (status, tag, tags with five subcommands, unpin), the crash-reporting verb (report-crash), the streaming verb (watch), and the informational verb (version). Every command is a thin argument-parsing shell that opens the app group store via StoreLocator.openAppGroup and delegates all business logic to a CLIBridge handler or store method, so the commands themselves contain no domain logic. Without this chunk, the CLI would lose the majority of its task-management surface and the entire crash-reporting and live-watch workflows.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `Add` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/TagsCommand.swift:36` | Creates a new tag with optional `--tint` hex color and `--parent` name; prints the created tag's UUID to stdout. |
| `Delete` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/TagsCommand.swift:72` | Deletes a tag by name and cascades deletion to all its descendants. |
| `Ls` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/TagsCommand.swift:15` | Lists all tags; output format (pretty/json/ndjson/tsv) controlled by GlobalOptions; the default subcommand of TagsCommand. |
| `Move` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/TagsCommand.swift:60` | Reparents a tag; `--root` moves the tag to the top level (nil parent); otherwise takes an explicit new-parent name. |
| `PurgeCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/PurgeCommand.swift:5` | Permanently deletes one or more tasks; stdin tokens require UUIDs unless `--allow-fuzzy-from-stdin` is set. |
| `Rename` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/TagsCommand.swift:49` | Renames an existing tag from `name` to `newName`; throws if the tag does not exist. |
| `ReportCrashCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/ReportCrashCommand.swift:5` | Assembles and emails a redacted crash report; `--no-logs` and `--no-breadcrumbs` suppress those sections. |
| `RestoreCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/RestoreCommand.swift:5` | Restores one or more trashed tasks using all-or-nothing semantics; aborts if any token does not resolve to a trashed task. |
| `SearchCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/SearchCommand.swift:5` | Full-text search across tasks; output format (pretty/json/ndjson/tsv) controlled by GlobalOptions. |
| `ShowCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/ShowCommand.swift:5` | Shows full task detail including journal entries; accepts token from argument or stdin sentinel `-`. |
| `StatusCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/StatusCommand.swift:5` | Transitions a task's status; applies UUID gate only for `closed`; optionally appends a journal note via `--note`. |
| `TagCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/TagCommand.swift:5` | Applies or removes tag operations on a single task using `+#Name` / `-#Name` / `#Name` syntax. |
| `TagsCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/TagsCommand.swift:5` | Parent command grouping tag-management subcommands (ls/add/rename/move/delete/tint); defaults to `ls` when no subcommand is given. |
| `Tint` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/TagsCommand.swift:82` | Sets a tag's tint color to the given hex string (e.g. `#FF0000`). |
| `UnpinCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/UnpinCommand.swift:5` | Removes the pin from a task identified by token. |
| `VersionCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/VersionCommand.swift:5` | Prints the CLI version string synchronously; no store access or async work required. |
| `WatchCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/WatchCommand.swift:5` | Streams NDJSON task-change events matching optional tag/status filters until interrupted; optionally targets a named smart filter. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/PurgeCommand.swift:11` | Resolves tokens with a UUID destructive gate, then calls hardDelete on each; throws if any token fails to resolve or deletion fails. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/ReportCrashCommand.swift:19` | Reads the canary file; exits silently if none is pending; otherwise prints a redacted preview, reads a stdin description, and calls reporter.submit. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/RestoreCommand.swift:11` | Pre-flights all tokens against the trash list before restoring any; a single bad token throws and no task is restored. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/SearchCommand.swift:11` | Delegates to SearchHandler, then routes results through TaskRenderer in the format resolved from GlobalOptions. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/ShowCommand.swift:18` | Opens store, reads tokens from argument or stdin lines, calls renderOne for each; throws on store or resolution failure. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/StatusCommand.swift:28` | Validates status string, resolves tokens, transitions each task, and appends a journal note if `--note` is non-empty. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/TagCommand.swift:19` | Opens the app group store and delegates all tag operations to TagHandler.run; throws on store or handler failure. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/TagsCommand.swift:19` | Lists all tags via TagsHandler.list and renders them in the format resolved from GlobalOptions. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/TagsCommand.swift:42` | Creates a tag via TagsHandler.add and prints the resulting UUID to stdout; throws on name conflict or store failure. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/TagsCommand.swift:54` | Renames a tag via TagsHandler.rename; throws if the tag does not exist or the new name conflicts. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/TagsCommand.swift:66` | Reparents a tag via TagsHandler.move; passes nil parent when `--root` is set, otherwise forwards the given newParent. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/TagsCommand.swift:76` | Deletes a tag and its descendants via TagsHandler.delete; throws if the tag does not exist. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/TagsCommand.swift:87` | Sets a tag's tint color via TagsHandler.tint; throws if the tag does not exist or the hex string is invalid. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/UnpinCommand.swift:9` | Opens the app group store and delegates to PinHandler.unpin; throws on store or handler failure. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/VersionCommand.swift:8` | Prints `"lillist <version>"` using LillistCoreInfo.version; callers can rely on a clean exit with no side effects. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/WatchCommand.swift:22` | Opens store, reads config for calendar, builds FilterFlags from options, then drives WatchHandler with a line-by-line JSON emit closure writing to stdout. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.renderOne -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.renderOne -> Packages-LillistCore-Sources-lillist-cli-Support.resolveColor (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.renderOne -> Packages-LillistCore-Sources-lillist-cli-Support.resolveOutputFormat (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.status (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.unpin (writes)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.move (writes)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.tint (writes)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers.jsonString (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.FilterFlags (owns)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.defaultLocation (reads)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.openAppGroup (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.resolveAll (reads)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.resolvedCalendar (reads)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-CrashReporting.BreadcrumbBuffer (owns)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CanaryFile (owns)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReport (owns)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReporter (owns)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-CrashReporting.OSLogFetcher (owns)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-CrashReporting.defaultURL (reads)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-CrashReporting.readIfPresent (reads)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-CrashReporting.renderedAsPlainText (reads)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-CrashReporting.submit (writes)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-Notifications.current (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.JournalStore (owns)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.appendNote (writes)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.hardDelete (writes)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.transition (writes)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.trashed (reads)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-lillist-cli-Support.CLIMailtoTransport (owns)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-lillist-cli-Support.isStdinSentinel (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-lillist-cli-Support.readAllLines (reads)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-lillist-cli-Support.resolveColor (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-lillist-cli-Support.resolveInput (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.run -> Packages-LillistCore-Sources-lillist-cli-Support.resolveOutputFormat (calls)`

## Type notes

All commands are `public struct` conforming to `AsyncParsableCommand`; `VersionCommand` is the sole synchronous `ParsableCommand` (Packages/LillistCore/Sources/lillist-cli/Commands/VersionCommand.swift:5). No actor isolation — swift-argument-parser invokes run() from the main context and each invocation is stateless after the function returns. `PurgeCommand` and `RestoreCommand` apply `destructiveGate: .requireUUIDs` on stdin tokens to prevent accidental fuzzy-matched deletions (Packages/LillistCore/Sources/lillist-cli/Commands/PurgeCommand.swift:15, Packages/LillistCore/Sources/lillist-cli/Commands/RestoreCommand.swift:15). `TagsCommand` nests six subcommand structs (`Ls`, `Add`, `Rename`, `Move`, `Delete`, `Tint`) with `Ls` as `defaultSubcommand`, so `lillist tags` lists tags without an explicit subcommand (Packages/LillistCore/Sources/lillist-cli/Commands/TagsCommand.swift:9). `ReportCrashCommand` is the only command in this chunk that never opens the app group store; it operates entirely on crash-reporting infrastructure (Packages/LillistCore/Sources/lillist-cli/Commands/ReportCrashCommand.swift:19-64).

## External deps

- ArgumentParser — imported
- Foundation — imported
- LillistCore — imported

## Gotchas

RestoreCommand.run runs a pre-flight check for every token before restoring any, giving all-or-nothing semantics; the comment at Packages/LillistCore/Sources/lillist-cli/Commands/RestoreCommand.swift:19 explains that RestoreHandler.run repeats the resolution, so the pre-flight throws first on a bad token to prevent partial restores. ReportCrashCommand.run prints a full plain-text preview to stdout before reading a user description from stdin (Packages/LillistCore/Sources/lillist-cli/Commands/ReportCrashCommand.swift:39-53), so users see exactly what they are agreeing to send. WatchCommand is the only command in this chunk that bypasses BatchTokens and Resolver entirely; it constructs FilterFlags directly and maps status strings through AddHandler.status (Packages/LillistCore/Sources/lillist-cli/Commands/WatchCommand.swift:25-32).
