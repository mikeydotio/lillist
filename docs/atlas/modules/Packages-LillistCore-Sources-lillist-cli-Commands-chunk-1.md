---
module: "Packages/LillistCore/Sources/lillist-cli/Commands (chunk 1)"
summary: "swift-argument-parser command structs for the lillist CLI; thin shells over CLIBridge handlers"
read_when: "lillist CLI verb structs add through pin"
sources:
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/AddCommand.swift
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/AttachCommand.swift
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/CompletionCommand.swift
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/CountCommand.swift
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/DeleteCommand.swift
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/EditCommand.swift
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/EvalCommand.swift
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/ExportCommand.swift
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/FiltersCommand.swift
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/LinkCommand.swift
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/LsCommand.swift
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/MoveCommand.swift
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/NoteCommand.swift
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/NudgeCommand.swift
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/PinCommand.swift
references_modules: [Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1, Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2, Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers, Packages-LillistCore-Sources-LillistCore-CLIBridge-misc, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistCore-Sources-LillistCore-Model, Packages-LillistCore-Sources-LillistCore-misc, Packages-LillistCore-Sources-lillist-cli-Support]
generator: cartographer/1 model=claude-sonnet-4-6
---

# Module: Packages/LillistCore/Sources/lillist-cli/Commands (chunk 1)

## Purpose

Defines the `swift-argument-parser` command structs that form the `lillist` CLI verb surface. Each struct declares only its flags/arguments and a thin `run()` that opens the shared App-Group store, reads config, and delegates the real work to a `CLIBridge` handler — keeping argument parsing and presentation strictly separate from store logic. If this module vanished the CLI would lose its parseable command tree, but no business logic would move (it lives in `CLIBridge`).

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AddCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/AddCommand.swift:5` | `add` verb; creates a task, prints new UUID unless `--quiet` |
| `AttachCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/AttachCommand.swift:5` | `attach` verb; attaches files to a task, prints attachment UUIDs |
| `CompletionCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/CompletionCommand.swift:4` | `completion` verb; bash/zsh/fish subcommands print install hint |
| `CountCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/CountCommand.swift:5` | `count` verb; prints a single integer match count |
| `DeleteCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/DeleteCommand.swift:5` | `delete` verb; all-or-nothing soft-delete (Trash); stdin requires UUIDs |
| `EditCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/EditCommand.swift:5` | `edit` verb; mutates title/notes/start/deadline of one task |
| `EvalCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/EvalCommand.swift:5` | `eval` verb; runs a PredicateGroup JSON (or stdin) and renders matches |
| `ExportCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/ExportCommand.swift:5` | `export` verb; writes JSON + assets to a target directory |
| `FiltersCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/FiltersCommand.swift:5` | `filters` verb; ls/show/run/save/delete subcommands for saved filters |
| `LinkCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/LinkCommand.swift:5` | `link` verb; attaches a URL link-preview, prints attachment UUID |
| `LsCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/LsCommand.swift:5` | `ls` verb; ad-hoc/saved filter listing with sort + output-format choice |
| `MoveCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/MoveCommand.swift:5` | `move` verb; re-parents tasks (or `--root`); destructive token gate |
| `NoteCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/NoteCommand.swift:5` | `note` verb; appends a Markdown journal note, prints note UUID |
| `NudgeCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/NudgeCommand.swift:5` | `nudge` verb; schedules a nudge at a parsed date, prints UUID |
| `PinCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/PinCommand.swift:5` | `pin` verb; pins a task (no output) |

## Load-bearing internals

(none — every struct is public API; all share the same delegate-to-`CLIBridge` shape)

## Relationships

- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.AddCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.AddHandler (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.AttachCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.AttachHandler (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.CountCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.CountHandler (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.EditCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.EditHandler (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.EvalCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.EvalHandler (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.ExportCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.ExportHandler (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.FiltersCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.FiltersHandler (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.LinkCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.LinkHandler (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.LsCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.LsHandler (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.NoteCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.NoteHandler (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.NudgeCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.NudgeHandler (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.PinCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.PinHandler (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.EvalCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers.TaskRenderer (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.FiltersCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers.FilterRenderer (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.LsCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers.TaskRenderer (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.AddCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.Config (reads)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.LsCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.FilterFlags (owns)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.AddCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.StoreLocator (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.DeleteCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.Resolver (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.MoveCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.Resolver (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.DeleteCommand -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.MoveCommand -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.LsCommand -> Packages-LillistCore-Sources-LillistCore-Model.SortField (reads)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.CountCommand -> Packages-LillistCore-Sources-LillistCore-misc.LillistError (emits)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.DeleteCommand -> Packages-LillistCore-Sources-lillist-cli-Support.BatchTokens (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.MoveCommand -> Packages-LillistCore-Sources-lillist-cli-Support.BatchTokens (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.EvalCommand -> Packages-LillistCore-Sources-lillist-cli-Support.StdinReader (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.AddCommand -> Packages-LillistCore-Sources-lillist-cli-Support.GlobalOptions (owns)`

## Type notes

All structs conform to `AsyncParsableCommand` except `CompletionCommand` and its nested `Bash`/`Zsh`/`Fish`, which are synchronous `ParsableCommand`s (`Packages/LillistCore/Sources/lillist-cli/Commands/CompletionCommand.swift:4`). Commands own no persistent state: each `run()` opens persistence afresh via `CLIBridge.StoreLocator.openAppGroup()` and reads `CLIBridge.Config` before delegating, so there is no shared mutable state across invocations. `FiltersCommand` is the only multi-level command — it nests `Ls`/`Show`/`Run`/`Save`/`Delete` subcommands with `Ls` as default (`Packages/LillistCore/Sources/lillist-cli/Commands/FiltersCommand.swift:9`). Destructive verbs (`DeleteCommand`, `MoveCommand`) pre-resolve every token before any mutation so one bad token aborts the whole batch (`Packages/LillistCore/Sources/lillist-cli/Commands/DeleteCommand.swift:18`).

## External deps

- ArgumentParser — `AsyncParsableCommand`/`ParsableCommand`, `@Argument`/`@Option`/`@Flag`/`@OptionGroup`, `CommandConfiguration`
- Foundation — `Date`, `UUID`, `URL`, `JSONEncoder`, `NSString` tilde expansion
