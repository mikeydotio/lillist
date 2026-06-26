---
module: "Packages/LillistCore/Sources/lillist-cli/Commands (chunk 1)"
summary: "AsyncParsableCommand structs for lillist CLI verbs add–pin; parse args and delegate to CLIBridge handlers."
read_when: "Touching CLI verb structs (add–pin)"
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
references_modules: [Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1, Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers, Packages-LillistCore-Sources-LillistCore-CLIBridge-misc, Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistCore-Sources-lillist-cli-Support]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistCore/Sources/lillist-cli/Commands (chunk 1)

## Purpose

This module defines every user-facing `AsyncParsableCommand` struct for the `lillist` CLI binary — one file per verb (add, attach, count, delete, edit, eval, export, link, ls, move, note, nudge, pin) plus the `filters` and `completion` subcommand groups. Each command parses CLI arguments and options via ArgumentParser, then opens the shared app-group store through `CLIBridge.StoreLocator.openAppGroup` and delegates all domain logic to a matching `CLIBridge` handler. Without this layer there are no user-facing subcommands; without the CLIBridge handlers there is no domain logic — the two halves are deliberately separated so the same handlers can serve both CLI and App Intents.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AddCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/AddCommand.swift:5` | CLI entry point for creating a task; callers provide title plus optional start, deadline, tags, notes, parent, status, and GlobalOptions. |
| `AttachCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/AttachCommand.swift:5` | CLI entry point for attaching files to a task; accepts a task token and one or more file-system paths as remaining arguments. |
| `Bash` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/CompletionCommand.swift:13` | ParsableCommand subcommand that prints the instruction to run `lillist --generate-completion-script bash`; does not generate the script itself. |
| `CompletionCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/CompletionCommand.swift:4` | ParsableCommand group exposing bash, zsh, and fish subcommands for shell completion script instructions. |
| `CountCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/CountCommand.swift:5` | CLI entry point for counting matching tasks; accepts --saved filter name, --tag (repeatable), --status (repeatable), and --include-trash. |
| `Delete` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/FiltersCommand.swift:109` | Subcommand of filters that deletes a named saved smart filter; accepts the filter name as a positional argument. |
| `DeleteCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/DeleteCommand.swift:5` | CLI entry point for soft-deleting tasks; requires UUID tokens by default; supports stdin batch input via '-' sentinel. |
| `EditCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/EditCommand.swift:5` | CLI entry point for modifying task fields; accepts a task token and optional new title, notes, start date, and deadline. |
| `EvalCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/EvalCommand.swift:5` | CLI entry point for evaluating a raw PredicateGroup JSON expression against all tasks; output format mirrors the ls command. |
| `ExportCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/ExportCommand.swift:5` | CLI entry point for full data export; accepts a target directory path (must be empty or non-existent). |
| `FiltersCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/FiltersCommand.swift:5` | AsyncParsableCommand group for smart-filter management with ls, show, run, save, and delete subcommands; default subcommand is ls. |
| `Fish` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/CompletionCommand.swift:25` | ParsableCommand subcommand that prints the instruction to run `lillist --generate-completion-script fish`; does not generate the script itself. |
| `LinkCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/LinkCommand.swift:5` | CLI entry point for attaching a URL with link preview to a task; accepts a task token and a URL string. |
| `Ls` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/FiltersCommand.swift:15` | Subcommand of filters that lists all saved filters with name, pin state, tint color, sort field, and sort direction. |
| `LsCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/LsCommand.swift:5` | CLI entry point for listing tasks with the richest filter surface: tags, exclude-tags, status, date ranges, attachments, pinned, saved filter, sort, and output format. |
| `MoveCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/MoveCommand.swift:5` | CLI entry point for re-parenting a task; accepts a task token and optional new-parent token or --root flag. |
| `NoteCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/NoteCommand.swift:5` | CLI entry point for appending a Markdown note to a task's journal; accepts a task token and a note body string. |
| `NudgeCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/NudgeCommand.swift:5` | CLI entry point for scheduling a nudge notification; accepts a task token and a --at time token (ISO-8601, relative DSL, or natural language). |
| `PinCommand` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/PinCommand.swift:5` | CLI entry point for pinning a task; accepts a single task token as a positional argument. |
| `Run` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/FiltersCommand.swift:46` | Subcommand of filters that runs a named saved filter and prints matching tasks; supports --sort override and GlobalOptions output flags. |
| `Save` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/FiltersCommand.swift:76` | Subcommand of filters that persists current tag/status/sort flags as a named smart filter; prints the new filter UUID. |
| `Show` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/FiltersCommand.swift:32` | Subcommand of filters that prints the raw PredicateGroup JSON for a named saved filter. |
| `Zsh` | struct | `Packages/LillistCore/Sources/lillist-cli/Commands/CompletionCommand.swift:20` | ParsableCommand subcommand that prints the instruction to run `lillist --generate-completion-script zsh`; does not generate the script itself. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/AddCommand.swift:36` | Opens the app-group store, delegates to AddHandler.run with all parsed fields, prints the created task UUID unless --quiet. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/AttachCommand.swift:10` | Opens the app-group store, delegates to AttachHandler.run, prints each returned attachment UUID on its own line. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/CompletionCommand.swift:16` | Prints the literal string "Run: lillist --generate-completion-script bash" to stdout. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/CompletionCommand.swift:23` | Prints the literal string "Run: lillist --generate-completion-script zsh" to stdout. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/CompletionCommand.swift:28` | Prints the literal string "Run: lillist --generate-completion-script fish" to stdout. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/CountCommand.swift:12` | Opens the app-group store, builds FilterFlags from CLI args, delegates to CountHandler.run, prints the matching task count as an integer. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/DeleteCommand.swift:11` | Opens store, resolves all tokens atomically (aborts on first bad token), calls TaskStore.softDelete for each resolved ID. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/EditCommand.swift:30` | Opens store, reads config for date parsing, delegates to EditHandler.run with the token and all non-nil field updates. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/EvalCommand.swift:10` | Opens store, reads JSON from argument or stdin sentinel, delegates to EvalHandler.run, formats output per GlobalOptions (json/ndjson/tsv/pretty). |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/ExportCommand.swift:9` | Expands the directory path, opens the store, delegates to ExportHandler.run, prints the resolved export path on success. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/FiltersCommand.swift:19` | Opens store, lists filters via FiltersHandler.list, renders each as PrettyFilterSummary and prints the colored list. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/FiltersCommand.swift:36` | Opens store, fetches named filter via FiltersHandler.show, JSON-encodes the predicate group with sorted-keys pretty-printing. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/FiltersCommand.swift:52` | Opens store, reads config for sort and calendar defaults, runs named filter via FiltersHandler.run, formats results per GlobalOptions. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/FiltersCommand.swift:83` | Opens store, converts FilterFlags to a PredicateGroup, saves it as a named filter via FiltersHandler.save, prints the new filter UUID. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/FiltersCommand.swift:113` | Opens store, deletes the named smart filter via FiltersHandler.delete; produces no output on success. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/LinkCommand.swift:10` | Opens store, delegates to LinkHandler.run with token and URL string, prints the created link-attachment UUID. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/LsCommand.swift:57` | Opens store, reads config defaults, builds FilterFlags from all CLI flags, delegates to LsHandler.run, formats output per GlobalOptions (json/ndjson/tsv/pretty). |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/MoveCommand.swift:13` | Opens store, resolves all tokens atomically, resolves new parent or clears it with --root, calls TaskStore.reparent for each task. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/NoteCommand.swift:21` | Opens store, delegates to NoteHandler.run with token and body, prints the journal entry UUID unless --quiet. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/NudgeCommand.swift:10` | Opens store, reads config for calendar, delegates to NudgeHandler.run with task token and time token, prints the nudge UUID. |
| `run` | func | `Packages/LillistCore/Sources/lillist-cli/Commands/PinCommand.swift:9` | Opens store, delegates to PinHandler.pin with token and persistence; produces no output on success. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.CountCommand -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.tasks (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.pin (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.show (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.status (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers.PrettyFilterSummary (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers.jsonString (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.FilterFlags (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.defaultLocation (reads)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.openAppGroup (reads)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.resolveAll (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.resolvedCalendar (reads)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.toPredicateGroup (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.run -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.softDelete (writes)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.run -> Packages-LillistCore-Sources-lillist-cli-Support.isStdinSentinel (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.run -> Packages-LillistCore-Sources-lillist-cli-Support.readAllLines (reads)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.run -> Packages-LillistCore-Sources-lillist-cli-Support.resolveColor (reads)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.run -> Packages-LillistCore-Sources-lillist-cli-Support.resolveInput (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.run -> Packages-LillistCore-Sources-lillist-cli-Support.resolveOutputFormat (reads)`

## Type notes

All command types are value-type `struct`s conforming to `AsyncParsableCommand` (or `ParsableCommand` for `CompletionCommand` and its sub-structs), instantiated fresh per invocation by ArgumentParser — they hold no persistent state beyond the parsed CLI arguments. No actor isolation is declared; `run()` is `async throws` and runs on the cooperative thread pool. Each `run()` acquires a persistence handle via `CLIBridge.StoreLocator.openAppGroup()` (Packages/LillistCore/Sources/lillist-cli/Commands/AddCommand.swift:37) as its first step. Config is always loaded via `CLIBridge.Config.read(from: CLIBridge.Config.defaultLocation())` when date parsing or output defaults are needed (e.g. Packages/LillistCore/Sources/lillist-cli/Commands/LsCommand.swift:59). Destructive batch commands (delete, move) resolve all tokens before mutating, enforcing all-or-nothing semantics (Packages/LillistCore/Sources/lillist-cli/Commands/DeleteCommand.swift:18-25).

## External deps

- ArgumentParser — imported
- Foundation — imported
- LillistCore — imported

## Gotchas

DeleteCommand.swift:18-25 and MoveCommand.swift:15-39 implement an explicit all-or-nothing pre-flight: all tokens are resolved before any mutation executes, so a single bad token aborts the whole batch. A comment in DeleteCommand.swift:18 states this contract. CompletionCommand.swift:16-29 — the Bash/Zsh/Fish subcommands do not generate scripts themselves; they print instructions directing the user to run `lillist --generate-completion-script <shell>`, delegating actual generation to ArgumentParser's built-in flag.
