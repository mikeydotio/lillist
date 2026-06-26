---
module: Packages/LillistCore/Sources/lillist-cli/Support
summary: "CLI startup support: canary lifecycle, output flags, batch stdin, TTY detection, exit-code mapping."
read_when: "Touching CLI startup or output flags"
sources:
  - path: Packages/LillistCore/Sources/lillist-cli/Support/BatchTokens.swift
    blob: c84df24df145043a34c89c879bf446bbbfcbf80e
  - path: Packages/LillistCore/Sources/lillist-cli/Support/CLICanaryLifecycle.swift
    blob: b492325d31ba448977841decc1891e5ff2a70d01
  - path: Packages/LillistCore/Sources/lillist-cli/Support/CLIMailtoTransport.swift
    blob: 4a30bb1119b0100198dfd21cd97c2df31051e2f3
  - path: Packages/LillistCore/Sources/lillist-cli/Support/ExitCode.swift
    blob: f5f5ffb1a175f5414cbda868ff0fd3ffd6bc981b
  - path: Packages/LillistCore/Sources/lillist-cli/Support/GlobalOptions.swift
    blob: 4799e259a152e240436eeff1d8d2458037a9f8fd
  - path: Packages/LillistCore/Sources/lillist-cli/Support/StdinReader.swift
    blob: 7ddf37b8827ee3a40b6d2ba58e4b6f2d7c6036fd
  - path: Packages/LillistCore/Sources/lillist-cli/Support/TTY.swift
    blob: 57090a111e9ba0726fe08d55be48af9ef03d5915
references_modules: [Packages-LillistCore-Sources-LillistCore-CrashReporting, Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistCore-Sources-LillistCore-Notifications]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistCore/Sources/lillist-cli/Support

## Purpose

Cross-cutting support layer for the lillist CLI binary: arms the crash-reporter canary at startup, tears it down on clean exit, maps errors to typed exit codes, and normalises batch stdin input. It also owns the shared ArgumentParser flag group (`GlobalOptions`) that every data-producing subcommand embeds for output-format and color control. Without it, each CLI command would duplicate canary management, stdin sentinel logic, TTY detection, and exit-code mapping independently.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `BatchTokens` | enum | `Packages/LillistCore/Sources/lillist-cli/Support/BatchTokens.swift:14` | Caseless namespace enum; callers use only `resolveInput` and the nested `DestructiveGate` — no cases to match. |
| `CLICanaryLifecycle` | enum | `Packages/LillistCore/Sources/lillist-cli/Support/CLICanaryLifecycle.swift:8` | Caseless namespace enum; callers call `makeReporter()` first, then `bootstrap(reporter:)` at startup, `teardown(reporter:)` on clean exit, and `teardownSync()` from signal handlers. |
| `CLIMailtoTransport` | struct | `Packages/LillistCore/Sources/lillist-cli/Support/CLIMailtoTransport.swift:7` | `CrashReportTransport` that saves the report to a temp `.lillistcrash` file then opens a pre-filled `mailto:` URL via `/usr/bin/open`; does not depend on AppKit. |
| `DestructiveGate` | enum | `Packages/LillistCore/Sources/lillist-cli/Support/BatchTokens.swift:16` | Two-case enum: `.none` permits any stdin token; `.requireUUIDs` causes `resolveInput` to reject non-UUID lines unless `allowFuzzy` is true. |
| `ExitCode` | enum | `Packages/LillistCore/Sources/lillist-cli/Support/ExitCode.swift:5` | Namespace enum of `Int32` constants mapping `LillistError` cases to exit codes per design doc Section 6; callers map errors at the process boundary via `fromLillistError` or `fromAny`. |
| `GlobalOptions` | struct | `Packages/LillistCore/Sources/lillist-cli/Support/GlobalOptions.swift:7` | `ParsableArguments` struct with `--json`, `--ndjson`, `--tsv`, `--quiet`, and `--no-color` flags; embed via `@OptionGroup` in every subcommand that produces data on stdout. |
| `StdinReader` | enum | `Packages/LillistCore/Sources/lillist-cli/Support/StdinReader.swift:5` | Namespace enum for stdin I/O; `sentinel` is `"-"`; all methods are either pure (`isStdinSentinel`, `linesFromData`, `validateAllUUIDs`) or read-once I/O (`readAllLines`). |
| `TTY` | enum | `Packages/LillistCore/Sources/lillist-cli/Support/TTY.swift:9` | Caseless namespace enum for TTY detection; `shouldUseColor` respects `NO_COLOR` env var and stdout isatty status; no mutable state. |
| `bootstrap` | func | `Packages/LillistCore/Sources/lillist-cli/Support/CLICanaryLifecycle.swift:30` | Writes a fresh canary via `reporter.start()`, returns the stale `CrashCanary` from a prior crashed run (or `nil`), and prints a stderr notice on TTY if a stale canary was found; `@discardableResult`. |
| `fromAny` | func | `Packages/LillistCore/Sources/lillist-cli/Support/ExitCode.swift:27` | Downcasts `Error` to `LillistError` and delegates to `fromLillistError`; returns `generic` (1) for all other error types; argument-parser exit types are not routed here. |
| `fromLillistError` | func | `Packages/LillistCore/Sources/lillist-cli/Support/ExitCode.swift:13` | Maps the five named `LillistError` cases to typed exit codes (3–5, 2); all other cases map to `generic` (1). |
| `isStdinSentinel` | func | `Packages/LillistCore/Sources/lillist-cli/Support/StdinReader.swift:8` | Returns `true` iff token equals `"-"`; callers use this to decide whether to expand stdin before processing batch arguments. |
| `linesFromData` | func | `Packages/LillistCore/Sources/lillist-cli/Support/StdinReader.swift:17` | UTF-8 decodes `data`, splits on `\n`, trims whitespace, and filters empty lines; returns `[]` on non-UTF-8 input; no side effects. |
| `makeReporter` | func | `Packages/LillistCore/Sources/lillist-cli/Support/CLICanaryLifecycle.swift:12` | Returns a fully-wired `CrashReporter` with CLI defaults: `CLIMailtoTransport`, `OSLogFetcher`, `BreadcrumbBuffer`, and `CanaryFile` at the `.macOSCLI` default URL. |
| `readAllLines` | func | `Packages/LillistCore/Sources/lillist-cli/Support/StdinReader.swift:12` | Reads all bytes from stdin to EOF and returns trimmed, non-empty lines; blocks until stdin is closed. |
| `resolveColor` | func | `Packages/LillistCore/Sources/lillist-cli/Support/GlobalOptions.swift:34` | Returns `false` if `--no-color` is set; otherwise delegates to `TTY.shouldUseColor` (which also checks `NO_COLOR` env var). |
| `resolveInput` | func | `Packages/LillistCore/Sources/lillist-cli/Support/BatchTokens.swift:29` | Returns `[token]` for a literal token; reads and validates stdin when token is `-`; throws `LillistError.validationFailed` if UUID gate is active and a line is not a valid UUID. |
| `resolveOutputFormat` | func | `Packages/LillistCore/Sources/lillist-cli/Support/GlobalOptions.swift:27` | Flag priority: `--json` > `--ndjson` > `--tsv` > `fallback`; callers supply the config-derived fallback format. |
| `send` | func | `Packages/LillistCore/Sources/lillist-cli/Support/CLIMailtoTransport.swift:10` | Writes report to a temp file via `FileSaveTransport`, constructs a `mailto:` URL with subject/body, launches `/usr/bin/open`, and writes a staging-path notice to stderr; throws on file write or process launch failure. |
| `teardown` | func | `Packages/LillistCore/Sources/lillist-cli/Support/CLICanaryLifecycle.swift:43` | Calls `reporter.markCleanExit()` asynchronously via a `Task`; blocks at most 1 second then returns regardless — callers must not rely on canary deletion completing. |
| `teardownSync` | func | `Packages/LillistCore/Sources/lillist-cli/Support/CLICanaryLifecycle.swift:55` | Deletes the `.macOSCLI` canary file synchronously; safe to call from POSIX signal handlers; never enters any async context. |
| `validateAllUUIDs` | func | `Packages/LillistCore/Sources/lillist-cli/Support/StdinReader.swift:27` | Returns `lines` unchanged if every element is a parseable UUID string; throws `LillistError.validationFailed` naming the first offending line otherwise. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

- `Packages-LillistCore-Sources-lillist-cli-Support.bootstrap -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CanaryFile (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Support.bootstrap -> Packages-LillistCore-Sources-LillistCore-CrashReporting.defaultURL (reads)`
- `Packages-LillistCore-Sources-lillist-cli-Support.bootstrap -> Packages-LillistCore-Sources-LillistCore-CrashReporting.readIfPresent (reads)`
- `Packages-LillistCore-Sources-lillist-cli-Support.linesFromData -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Support.makeReporter -> Packages-LillistCore-Sources-LillistCore-CrashReporting.BreadcrumbBuffer (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Support.makeReporter -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CanaryFile (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Support.makeReporter -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReporter (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Support.makeReporter -> Packages-LillistCore-Sources-LillistCore-CrashReporting.OSLogFetcher (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Support.makeReporter -> Packages-LillistCore-Sources-LillistCore-CrashReporting.defaultURL (reads)`
- `Packages-LillistCore-Sources-lillist-cli-Support.makeReporter -> Packages-LillistCore-Sources-LillistCore-Notifications.current (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Support.send -> Packages-LillistCore-Sources-LillistCore-CrashReporting.FileSaveTransport (writes)`
- `Packages-LillistCore-Sources-lillist-cli-Support.teardown -> Packages-LillistCore-Sources-LillistCore-CrashReporting.markCleanExit (writes)`
- `Packages-LillistCore-Sources-lillist-cli-Support.teardownSync -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CanaryFile (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Support.teardownSync -> Packages-LillistCore-Sources-LillistCore-CrashReporting.defaultURL (reads)`
- `Packages-LillistCore-Sources-lillist-cli-Support.teardownSync -> Packages-LillistCore-Sources-LillistCore-CrashReporting.deleteOnCleanExit (writes)`

## Type notes

All types are either caseless `enum` namespaces or thin value types — no stored mutable state. `GlobalOptions` conforms to `ParsableArguments` and is embedded via `@OptionGroup` (GlobalOptions.swift:7). `CLIMailtoTransport` conforms to `CrashReportTransport` and carries only its `recipient` string (CLIMailtoTransport.swift:7–9). `CLICanaryLifecycle.teardown` bridges async→sync with `DispatchGroup` + a hard 1-second timeout (CLICanaryLifecycle.swift:44–50), deliberately trading completeness for non-hanging. `CLICanaryLifecycle.teardownSync` is signal-handler-safe and performs a purely synchronous file delete with no async context (CLICanaryLifecycle.swift:53–57). `BatchTokens.resolveInput` accepts an injectable `stdin` closure defaulting to `StdinReader.readAllLines`, keeping it testable without touching the real process stdin (BatchTokens.swift:31–32). None of these types carry actor isolation annotations; they are safe to call from synchronous and async contexts alike.

## External deps

- ArgumentParser — imported
- Darwin — imported
- Foundation — imported
- Glibc — imported
- LillistCore — imported

## Gotchas

`CLICanaryLifecycle.teardown` bridges async `markCleanExit()` via a `DispatchGroup` with a 1-second hard timeout (CLICanaryLifecycle.swift:44–50); the canary delete may be skipped if the system is under heavy load at exit. `teardownSync` exists specifically for POSIX signal handlers and must not be called from async code — the comment at CLICanaryLifecycle.swift:53 documents this constraint. `CLIMailtoTransport.send` first writes the report to a temp `.lillistcrash` file via `FileSaveTransport` before composing the `mailto:` URL, because mail clients cannot carry report data as URL query parameters (CLIMailtoTransport.swift:11–13). `TTY.shouldUseColor` checks the `NO_COLOR` environment variable before the isatty result, honouring the https://no-color.org convention (TTY.swift:16).
