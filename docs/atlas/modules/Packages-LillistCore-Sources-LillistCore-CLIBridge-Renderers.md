---
module: Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers
summary: "CLI output formatters: convert store records to JSON/NDJSON/TSV/pretty-text for the lillist CLI."
read_when: "Touching lillist CLI output format"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/FilterRenderer.swift
    blob: 751ad48396684b394771f92078d1e4ff8af3887f
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/JournalRenderer.swift
    blob: facea689a166003da677132304e1eeb8f4b4433c
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TagRenderer.swift
    blob: 95a9efc7b3fd0fa5dbbdcea0cfdb0663e35ca147
  - path: Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TaskRenderer.swift
    blob: 0ef33ce9e0dd81909afeb708247b92db04a54fb9
references_modules: [Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistUI-Sources-LillistUI-Recurrence]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers

## Purpose

Renderers is the output layer of the CLI bridge: four stateless enum namespaces (`TaskRenderer`, `TagRenderer`, `JournalRenderer`, `FilterRenderer`) each accept store value-type records and produce one of four formats — JSON, NDJSON, TSV, or pretty-printed ANSI text. Each renderer owns a `Codable` DTO that flattens enum fields (e.g. `Status`, journal `kind`) to their string descriptions so JSON output is stable across internal type changes. Without this module the CLI and Shortcuts layer have no path to serialize or display retrieved data.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/FilterRenderer.swift:3` | Namespace extension that nests `FilterRenderer` inside `CLIBridge`; callers access it as `CLIBridge.FilterRenderer`. |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/JournalRenderer.swift:3` | Namespace extension that nests `JournalRenderer` inside `CLIBridge`. |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TagRenderer.swift:3` | Namespace extension that nests `TagRenderer` inside `CLIBridge`. |
| `CLIBridge` | extension | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TaskRenderer.swift:3` | Namespace extension that nests `TaskRenderer` inside `CLIBridge`; the largest renderer with four output formats and status glyphs. |
| `FilterRenderer` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/FilterRenderer.swift:4` | Stateless formatter for smart filter summaries; only a pretty-text path exists — no JSON, NDJSON, or TSV output. |
| `JournalDTO` | struct | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/JournalRenderer.swift:5` | Codable bridge from `JournalStore.JournalRecord`; `kind` is flattened to `String(describing:)` for stable JSON serialization. |
| `JournalRenderer` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/JournalRenderer.swift:4` | Stateless formatter for journal records; provides JSON (ISO8601 dates, sorted keys, pretty-printed) and plain-text paths. |
| `PrettyFilterSummary` | struct | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/FilterRenderer.swift:5` | Carry type for filter display data; `Sendable, Equatable`, no `Codable`; callers must use the explicit public `init`. |
| `TagDTO` | struct | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TagRenderer.swift:5` | Codable bridge from `TagStore.TagRecord`; preserves `parentID`, `position`, and optional `tintColor` as a hex string. |
| `TagRenderer` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TagRenderer.swift:4` | Stateless formatter for tag records: JSON, NDJSON, TSV, and a `prettyTree` that renders the parent-child hierarchy with optional ANSI color. |
| `TaskDTO` | struct | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TaskRenderer.swift:7` | Codable bridge from `TaskStore.TaskRecord`; `status` is `String(describing:)` for stable JSON; all date fields encode as ISO8601. |
| `TaskRenderer` | enum | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TaskRenderer.swift:5` | Stateless formatter for task records: JSON, NDJSON, TSV, and pretty-tree with Unicode status glyphs and optional ANSI color. |
| `ansiFor` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TagRenderer.swift:73` | Maps a non-empty hex string to a fixed cyan ANSI escape; returns nil for empty. Intentionally approximate — signal-only. |
| `json` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/JournalRenderer.swift:22` | Encodes journal records as sorted-key, pretty-printed ISO8601 JSON `Data`; throws if `JSONEncoder.encode` fails. |
| `json` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TagRenderer.swift:20` | Encodes tag records as sorted-key, pretty-printed JSON `Data`; throws if `JSONEncoder.encode` fails. |
| `json` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TaskRenderer.swift:45` | Encodes task records as sorted-key, pretty-printed ISO8601 JSON `Data`; throws if `JSONEncoder.encode` fails. |
| `jsonString` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TaskRenderer.swift:53` | UTF-8 string wrapper around `json(_:)`; returns an empty string on encoding failure rather than propagating. |
| `ndjson` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TagRenderer.swift:27` | One JSON object per record per line, sorted keys, trailing newline when non-empty; throws if `JSONEncoder.encode` fails. |
| `ndjson` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TaskRenderer.swift:59` | One task JSON object per line, ISO8601 dates, sorted keys, trailing newline when non-empty; throws if `JSONEncoder.encode` fails. |
| `prettyList` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/FilterRenderer.swift:22` | Returns multiline plain-text with name, pin flag, sort field, and direction per filter; never throws. |
| `prettyList` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/JournalRenderer.swift:29` | Returns records as ISO8601-timestamped lines of the form `[when] kind: body`; never throws. |
| `prettyTree` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TagRenderer.swift:46` | Depth-first, position-sorted tree; roots are records with nil parent or whose parent is absent from the input set; never throws. |
| `prettyTree` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TaskRenderer.swift:94` | Depth-first, position-sorted tree; roots are records with nil parent or parent absent from input set; never throws. |
| `render` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TagRenderer.swift:60` | Recursive helper: appends one indented `#name` line with optional ANSI color then recurses into children from `byParent`. |
| `renderNode` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TaskRenderer.swift:114` | Recursive internal helper: appends `indent + statusGlyph + title` then recurses into children from the pre-built `byParent` map. |
| `statusGlyph` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TaskRenderer.swift:129` | Maps `Status` to a Unicode circle glyph (todo/started/blocked/closed) with optional ANSI color (white/yellow/red/green). |
| `tsv` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TagRenderer.swift:38` | Header row plus tab-separated id/name/parentID/tintColor rows; never throws. |
| `tsv` | func | `Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TaskRenderer.swift:73` | Header plus tab-separated id/title/status/start/deadline/isPinned/parentID rows; declared `throws` but body never throws. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers.JournalDTO -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers.TaskDTO -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers.jsonString -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers.ndjson -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers.prettyList -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers.render -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers.renderNode -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers.tsv -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers.tsv -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`

## Type notes

All renderer types are caseless `enum`s (namespace-only pattern) nested inside `extension CLIBridge` — no instances, no state, no actor isolation required. DTO types (`TaskDTO`, `TagDTO`, `JournalDTO`) are `Codable, Sendable, Equatable` and each exposes `init(from:)` that bridges the store record to stable field names; `PrettyFilterSummary` is `Sendable, Equatable` only because filter rendering has no JSON path. `JSONEncoder` is allocated per call; batch JSON paths use `.sortedKeys, .prettyPrinted` (`Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TaskRenderer.swift:48-49`); NDJSON paths use `.sortedKeys` only for compact single-line output (`Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TaskRenderer.swift:61`). Dates are ISO8601 in all JSON/NDJSON paths (`Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/JournalRenderer.swift:25`); tags omit date encoding because `TagDTO` has no date fields.

## External deps

- Foundation — imported

## Gotchas

`TagRenderer.ansiFor(hex:)` maps every non-empty hex to a single cyan ANSI escape regardless of actual hue; a source comment acknowledges this as intentional signal-only coloring (`Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TagRenderer.swift:74`). `TaskRenderer.tsv` is declared `throws` but its body contains no throwing calls — callers must `try` unnecessarily (`Packages/LillistCore/Sources/LillistCore/CLIBridge/Renderers/TaskRenderer.swift:73`).
