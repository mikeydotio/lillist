---
module: "Packages/LillistCore/Sources/LillistCore/CLIBridge (misc)"
summary: "Shared load-bearing primitives for the CLI and Shortcuts — store location, task resolution, date/filter parsing"
read_when: "CLI/Shortcuts store access, fuzzy task resolution, date input parsing, or filter flag translation"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/CLIBridge.swift
    blob: c4bf1afbbb44a21b8a5162f4b1a1db2299deaf1f
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Config.swift
    blob: 30810b649af3df23a2b16e8904d91656bbc898c2
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/DateParsing.swift
    blob: 832f427a2cca04791e3783ff2501735e0d2680aa
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/FilterFlags.swift
    blob: 6beb4def986435c783f9301805fb0dba74a10c6d
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/OutputFormat.swift
    blob: 95f838c57fcc1427c31d510dd578058ea1ecbdb1
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift
    blob: 96b084b79bf8710a31e90cc520bb38402daf19c8
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/StoreLocator.swift
    blob: face1e87c95329651709b822e18bef6c20a765f4
references_modules: [Packages-LillistCore-Sources-LillistCore-misc, Packages-LillistCore-Sources-LillistCore-Model, Packages-LillistCore-Sources-LillistCore-Rules, Packages-LillistCore-Sources-LillistCore-Persistence, Packages-LillistCore-Sources-LillistCore-Sync-chunk-1, Packages-LillistCore-Sources-LillistCore-ManagedObjects, Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1, Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1]
generator: cartographer/1
baseline: 1a1562b636e43ebbdc35c7939ab6989b387f50e9
verified: true
---

# Module: Packages/LillistCore/Sources/LillistCore/CLIBridge (misc)

## Purpose

The shared substrate that the `lillist` CLI and the App-Intents/Shortcuts
actions both build on, per design Section 6: anything load-bearing
(store location, resolution, validation, parsing) lives here, while verb
parsing and output formatting stay with the caller. These root files supply
the cross-cutting primitives — store opening, fuzzy task resolution, date and
filter parsing, config — that the per-verb `Handlers` and `Renderers` consume.
Without them every CLI command would reimplement store discovery and token
matching independently.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `CLIBridge` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/CLIBridge.swift:9` | Namespace; every type below is nested under it |
| `CLIBridge.Config` | struct | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Config.swift:7` | User config from `~/.config/lillist/config.toml`; hand-parsed, value-type, unknown keys ignored |
| `CLIBridge.DateParsing` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/DateParsing.swift:18` | Parses ISO-8601, relative DSL, and NL date phrases into a `Resolved` |
| `CLIBridge.DateParsing.Resolved` | struct | `Packages/LillistCore/Sources/LillistCore/CLIBridge/DateParsing.swift:19` | `date` + `hasTime`; callers map `hasTime` onto start/deadline |
| `CLIBridge.FilterFlags` | struct | `Packages/LillistCore/Sources/LillistCore/CLIBridge/FilterFlags.swift:14` | Value bag for `ls`/`count`/`watch` filters; `toPredicateGroup` builds the query |
| `CLIBridge.OutputFormat` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/OutputFormat.swift:4` | `pretty`/`json`/`ndjson`/`tsv` render-mode selector |
| `CLIBridge.Resolver` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift:15` | Resolves a user token to one task ID (UUID, prefix, exact/substring title) |
| `CLIBridge.Resolver.Resolution` | struct | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift:38` | Resolved `id` + `matchKind` + `pickedSilently` |
| `CLIBridge.Resolver.Scope` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift:16` | Search scope: anywhere / descendants-of / closed-inclusive variants |
| `CLIBridge.Resolver.Destructiveness` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift:23` | Gate: destructive verbs require UUID or exact-title match |
| `CLIBridge.StoreLocator` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/StoreLocator.swift:11` | Opens the shared store (app-group / on-disk / in-memory) for CLI access |

## Load-bearing internals

| Symbol | Location | Why it matters |
| --- | --- | --- |
| `StoreLocator.openAppGroup` | `Packages/LillistCore/Sources/LillistCore/CLIBridge/StoreLocator.swift:24` | Default CLI store entry point; consults MigrationGate before opening |
| `Resolver.resolve` | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift:47` | Core fuzzy-match routing: UUID → prefix → exact → substring |
| `Resolver.resolveAll` | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift:98` | All-or-nothing batch resolve; throws before any caller mutation |
| `FilterFlags.toPredicateGroup` | `Packages/LillistCore/Sources/LillistCore/CLIBridge/FilterFlags.swift:34` | Translates flags to a `PredicateGroup`; resolves tag names to UUIDs |
| `Config.resolvedCalendar` | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Config.swift:23` | Calendar honoring configured `time_zone`; centralizes relative-date math |
| `Config.defaultLocation` | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Config.swift:73` | Default config path; `NSHomeDirectory`-based for iOS portability |
| `DateParsing.startOfDay` | `Packages/LillistCore/Sources/LillistCore/CLIBridge/DateParsing.swift:222` | Calendar-anchored day floor underpinning all base-phrase math |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.StoreLocator -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceController (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.StoreLocator -> Packages-LillistCore-Sources-LillistCore-Persistence.StoreConfiguration (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.StoreLocator -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.MigrationGate (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.StoreLocator -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.SyncModeStore (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.StoreLocator -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.FileMigrationJournalStore (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.StoreLocator -> Packages-LillistCore-Sources-LillistCore-misc.LillistError (emits)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.Resolver -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.LillistTask (reads)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.Resolver -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceController (reads)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.Resolver -> Packages-LillistCore-Sources-LillistCore-Rules.PredicateLimits (reads)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.Resolver -> Packages-LillistCore-Sources-LillistCore-Model.Status (reads)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.Resolver -> Packages-LillistCore-Sources-LillistCore-misc.LillistError (emits)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.FilterFlags -> Packages-LillistCore-Sources-LillistCore-Rules.PredicateGroup (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.FilterFlags -> Packages-LillistCore-Sources-LillistCore-Rules.AttachmentKindMatch (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.FilterFlags -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.Tag (reads)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.FilterFlags -> Packages-LillistCore-Sources-LillistCore-Model.Status (reads)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.Config -> Packages-LillistCore-Sources-LillistCore-Model.SortField (reads)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.Config -> Packages-LillistCore-Sources-LillistCore-misc.LillistError (emits)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.DateParsing -> Packages-LillistCore-Sources-LillistCore-misc.LillistError (emits)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.FilterFlags -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.DateParsing (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.SearchHandler -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.Resolver (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.AddCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.StoreLocator (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.MoveCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.Resolver (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.DeleteCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.StoreLocator (calls)`

## Type notes

All public types are value types (`struct`/`enum`) and `Sendable`; no
`NSManagedObject` escapes — `Resolver` and `FilterFlags` hold Core Data fetches
inside `viewContext.perform` closures and return only UUIDs/`Resolution`s.
`DateParsing.parse` and `FilterFlags.toPredicateGroup` thread an explicit
`Calendar` (sourced from `Config.resolvedCalendar`) so time-zone config affects
relative-date math; `ISO8601DateFormatter` is constructed per call because it
is not `Sendable` under strict concurrency
(`Packages/LillistCore/Sources/LillistCore/CLIBridge/DateParsing.swift:31`).
`Resolver.Scope`'s descendant constraint cannot be expressed in SQL, so it is
enforced in-memory by `passesScope` bounded by `PredicateLimits.maxAncestorDepth`
(`Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift:249`).

## External deps

- Foundation — `Calendar`/`DateComponents` date math, `URL`/`FileManager` paths, ISO/`DateFormatter`
- CoreData — `NSFetchRequest`/`NSPredicate`/`NSCompoundPredicate` in `Resolver` and `FilterFlags`

## Gotchas

- Unknown `--tag` names resolve to an empty UUID set, not an error: `lillist ls --tag UnknownTag` silently returns zero rows (`Packages/LillistCore/Sources/LillistCore/CLIBridge/FilterFlags.swift:86`).
- Destructive verbs refuse substring matches; only UUID or exact-title resolves (`Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift:82`).
- A non-idle migration journal makes `openAppGroup` throw `storeUnavailable` rather than racing a foreground migration (`Packages/LillistCore/Sources/LillistCore/CLIBridge/StoreLocator.swift:49`).
