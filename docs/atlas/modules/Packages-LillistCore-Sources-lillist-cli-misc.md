---
module: "Packages/LillistCore/Sources/lillist-cli (misc)"
summary: "lillist CLI entry point — root command, subcommand registry, and LillistError-to-exit-code dispatch"
read_when: "lillist CLI entry point"
sources:
  - path: Packages/LillistCore/Sources/lillist-cli/Lillist.swift
    blob: 79bcebeb5b2478ae49266dc79a55745b8eb79590
  - path: Packages/LillistCore/Sources/lillist-cli/README.md
    blob: 5c8c96a2b16dac9e4e1636307fe95ef1087268ab
  - path: Packages/LillistCore/Sources/lillist-cli/main.swift
    blob: c367855ff18222c56fe80651b096c6baeb243fe9
references_modules: [Packages-LillistCore-Sources-LillistCore-misc, Packages-LillistCore-Sources-LillistCore-CrashReporting, Packages-LillistCore-Sources-lillist-cli-Support, Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1, Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
---

# Module: Packages/LillistCore/Sources/lillist-cli (misc)

## Purpose

The process entry point and top-level wiring of the `lillist` CLI executable.
`Lillist` is the ArgumentParser root command that registers all ~26 subcommands;
`main.swift` is the top-level script that runs the crash-reporting canary
lifecycle and then dispatches into the parser. The design intent is a custom
main (`@main` was deliberately removed) so thrown `LillistError`s map onto the
design Section 6 exit codes (0/1/2/3/4/5) instead of ArgumentParser's defaults.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `Lillist` | struct | `Packages/LillistCore/Sources/lillist-cli/Lillist.swift:10` | Root `AsyncParsableCommand`; its `configuration` is the canonical subcommand registry |
| `Lillist.runWithExitCodes` | static func | `Packages/LillistCore/Sources/lillist-cli/Lillist.swift:36` | Parses+runs the root command; maps thrown `LillistError` to Section 6 exit codes, else defers to ArgumentParser's renderer |

## Load-bearing internals

None — the module is two thin entry files plus a README. `Lillist` and
`runWithExitCodes` are the public surface; there are no ranked private symbols.

## Relationships

- `Packages-LillistCore-Sources-lillist-cli-misc.Lillist -> Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.AddCommand (owns)`
- `Packages-LillistCore-Sources-lillist-cli-misc.Lillist -> Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.WatchCommand (owns)`
- `Packages-LillistCore-Sources-lillist-cli-misc.Lillist -> Packages-LillistCore-Sources-LillistCore-misc.LillistCoreInfo (reads)`
- `Packages-LillistCore-Sources-lillist-cli-misc.runWithExitCodes -> Packages-LillistCore-Sources-LillistCore-misc.LillistError (reads)`
- `Packages-LillistCore-Sources-lillist-cli-misc.runWithExitCodes -> Packages-LillistCore-Sources-lillist-cli-Support.ExitCode (calls)`
- `Packages-LillistCore-Sources-lillist-cli-misc.main -> Packages-LillistCore-Sources-lillist-cli-Support.CLICanaryLifecycle (calls)`
- `Packages-LillistCore-Sources-lillist-cli-misc.main -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReporter (owns)`
- `Packages-LillistCore-Sources-lillist-cli-misc.main -> Packages-LillistCore-Sources-lillist-cli-misc.runWithExitCodes (calls)`

## Type notes

`Lillist` is an `AsyncParsableCommand` with a stateless `public init()`; the
subcommand list lives entirely in `configuration` at
`Packages/LillistCore/Sources/lillist-cli/Lillist.swift:11`. `runWithExitCodes`
is `static` and `async`: it calls `parseAsRoot()`, runs the result via the async
or sync `run()` path, and on success exits `ExitCode.success`. A caught
`LillistError` is written to stderr and exits via `ExitCode.fromLillistError`;
any other error (parse errors, `CleanExit`, `ExitCode`) flows back through
`Lillist.exit(withError:)` (`Packages/LillistCore/Sources/lillist-cli/Lillist.swift:51`).

`main.swift` is a top-level executable script (not a type). It creates one
`CrashReporter` via `CLICanaryLifecycle.makeReporter()`, awaits `bootstrap`
before any work so the canary is guaranteed written, and registers `atexit_b`
plus `SIGTERM`/`SIGINT` handlers that call the sync teardown
(`Packages/LillistCore/Sources/lillist-cli/main.swift:7`–`30`). Signal handlers
exit 143 (SIGTERM) and 130 (SIGINT).

## External deps

- ArgumentParser — `AsyncParsableCommand`, `CommandConfiguration`, `parseAsRoot`, `ExitCode.success`, `exit(withError:)`
- Foundation — `FileHandle.standardError`, `Foundation.exit`, `atexit_b`, `signal`, `Data`

## Gotchas

- `@main` was intentionally removed (Task 24); `main.swift` calls `runWithExitCodes()` so `LillistError` maps to Section 6 codes — see `Packages/LillistCore/Sources/lillist-cli/Lillist.swift:7`.
- Signal handlers must use sync-safe work only, so they call `CLICanaryLifecycle.teardownSync()`, not the async teardown — `Packages/LillistCore/Sources/lillist-cli/main.swift:14`.
- `report-crash` is a stub verb per the README verb list — `Packages/LillistCore/Sources/lillist-cli/README.md:30`.
