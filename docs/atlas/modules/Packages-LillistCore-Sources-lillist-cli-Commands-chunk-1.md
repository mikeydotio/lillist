---
module: "Packages/LillistCore/Sources/lillist-cli/Commands (chunk 1)"
summary: "swift-argument-parser command structs for the lillist CLI; thin shells over CLIBridge handlers"
read_when: "lillist CLI verb structs add through pin"
sources:
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/AddCommand.swift
    blob: faa8bc85ffe6ba35ce713b96b59c3d3c9fb21d85
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/AttachCommand.swift
    blob: 68063ea70be3192e7fca5f8c35a160c7e1e78864
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/CompletionCommand.swift
    blob: 5ca5486e48b088901e39f1c30f3880b11e37e8c9
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/CountCommand.swift
    blob: 07fcd37d3f1b9a8a6fd92752f3eb3b829eae1581
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/DeleteCommand.swift
    blob: 092072d2868c153becf55eddfad26ce5fa757643
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/EditCommand.swift
    blob: 390df740cd37e21edecd76c2eec228f9fc5e5639
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/EvalCommand.swift
    blob: 84df2bd097cdfc178069b3790d4876674cd4d465
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/ExportCommand.swift
    blob: 286cbb35bc00f0fb31c651a1eae31de2d1afc588
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/FiltersCommand.swift
    blob: 8f878f52b352349cfadb4753df39e056f0bcdb97
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/LinkCommand.swift
    blob: 28a0e4fe9d7d414dbecd96bcc26d3cde50bb620c
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/LsCommand.swift
    blob: 4e3efcc491f99edd2c97eebc15536790f1aeaa10
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/MoveCommand.swift
    blob: d844f0d4bb2b6b80cce83776bb9cd7e79db249fc
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/NoteCommand.swift
    blob: f48e803aa718106b722892bea41aafb353c40cf3
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/NudgeCommand.swift
    blob: f1a0f0806294bf1de796ededb51a2c6d2d3e5e8d
  - path: Packages/LillistCore/Sources/lillist-cli/Commands/PinCommand.swift
    blob: dca0ae768570cdd10e8c60719ed5f463a8537b4d
references_modules: [Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1, Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2, Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers, Packages-LillistCore-Sources-LillistCore-CLIBridge-misc, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistCore-Sources-LillistCore-Model, Packages-LillistCore-Sources-LillistCore-misc, Packages-LillistCore-Sources-lillist-cli-Support]
generator: cartographer/1
baseline: 1a1562b636e43ebbdc35c7939ab6989b387f50e9
verified: true
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
