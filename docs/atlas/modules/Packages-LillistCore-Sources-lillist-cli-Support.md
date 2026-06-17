---
module: Packages/LillistCore/Sources/lillist-cli/Support
summary: Shared CLI plumbing — output/color flags, stdin batch tokens, exit codes, crash-canary lifecycle
read_when: Touching lillist CLI startup, output flags, batch stdin, exit codes, or crash-canary wiring
sources:
  - path: Packages/LillistCore/Sources/lillist-cli/Support/BatchTokens.swift
  - path: Packages/LillistCore/Sources/lillist-cli/Support/CLICanaryLifecycle.swift
  - path: Packages/LillistCore/Sources/lillist-cli/Support/CLIMailtoTransport.swift
  - path: Packages/LillistCore/Sources/lillist-cli/Support/ExitCode.swift
  - path: Packages/LillistCore/Sources/lillist-cli/Support/GlobalOptions.swift
  - path: Packages/LillistCore/Sources/lillist-cli/Support/StdinReader.swift
  - path: Packages/LillistCore/Sources/lillist-cli/Support/TTY.swift
references_modules:
  - Packages-LillistCore-Sources-LillistCore-CrashReporting
  - Packages-LillistCore-Sources-LillistCore-CLIBridge-misc
  - Packages-LillistCore-Sources-LillistCore-misc
generator: cartographer/1 model=claude-sonnet-4-6
---

# Module: Packages/LillistCore/Sources/lillist-cli/Support

## Purpose

Cross-cutting plumbing every `lillist` subcommand reuses: a shared output/color
flag group, stdin-driven batch token resolution, the design-spec exit-code
table, TTY detection, and the static crash-canary lifecycle hooks. These are
the policy pieces that would otherwise be duplicated across the dozen Commands;
centralizing them keeps each subcommand thin and keeps behavior (UUID gating,
NO_COLOR honoring, exit-code mapping) consistent across the CLI surface.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `BatchTokens` | enum | `Packages/LillistCore/Sources/lillist-cli/Support/BatchTokens.swift:14` | Namespace for batch-mode token resolution |
| `BatchTokens.DestructiveGate` | enum | `Packages/LillistCore/Sources/lillist-cli/Support/BatchTokens.swift:16` | `.none` / `.requireUUIDs` — UUID requirement for stdin lines |
| `BatchTokens.resolveInput` | func | `Packages/LillistCore/Sources/lillist-cli/Support/BatchTokens.swift:29` | Returns `[token]` or stdin lines; gates UUIDs for destructive verbs unless `allowFuzzy` |
| `CLICanaryLifecycle` | enum | `Packages/LillistCore/Sources/lillist-cli/Support/CLICanaryLifecycle.swift:8` | Static hook bag for arming/clearing the crash canary |
| `CLICanaryLifecycle.bootstrap` | func | `Packages/LillistCore/Sources/lillist-cli/Support/CLICanaryLifecycle.swift:30` | Arms canary at startup; warns on TTY if prior run crashed; returns stale canary |
| `CLICanaryLifecycle.makeReporter` | func | `Packages/LillistCore/Sources/lillist-cli/Support/CLICanaryLifecycle.swift:12` | Builds a `CrashReporter` wired for the macOS CLI canary slot |
| `CLICanaryLifecycle.teardown` | func | `Packages/LillistCore/Sources/lillist-cli/Support/CLICanaryLifecycle.swift:43` | Async clean-exit canary delete, bounded to 1 s |
| `CLICanaryLifecycle.teardownSync` | func | `Packages/LillistCore/Sources/lillist-cli/Support/CLICanaryLifecycle.swift:55` | Signal-handler-safe synchronous canary delete |
| `CLIMailtoTransport` | struct | `Packages/LillistCore/Sources/lillist-cli/Support/CLIMailtoTransport.swift:7` | `CrashReportTransport` that opens `mailto:` via `/usr/bin/open`, no AppKit |
| `ExitCode` | enum | `Packages/LillistCore/Sources/lillist-cli/Support/ExitCode.swift:5` | Design Section 6 exit-code constants (`success`…`storeUnavailable`) |
| `ExitCode.fromAny` | func | `Packages/LillistCore/Sources/lillist-cli/Support/ExitCode.swift:27` | Maps any `Error` to an exit code; non-`LillistError` → `generic` |
| `ExitCode.fromLillistError` | func | `Packages/LillistCore/Sources/lillist-cli/Support/ExitCode.swift:13` | Maps a `LillistError` case to its exit code |
| `GlobalOptions` | struct | `Packages/LillistCore/Sources/lillist-cli/Support/GlobalOptions.swift:7` | `@OptionGroup` flag bag: `json`/`ndjson`/`tsv`/`quiet`/`noColor` |
| `GlobalOptions.resolveColor` | func | `Packages/LillistCore/Sources/lillist-cli/Support/GlobalOptions.swift:34` | False if `--no-color`, else defers to `TTY.shouldUseColor` |
| `GlobalOptions.resolveOutputFormat` | func | `Packages/LillistCore/Sources/lillist-cli/Support/GlobalOptions.swift:27` | Flags win over the passed config fallback |
| `StdinReader` | enum | `Packages/LillistCore/Sources/lillist-cli/Support/StdinReader.swift:5` | Stdin line reader + UUID validator for batch mode |
| `StdinReader.isStdinSentinel` | func | `Packages/LillistCore/Sources/lillist-cli/Support/StdinReader.swift:8` | True when token equals the `-` sentinel |
| `StdinReader.readAllLines` | func | `Packages/LillistCore/Sources/lillist-cli/Support/StdinReader.swift:12` | Trimmed, non-empty stdin lines |
| `StdinReader.validateAllUUIDs` | func | `Packages/LillistCore/Sources/lillist-cli/Support/StdinReader.swift:27` | Returns lines or throws `LillistError.validationFailed` |
| `TTY` | enum | `Packages/LillistCore/Sources/lillist-cli/Support/TTY.swift:9` | TTY/color detection (honors `NO_COLOR`) |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `StdinReader.linesFromData` | func | `Packages/LillistCore/Sources/lillist-cli/Support/StdinReader.swift:17` | Pure parse step `readAllLines` delegates to; the testable core of stdin handling |
| `TTY.shouldUseColor` | static var | `Packages/LillistCore/Sources/lillist-cli/Support/TTY.swift:14` | Single color-policy gate; `resolveColor` and renderers route through it |

## Relationships

- `Packages-LillistCore-Sources-lillist-cli-Support.CLICanaryLifecycle -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReporter (owns)`
- `Packages-LillistCore-Sources-lillist-cli-Support.CLICanaryLifecycle -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CanaryFile (reads)`
- `Packages-LillistCore-Sources-lillist-cli-Support.CLICanaryLifecycle -> Packages-LillistCore-Sources-lillist-cli-Support.CLIMailtoTransport (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Support.CLICanaryLifecycle -> Packages-LillistCore-Sources-LillistCore-misc.LillistCoreInfo (reads)`
- `Packages-LillistCore-Sources-lillist-cli-Support.CLIMailtoTransport -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReportTransport (conforms-to)`
- `Packages-LillistCore-Sources-lillist-cli-Support.CLIMailtoTransport -> Packages-LillistCore-Sources-LillistCore-CrashReporting.FileSaveTransport (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Support.CLIMailtoTransport -> Packages-LillistCore-Sources-LillistCore-misc.LillistCoreContact (reads)`
- `Packages-LillistCore-Sources-lillist-cli-Support.ExitCode -> Packages-LillistCore-Sources-LillistCore-misc.LillistError (reads)`
- `Packages-LillistCore-Sources-lillist-cli-Support.StdinReader -> Packages-LillistCore-Sources-LillistCore-misc.LillistError (emits)`
- `Packages-LillistCore-Sources-lillist-cli-Support.GlobalOptions -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.CLIBridge (reads)`
- `Packages-LillistCore-Sources-lillist-cli-Support.GlobalOptions -> Packages-LillistCore-Sources-lillist-cli-Support.TTY (reads)`
- `Packages-LillistCore-Sources-lillist-cli-Support.BatchTokens -> Packages-LillistCore-Sources-lillist-cli-Support.StdinReader (calls)`

## Type notes

All public types are uninstantiated namespace enums or value structs — there is
no shared mutable state in this module. `GlobalOptions` conforms to
`ParsableArguments` and is embedded via `@OptionGroup` in subcommands; it carries
only flag booleans plus the explicit `init()` argument-parser requires.

`CLICanaryLifecycle` is a stateless static facade; `main.swift` holds the single
`CrashReporter` instance and threads it through `bootstrap`/`teardown`. The split
`teardown` (async, group-bounded to 1 s) versus `teardownSync` (no async context)
exists because a POSIX signal handler cannot touch an async runtime — the sync
path is the signal-safe variant (`Packages/LillistCore/Sources/lillist-cli/Support/CLICanaryLifecycle.swift:55`).

`BatchTokens.resolveInput` takes its `stdin` reader as an injected closure
defaulting to `StdinReader.readAllLines` so tests resolve tokens without touching
the process's standard input (`Packages/LillistCore/Sources/lillist-cli/Support/BatchTokens.swift:31`).

## External deps

- ArgumentParser — `GlobalOptions` conforms to `ParsableArguments` for `@OptionGroup` embedding
- Foundation — `FileHandle`, `Process`, `URLComponents`, `ProcessInfo`, `Host`
- Darwin/Glibc — `isatty`/`fileno` for TTY detection in `TTY`

## Gotchas

- Destructive batch verbs reject non-UUID stdin lines; `--allow-fuzzy-from-stdin` is the only bypass (`Packages/LillistCore/Sources/lillist-cli/Support/StdinReader.swift:27`).
- `NO_COLOR` env var disables ANSI color even on a TTY (`Packages/LillistCore/Sources/lillist-cli/Support/TTY.swift:16`).
- Argument-parser's own `CleanExit`/`ExitCode` are routed at the dispatcher, not through `ExitCode.fromAny` (`Packages/LillistCore/Sources/lillist-cli/Support/ExitCode.swift:24`).
