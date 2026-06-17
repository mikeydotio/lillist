---
module: "Packages/LillistCore/Sources/lillist-cli/Commands (chunk 2)"
summary: "ArgumentParser command structs (search through watch) that thin-wrap CLIBridge handlers and stores"
read_when: "CLI subcommands (search-watch)"
sources:
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/PurgeCommand.swift
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/ReportCrashCommand.swift
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/RestoreCommand.swift
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/SearchCommand.swift
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/ShowCommand.swift
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/StatusCommand.swift
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/TagCommand.swift
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/TagsCommand.swift
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/UnpinCommand.swift
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/VersionCommand.swift
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/WatchCommand.swift
references_modules: [Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1, Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2, Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers, Packages-LillistCore-Sources-LillistCore-CLIBridge-misc, Packages-LillistCore-Sources-LillistCore-CrashReporting, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistCore-Sources-LillistCore-misc, Packages-LillistCore-Sources-lillist-cli-Support]
generator: cartographer/1
---

# Module: Packages/LillistCore/Sources/lillist-cli/Commands (chunk 2)

## Purpose

The second half of the `lillist` CLI verb set: `purge`, `report-crash`, `restore`,
`search`, `show`, `status`, `tag`, `tags`, `unpin`, `version`, and `watch`. Each
file is a `swift-argument-parser` command struct that parses flags/arguments, opens
the shared App Group store, and delegates to a `CLIBridge` handler or a store DTO.
The design rule is *thin commands*: parsing and output formatting live here; all
business logic lives in `CLIBridge` so the macOS/iOS apps reuse it. Remove this
chunk and those verbs disappear from the CLI surface.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `PurgeCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/PurgeCommand.swift:5` | `purge` — permanently hard-deletes resolved tasks; UUID-gated |
| `ReportCrashCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/ReportCrashCommand.swift:5` | `report-crash` — previews then emails a redacted pending crash report |
| `RestoreCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/RestoreCommand.swift:5` | `restore` — all-or-nothing restore of trashed tasks |
| `SearchCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/SearchCommand.swift:5` | `search` — full-text query, rendered in the chosen output format |
| `ShowCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/ShowCommand.swift:5` | `show` — full detail + journal for one or more tokens |
| `StatusCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/StatusCommand.swift:5` | `status` — transition status; closing is destructive/UUID-gated |
| `TagCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/TagCommand.swift:5` | `tag` — apply/remove tag ops (`+#Work`, `-#Home`) on a task |
| `TagsCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/TagsCommand.swift:5` | `tags` — tag CRUD via subcommands; default `Ls` |
| `UnpinCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/UnpinCommand.swift:5` | `unpin` — clear pin on a task |
| `VersionCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/VersionCommand.swift:5` | `version` — print `lillist <version>`; sync, no store |
| `WatchCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/WatchCommand.swift:5` | `watch` — stream NDJSON events on matching task changes |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `TagsCommand.Add` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/TagsCommand.swift:36` | Create-tag subcommand; prints the new tag UUID |
| `TagsCommand.Move` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/TagsCommand.swift:60` | Reparent subcommand; `--root` overrides the parent arg to nil |
| `TagsCommand.Delete` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/TagsCommand.swift:72` | Delete subcommand; cascades to descendant tags |

## Relationships

- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.PurgeCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.StoreLocator (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.PurgeCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.Resolver (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.PurgeCommand -> Packages-LillistCore-Sources-lillist-cli-Support.BatchTokens (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.PurgeCommand -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.ReportCrashCommand -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CanaryFile (reads)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.ReportCrashCommand -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReport (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.RestoreCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.RestoreHandler (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.RestoreCommand -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.SearchCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.SearchHandler (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.SearchCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers.TaskRenderer (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.ShowCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.ShowHandler (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.ShowCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers.JournalRenderer (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.ShowCommand -> Packages-LillistCore-Sources-lillist-cli-Support.StdinReader (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.StatusCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.AddHandler (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.StatusCommand -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.StatusCommand -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.JournalStore (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.TagCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.TagHandler (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.TagsCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.TagsHandler (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.TagsCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers.TagRenderer (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.UnpinCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.PinHandler (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.WatchCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.WatchHandler (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.WatchCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.Config (reads)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.VersionCommand -> Packages-LillistCore-Sources-LillistCore-misc.LillistCoreInfo (reads)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.SearchCommand -> Packages-LillistCore-Sources-lillist-cli-Support.GlobalOptions (reads)`

## Type notes

Every async command conforms to `AsyncParsableCommand`; `VersionCommand` is the
lone synchronous `ParsableCommand` (`Packages/LillistCore/Sources/lillist-cli/Commands/VersionCommand.swift:5`)
since it touches no store. Stores are opened per-invocation via
`CLIBridge.StoreLocator.openAppGroup()` and never retained.
Destructive verbs flow through a gate: `PurgeCommand` and `RestoreCommand` force
`destructiveGate: .requireUUIDs` (`Packages/LillistCore/Sources/lillist-cli/Commands/PurgeCommand.swift:15`,
`Packages/LillistCore/Sources/lillist-cli/Commands/RestoreCommand.swift:15`), and
`StatusCommand` raises the same gate only when the target status is `.closed`
(`Packages/LillistCore/Sources/lillist-cli/Commands/StatusCommand.swift:33`).
`RestoreCommand` runs a full pre-flight pass before mutating so a bad token aborts
all-or-nothing (`Packages/LillistCore/Sources/lillist-cli/Commands/RestoreCommand.swift:23`).
Output format is selected by `globals.resolveOutputFormat` on commands carrying a
`GlobalOptions` group (search/show/status/tags-ls); destructive verbs print nothing.

## External deps

- ArgumentParser — `AsyncParsableCommand`/`ParsableCommand`, `@Argument`, `@Option`, `@Flag`, `CommandConfiguration`
- Foundation — `FileHandle`, `Data`, `readLine`, `JSONEncoder`, `Date`, `ProcessInfo`, `Host`

## Gotchas

- `report-crash` re-reads the canary because `main.swift` may have already consumed it on startup (`Packages/LillistCore/Sources/lillist-cli/Commands/ReportCrashCommand.swift:20`).
- `TagsCommand.Move` treats `--root` as overriding `newParent` to nil, ignoring the positional arg (`Packages/LillistCore/Sources/lillist-cli/Commands/TagsCommand.swift:68`).
