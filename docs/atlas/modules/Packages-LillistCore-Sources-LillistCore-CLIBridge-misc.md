---
module: "Packages/LillistCore/Sources/LillistCore/CLIBridge (misc)"
summary: "CLIBridge shared infrastructure: store access, date parsing, task resolution, and filter flags."
read_when: "Touching CLI store access, dates, or filters"
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
    blob: c61365f2edbccdd5bba2fb1da406c9406295497f
references_modules: [Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistCore-Sources-LillistCore-Persistence, Packages-LillistCore-Sources-LillistCore-Rules, Packages-LillistCore-Sources-LillistCore-Sync-chunk-1, Packages-LillistUI-Sources-LillistUI-Recurrence]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistCore/Sources/LillistCore/CLIBridge (misc)

## Purpose

CLIBridge is the shared verb infrastructure layer consumed by both the `lillist` CLI and the Shortcuts/App Intents extension. It provides everything a handler needs before touching a store: open the right Core Data container (`StoreLocator`), parse user-typed date tokens into `Date` values (`DateParsing`), translate flag bags into `PredicateGroup` queries (`FilterFlags`), resolve partial title or UUID tokens to a single task ID (`Resolver`), read per-user config (`Config`), and select output format (`OutputFormat`). Without it, every CLI handler and every Shortcuts action would re-implement store access, date parsing, and task resolution — the module is the abstraction seam between the user-facing verb layer and the LillistCore data layer.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `CLIBridge` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/CLIBridge.swift:9` | Caseless enum namespace; callers may rely on it grouping all shared CLI/Shortcuts sub-types and never being instantiated. |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Config.swift:3` | Extension namespace binding `Config` into the `CLIBridge` group; no standalone contract beyond the types it contains. |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/DateParsing.swift:3` | Extension namespace binding `DateParsing` into `CLIBridge`; no standalone contract beyond the types it contains. |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/FilterFlags.swift:4` | Extension namespace binding `FilterFlags` into `CLIBridge`; no standalone contract beyond the types it contains. |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/OutputFormat.swift:3` | Extension namespace binding `OutputFormat` into `CLIBridge`; no standalone contract beyond the type it contains. |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift:4` | Extension namespace binding `Resolver` and its supporting types into `CLIBridge`; no standalone contract beyond the types it contains. |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/StoreLocator.swift:3` | Extension namespace binding `StoreLocator` into `CLIBridge`; no standalone contract beyond the type it contains. |
| `Candidate` | struct | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift:141` | Internal `(id: UUID, title: String)` pair built during title-candidate fetches; not exposed to callers outside `Resolver`. |
| `Config` | struct | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Config.swift:7` | Sendable, Equatable value bag for the three supported config keys; a missing file or absent key silently yields defaults. |
| `DateParsing` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/DateParsing.swift:18` | Stateless caseless enum; callers rely on `parse` returning a `Resolved` with a `hasTime` flag for all supported shapes, and throwing `LillistError.validationFailed` for unrecognized input. |
| `Destructiveness` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift:23` | Two-case enum; `.destructive` forces callers to supply a UUID or exact title — partial substring matches throw instead of silently proceeding. |
| `FilterFlags` | struct | `Packages/LillistCore/Sources/LillistCore/CLIBridge/FilterFlags.swift:14` | Sendable, Equatable mutable bag of CLI filter options; defaults to `combinator: .all` with all collections empty and boolean flags false. |
| `MatchKind` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift:31` | Sendable, Equatable four-case enum recording how a token was resolved; callers may use this to emit provenance notes to stderr. |
| `OutputFormat` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/OutputFormat.swift:4` | Codable, CaseIterable, Sendable enum with four cases: `pretty`, `json`, `ndjson`, `tsv`; raw value matches the config-file string. |
| `RelativeMatch` | struct | `Packages/LillistCore/Sources/LillistCore/CLIBridge/DateParsing.swift:162` | Internal result carrying `Calendar.Component` and signed value extracted from a `±N<unit>` DSL token; not exposed to module callers. |
| `Resolution` | struct | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift:38` | Sendable, Equatable result carrying `id: UUID`, `matchKind`, and `pickedSilently: Bool`; callers should emit a stderr note when `pickedSilently` is true. |
| `Resolved` | struct | `Packages/LillistCore/Sources/LillistCore/CLIBridge/DateParsing.swift:19` | Sendable, Equatable result pair `(date: Date, hasTime: Bool)`; `hasTime` maps to `startHasTime`/`deadlineHasTime` per design Section 2. |
| `Resolver` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift:15` | Stateless caseless enum; callers rely on `resolve`/`resolveAll` returning deterministic `Resolution` values or throwing `LillistError.notFound`/`.ambiguous`. |
| `Scope` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift:16` | Four-case enum controlling which tasks are visible to resolution; `.anywhere` excludes closed tasks; `descendantsOf(UUID)` adds in-memory parent-chain filtering. |
| `StoreLocator` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/StoreLocator.swift:11` | Caseless enum; callers rely on `openAppGroup` returning a ready `PersistenceController` or throwing `LillistError.storeUnavailable` with a human-readable install pointer. |
| `applyTime` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/DateParsing.swift:115` | Applies an `h`, `h:mm`, `ham`, or `hpm` time clause to a base `Date`; throws `LillistError.validationFailed` on malformed input. |
| `defaultLocation` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Config.swift:73` | Returns `~/.config/lillist/config.toml` via `NSHomeDirectory()` — always succeeds, never throws; the file need not exist. |
| `endOfMonth` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/DateParsing.swift:237` | Returns the last day of the month containing `d` at midnight in `calendar`'s time zone via `Calendar.date(byAdding:)`. |
| `endOfWeek` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/DateParsing.swift:229` | Returns the last day of the week containing `d` (week-start + 6 days) at midnight in `calendar`'s time zone. |
| `fetchTitleCandidates` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift:206` | Fetches all in-scope tasks then applies diacritic-folded substring match in-memory; internal helper for `resolve`. |
| `foldedContains` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift:154` | Case- and diacritic-insensitive substring check using `applyingTransform(.stripDiacritics)`; internal helper for `fetchTitleCandidates`. |
| `isoDateOnly` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/DateParsing.swift:251` | Parses `yyyy-MM-dd` anchored to `calendar.timeZone` so midnight is in the user's configured zone, not UTC. |
| `looksLikeHexPrefix` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift:160` | Returns `true` if a string is ≥4 hex characters — routes the token to UUID-prefix resolution instead of title search. |
| `looksLikeTimeToken` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/DateParsing.swift:108` | Returns `true` if a token ends in `am`/`pm` or contains `:`; used to detect trailing time clauses in date strings. |
| `openAppGroup` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/StoreLocator.swift:24` | Opens the app-group store, consulting `MigrationGate` to avoid racing a sync-mode migration; throws `storeUnavailable` if the app group, file, or gate blocks access. |
| `openInMemory` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/StoreLocator.swift:16` | Creates an ephemeral in-memory `PersistenceController`; no side effects on disk; used for tests. |
| `openOnDisk` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/StoreLocator.swift:20` | Opens a `PersistenceController` at an arbitrary on-disk URL with the CLI transaction author; does not consult `MigrationGate`. |
| `parse` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/DateParsing.swift:24` | Primary entry point: tries ISO-8601 date+time, ISO date, relative DSL, then natural-language phrases; returns `Resolved` or throws `LillistError.validationFailed`. |
| `parseRelativeDSL` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/DateParsing.swift:167` | Parses `±N<d|w|m|y>` relative tokens; returns `nil` for non-matching input rather than throwing. |
| `parseWeekdayPhrase` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/DateParsing.swift:193` | Parses `next|last|this <weekday>` phrases; returns `nil` for non-matching input rather than throwing. |
| `passesScope` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift:249` | Post-fetch filter enforcing descendant-scope constraint via parent-chain traversal; guards infinite loops with `PredicateLimits.maxAncestorDepth`. |
| `read` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Config.swift:31` | Parses the config file at `url`; missing file returns defaults; unknown keys are silently skipped; bad known values throw `LillistError.validationFailed`. |
| `resolve` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift:47` | Resolves one token to a single `Resolution` via six-step priority (UUID exact, UUID prefix, exact title, substring); destructive partial matches always throw. |
| `resolveAll` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift:98` | Resolves all tokens sequentially, throwing on the first failure; guarantees zero mutations have occurred before the throw — safe for destructive stdin batches. |
| `resolveBase` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/DateParsing.swift:57` | Resolves a base-phrase token (no time clause) to a `Date` via keyword, relative DSL, or weekday phrase; throws `LillistError.validationFailed` for unrecognized input. |
| `resolveExactUUID` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift:166` | Looks up a full UUID in the scoped fetch; throws `LillistError.notFound` if absent. Internal helper for `resolve`. |
| `resolveUUIDPrefix` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift:183` | Looks up tasks whose UUID (no-dash lowercased) has `prefix` as a prefix; throws `.notFound` or `.ambiguous`. Internal helper for `resolve`. |
| `resolvedCalendar` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Config.swift:23` | Returns a `Calendar` with `timeZone` applied if configured, otherwise `Calendar.current`; pure, no side effects. |
| `shortestUniqueShortIDs` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift:120` | Computes the shortest hex prefix (min 4 chars, no dashes) that uniquely identifies each UUID in the input set; falls back to full hex on unresolvable collision. |
| `splitTime` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/DateParsing.swift:89` | Splits `input` into `(base, time?)` by detecting a trailing ` at <time>` phrase or a trailing time-like token; never throws. |
| `sqlPredicate` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift:234` | Builds an SQL-optimized `NSPredicate` covering `deletedAt == nil` and scope-appropriate status; descendant filtering is deferred to `passesScope` post-fetch. |
| `startOfDay` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/DateParsing.swift:222` | Returns midnight for `d` in `calendar`'s time zone via `Calendar.startOfDay(for:)`. |
| `startOfMonth` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/DateParsing.swift:233` | Returns the first day of the month containing `d` at midnight in `calendar`'s time zone. |
| `startOfWeek` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/DateParsing.swift:225` | Returns the first day of the week containing `d` at midnight in `calendar`'s time zone. |
| `stripQuotes` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Config.swift:86` | Strips matching outer single or double quotes from a string; internal helper, not part of the public API surface. |
| `tagIDs` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/FilterFlags.swift:90` | Resolves tag names to UUIDs via a Core Data fetch; names that match nothing are silently dropped, producing a smaller set rather than throwing. |
| `toPredicateGroup` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/FilterFlags.swift:34` | Translates flags into a `PredicateGroup`; pass `applyTrashImplicit: false` for trash-targeted verbs like `restore` that need to query deleted items. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.applyTime -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.openAppGroup -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceController (owns)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.openAppGroup -> Packages-LillistCore-Sources-LillistCore-Persistence.onDisk (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.openAppGroup -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.FileMigrationJournalStore (reads)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.openAppGroup -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.MigrationGate (reads)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.openAppGroup -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.SyncModeStore (reads)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.openInMemory -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceController (owns)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.openOnDisk -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceController (owns)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.openOnDisk -> Packages-LillistCore-Sources-LillistCore-Persistence.onDisk (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.read -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.read -> Packages-LillistUI-Sources-LillistUI-Recurrence.index (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.shortestUniqueShortIDs -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.splitTime -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.stripQuotes -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.toPredicateGroup -> Packages-LillistCore-Sources-LillistCore-Rules.AttachmentKindMatch (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.toPredicateGroup -> Packages-LillistCore-Sources-LillistCore-Rules.PredicateGroup (calls)`

## Type notes

All types are value types or caseless enums (`Sendable`) safe to cross actor boundaries. `CLIBridge` itself is a caseless enum used purely as a namespace (CLIBridge.swift:9). `Config` is read-once-then-immutable; its hand-written TOML parser ignores unknown keys for forward-compatibility (Config.swift:66-68). `ISO8601DateFormatter` is constructed per-call in `DateParsing.parse` because it is not `Sendable` and cannot live as a static under strict concurrency (DateParsing.swift:32-33). `Resolver.resolve` and `resolveAll` run Core Data fetches via `ctx.perform {}` against `viewContext` (Resolver.swift:172, 188); the SQL predicate prunes the fetch set but descendant-scope is enforced in-memory post-fetch (Resolver.swift:234, 249). `StoreLocator.openAppGroup` falls back to the legacy direct-open path if `FileMigrationJournalStore` cannot be initialised, rather than failing — preserving backward compatibility (StoreLocator.swift:42-47).

## External deps

- CoreData — imported
- Foundation — imported

## Gotchas

`Config.defaultLocation()` uses `NSHomeDirectory()` instead of `FileManager.homeDirectoryForCurrentUser` for iOS portability; on iOS the path is meaningless but harmless (Config.swift:74-78). `ISO8601DateFormatter` is constructed per call in `DateParsing.parse` because it is not `Sendable` and cannot be a static under strict concurrency (DateParsing.swift:31-33). `FilterFlags.tagIDs` silently drops unknown tag names rather than throwing; `toPredicateGroup` produces an empty `uuidSet`, so `lillist ls --tag UnknownTag` returns zero rows without an error (FilterFlags.swift:86-101). `Resolver.sqlPredicate` handles only the SQL-expressible parts of `Scope`; descendant-chain containment is enforced in-memory by `passesScope` because parent-chain traversal cannot be expressed in a SQL predicate (Resolver.swift:234-263).
