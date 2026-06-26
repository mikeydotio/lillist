---
module: "Packages/LillistCore/Sources/lillist-cli (misc)"
summary: "Binary entry point for the lillist CLI: root command, subcommand registry, and LillistError-to-exit-code mapping."
read_when: "Touching lillist CLI entry point"
sources:
  - path: Packages/LillistCore/Sources/lillist-cli/Lillist.swift
    blob: 79bcebeb5b2478ae49266dc79a55745b8eb79590
  - path: Packages/LillistCore/Sources/lillist-cli/README.md
    blob: 5c8c96a2b16dac9e4e1636307fe95ef1087268ab
  - path: Packages/LillistCore/Sources/lillist-cli/main.swift
    blob: c367855ff18222c56fe80651b096c6baeb243fe9
references_modules: [Packages-LillistCore-Sources-lillist-cli-Support]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistCore/Sources/lillist-cli (misc)

## Purpose

This module is the binary entry point and root command definition for the `lillist` CLI. `Lillist` registers all subcommands and `runWithExitCodes()` ensures thrown `LillistError` values map to the canonical Section 6 exit codes (0/1/2/3/4/5) rather than argument-parser's default behavior; `main.swift` wraps the whole dispatch with a crash-reporter canary lifecycle before handing off. Without this module, the CLI binary has no entry point, no subcommand registry, and no domain-error-to-exit-code translation.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `Lillist` | struct | `Packages/LillistCore/Sources/lillist-cli/Lillist.swift:10` | Root `AsyncParsableCommand`; callers rely on `configuration.commandName == "lillist"` and the full subcommand list being registered here. |
| `Lillist` | extension | `Packages/LillistCore/Sources/lillist-cli/Lillist.swift:32` | Adds `runWithExitCodes()` to `Lillist`; callers rely on it never returning — it always terminates via `Foundation.exit()` or `Lillist.exit(withError:)`. |
| `runWithExitCodes` | func | `Packages/LillistCore/Sources/lillist-cli/Lillist.swift:36` | Runs the full CLI command lifecycle and terminates the process; `LillistError` exits with Section 6 codes (3/4/5/2/1); argument-parser errors exit via `Lillist.exit(withError:)`. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

- `Packages-LillistCore-Sources-lillist-cli-misc.runWithExitCodes -> Packages-LillistCore-Sources-lillist-cli-Support.fromLillistError (calls)`

## Type notes

`Lillist` is a value-type `struct` conforming to `AsyncParsableCommand`; it carries no stored properties beyond the static `configuration` that lists all subcommands (`Packages/LillistCore/Sources/lillist-cli/Lillist.swift:10-30`). `main.swift` executes at module-init time in a Swift top-level `async` context; `cliReporter` is a `let` constant initialized before any parallel work and captured by all three teardown paths (`Packages/LillistCore/Sources/lillist-cli/main.swift:7`). The `atexit_b` block and signal handlers are outside Swift concurrency — only sync-safe operations are permitted there; `CLICanaryLifecycle.teardownSync()` handles signals while `CLICanaryLifecycle.teardown()` handles normal exit (`Packages/LillistCore/Sources/lillist-cli/main.swift:17-26`). `runWithExitCodes()` is the sole async dispatch entry; it is called exactly once from `main.swift:30` and always terminates the process.

## External deps

- ArgumentParser — imported
- Foundation — imported
- LillistCore — imported

## Gotchas

`@main` was deliberately removed in favor of `main.swift` + `runWithExitCodes()` so `LillistError` can be intercepted before argument-parser's built-in exit path; the comment at `Packages/LillistCore/Sources/lillist-cli/Lillist.swift:6-9` documents this decision. Signal handlers (`SIGTERM`/`SIGINT`) must use `CLICanaryLifecycle.teardownSync()` (sync-safe only); `atexit_b` uses the async variant — swapping them would deadlock (`Packages/LillistCore/Sources/lillist-cli/main.swift:17-26`). `Foundation.exit()` is called directly for `LillistError` cases, while argument-parser's `CleanExit`/`ExitCode` types still flow through `Lillist.exit(withError:)` to preserve argument-parser error rendering (`Packages/LillistCore/Sources/lillist-cli/Lillist.swift:44-52`).
