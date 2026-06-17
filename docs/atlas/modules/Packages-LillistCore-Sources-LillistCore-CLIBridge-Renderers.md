---
module: Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers
summary: "Serializes store DTOs into the CLI's json/ndjson/tsv/pretty output formats"
read_when: "lillist CLI output format"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/FilterRenderer.swift
    blob: 751ad48396684b394771f92078d1e4ff8af3887f
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/JournalRenderer.swift
    blob: facea689a166003da677132304e1eeb8f4b4433c
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TagRenderer.swift
    blob: 95a9efc7b3fd0fa5dbbdcea0cfdb0663e35ca147
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TaskRenderer.swift
    blob: 0ef33ce9e0dd81909afeb708247b92db04a54fb9
references_modules: [Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Model, Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2]
generator: cartographer/1
baseline: 34dfea7772679dbabc08fabd6fbba53f6ad5856b
---

# Module: Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers

## Purpose

The presentation layer of the `lillist` CLI. Each renderer is a stateless
`public enum` nested under `CLIBridge` that turns a store's value-type record
into one of the CLI's output formats — JSON, NDJSON, TSV, or a colorized pretty
tree. The renderers own the wire shape of every machine-readable CLI surface:
the `*DTO` structs decouple stable, sorted-key JSON field names from the
internal `*Record` layout, so a store schema change does not silently reshape
scriptable output.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `FilterRenderer` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/FilterRenderer.swift:4` | Renders smart-filter summaries for the filters list command |
| `FilterRenderer.PrettyFilterSummary` | struct | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/FilterRenderer.swift:5` | Value-type view-model a caller builds from a filter record; explicit public init |
| `FilterRenderer.prettyList(_:color:)` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/FilterRenderer.swift:22` | Human-readable one-line-per-filter listing |
| `JournalRenderer` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/JournalRenderer.swift:4` | Renders journal entries for the show command |
| `JournalRenderer.JournalDTO` | struct | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/JournalRenderer.swift:5` | Codable JSON mirror of `JournalRecord` |
| `JournalRenderer.json(_:)` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/JournalRenderer.swift:22` | Pretty-printed sorted-keys ISO8601 JSON `Data` |
| `JournalRenderer.prettyList(_:color:)` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/JournalRenderer.swift:29` | `[when] kind: body` lines |
| `TagRenderer` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TagRenderer.swift:4` | Renders tag records to all four formats |
| `TagRenderer.TagDTO` | struct | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TagRenderer.swift:5` | Codable JSON mirror of `TagRecord` |
| `TagRenderer.json(_:)` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TagRenderer.swift:20` | Pretty-printed sorted-keys JSON `Data` |
| `TagRenderer.ndjson(_:)` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TagRenderer.swift:27` | One sorted-keys JSON object per line, trailing newline |
| `TagRenderer.prettyTree(_:color:)` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TagRenderer.swift:46` | Indented `#name` hierarchy, optional ANSI tint |
| `TagRenderer.tsv(_:)` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TagRenderer.swift:38` | `id\tname\tparentID\ttintColor` rows |
| `TaskRenderer` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TaskRenderer.swift:5` | Renders task records to all four formats |
| `TaskRenderer.TaskDTO` | struct | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TaskRenderer.swift:7` | Codable JSON mirror of `TaskRecord`; reused by `WatchHandler` events |
| `TaskRenderer.json(_:)` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TaskRenderer.swift:45` | Pretty-printed sorted-keys ISO8601 JSON `Data` |
| `TaskRenderer.jsonString(_:)` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TaskRenderer.swift:53` | UTF-8 string form of `json(_:)` |
| `TaskRenderer.ndjson(_:)` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TaskRenderer.swift:59` | One sorted-keys JSON object per line, trailing newline |
| `TaskRenderer.prettyTree(_:color:)` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TaskRenderer.swift:94` | Indented status-glyph tree of tasks |
| `TaskRenderer.tsv(_:)` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TaskRenderer.swift:73` | `id\ttitle\tstatus\tstart\tdeadline\tisPinned\tparentID` rows |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `TaskRenderer.statusGlyph(_:color:)` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TaskRenderer.swift:129` | Maps each `Status` to its glyph + ANSI code; sole color source for the task tree |
| `TaskRenderer.renderNode(...)` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TaskRenderer.swift:114` | Recursive depth-first walk that emits the indented task tree |
| `TagRenderer.render(...)` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TagRenderer.swift:60` | Recursive walk emitting the indented tag tree |
| `TagRenderer.ansiFor(hex:)` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TagRenderer.swift:73` | Crude hex→cyan stub; any non-empty tint becomes one ANSI color |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers.TaskRenderer -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TaskRecord (reads)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers.TagRenderer -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TagRecord (reads)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers.JournalRenderer -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.JournalRecord (reads)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers.TaskRenderer -> Packages-LillistCore-Sources-LillistCore-Model.Status (reads)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers.FilterRenderer -> Packages-LillistCore-Sources-LillistCore-Model.SortField (reads)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.WatchHandler -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers.TaskRenderer (calls)`

## Type notes

All four renderers are `public enum` namespaces with only `static` members — no
instances, no shared state; each call is pure given its input records. The
`*DTO` structs are `Codable, Sendable, Equatable` and built only via
`init(from:)` from a store record, so JSON field names live here, independent of
the record layout. `prettyTree` (`TaskRenderer.swift:94`, `TagRenderer.swift:46`)
reparents orphans: a record whose `parentID` points outside the visible set is
promoted to a root, so a filtered subset still renders as a forest. Children are
ordered by `position` ascending. `PrettyFilterSummary`
(`FilterRenderer.swift:5`) is the only renderer input that is not a store DTO —
the caller assembles it, since `FilterRenderer` has no JSON path of its own.

## External deps

- Foundation — `JSONEncoder` (`.sortedKeys`/`.prettyPrinted`/`.iso8601`), `ISO8601DateFormatter`, `UUID`, `Data`

## Gotchas

- `TagRenderer.ansiFor(hex:)` is a stub: any non-empty hex collapses to cyan, ignoring the actual color (`Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TagRenderer.swift:73`).
- `FilterRenderer.prettyList` and `JournalRenderer.prettyList` accept a `color:` flag but never apply ANSI; the parameter is currently inert (`Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/FilterRenderer.swift:22`, `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/JournalRenderer.swift:29`).
