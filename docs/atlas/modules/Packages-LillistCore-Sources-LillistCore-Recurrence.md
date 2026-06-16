---
module: Packages/LillistCore/Sources/LillistCore/Recurrence
summary: "Recurrence model, pure-Swift occurrence expansion, and next-instance spawning for Series"
read_when: "Recurrence rules & spawning"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceExpander.swift
    blob: 8295dbcad3f9a43df5e169e244d796d4d3d7b63a
  - path: Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceLog.swift
    blob: 68f88ca6008fc34d527971db67145b4e59ef9f04
  - path: Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceRule.swift
    blob: 2eccd5ea55c65114c042d959e25ff2de10d92981
  - path: Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceSpawner.swift
    blob: 929d8f5ad9841970801b8eec49d47b6b7a8ddaf2
  - path: Packages/LillistCore/Sources/LillistCore/Recurrence/Weekday.swift
    blob: 721acfa8295d34af2f90c59b1561c5fb3c606493
references_modules: [Packages-LillistCore-Sources-LillistCore-ManagedObjects, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistUI-Sources-LillistUI-Recurrence]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
---

# Module: Packages/LillistCore/Sources/LillistCore/Recurrence

## Purpose

The recurrence engine: the `RecurrenceRule` value type that a `Series` persists,
the pure-Swift `RecurrenceExpander` that turns a rule into occurrence dates, and
the `RecurrenceSpawner` that mints the next instance when a task closes. The
design idea is a hard split between the Codable rule (durable, sync-safe) and the
stateless calendar math (DST- and month-length-correct via `Calendar`, never
`addingTimeInterval`). If it vanished, recurring tasks would never advance and
stored rule JSON would have no decoder.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `RecurrenceExpander` | enum | `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceExpander.swift:9` | Stateless namespace; pure occurrence math, no I/O |
| `RecurrenceExpander.nextAfterCompletion(completedAt:rule:)` | func | `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceExpander.swift:37` | Next date = completion + rule interval (absolute seconds) |
| `RecurrenceExpander.nextOccurrences(after:rule:calendar:count:)` | func | `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceExpander.swift:13` | Up to `count` dates strictly after seed; honors rule `count`/`until` |
| `RecurrenceRule` | enum | `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceRule.swift:13` | `.calendar`/`.afterCompletion`; Codable into `Series.ruleJSON` |
| `RecurrenceRule.AfterCompletionRule` | struct | `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceRule.swift:104` | Fixed `TimeInterval` measured from previous close |
| `RecurrenceRule.CalendarRule` | struct | `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceRule.swift:21` | RRULE subset; `interval` clamped to `1...maxInterval` on init/decode |
| `RecurrenceRule.Frequency` | enum | `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceRule.swift:17` | `daily`/`weekly`/`monthly`/`yearly`; raw strings persisted |
| `Weekday` | enum | `Packages/LillistCore/Sources/LillistCore/Recurrence/Weekday.swift:6` | Two-letter RRULE codes; bridges to `Calendar` via `calendarComponent` |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `RecurrenceSpawner` | enum | `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceSpawner.swift:12` | Internal; bridges expander math to Core Data instance creation |
| `RecurrenceSpawner.spawnIfNeeded(forClosedTask:in:)` | func | `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceSpawner.swift:24` | Sole spawn entry; runs inside caller's `context.perform`, returns spawn `UUID?` |
| `RecurrenceSpawner.advance(rule:lastOccurrence:completedAt:)` | func | `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceSpawner.swift:98` | Dispatches both rule variants to the expander to set `nextOccurrenceAfter` |
| `RecurrenceExpander.step(from:rule:calendar:)` | func | `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceExpander.swift:56` | Frequency dispatch; all daily/weekly/monthly/yearly stepping fans in here |
| `CalendarRule.clampedInterval(_:)` | func | `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceRule.swift:82` | Silent two-sided interval clamp; expander's defense-in-depth at every step |
| `RecurrenceLog` | enum | `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceLog.swift:12` | os.Logger destination for trust-boundary interval normalization warnings |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TaskStore -> Packages-LillistCore-Sources-LillistCore-Recurrence.RecurrenceSpawner (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SeriesStore -> Packages-LillistCore-Sources-LillistCore-Recurrence.RecurrenceExpander (calls)`
- `Packages-LillistCore-Sources-LillistCore-ManagedObjects.Series -> Packages-LillistCore-Sources-LillistCore-Recurrence.RecurrenceRule (reads)`
- `Packages-LillistCore-Sources-LillistCore-Recurrence.RecurrenceSpawner -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.LillistTask (writes)`
- `Packages-LillistCore-Sources-LillistCore-Recurrence.RecurrenceSpawner -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.Series (reads)`
- `Packages-LillistUI-Sources-LillistUI-Recurrence.RecurrenceEditorViewModel -> Packages-LillistCore-Sources-LillistCore-Recurrence.RecurrenceRule (writes)`
- `Packages-LillistCore-Sources-LillistCore-Recurrence.RecurrenceSpawner -> Packages-LillistCore-Sources-LillistCore-Recurrence.RecurrenceExpander (calls)`
- `Packages-LillistCore-Sources-LillistCore-Recurrence.RecurrenceRule -> Packages-LillistCore-Sources-LillistCore-Recurrence.RecurrenceLog (writes)`

## Type notes

`RecurrenceRule` and its nested types are `Codable`, `Sendable`, value types — no
Core Data escapes this module. A `type` discriminator (`Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceRule.swift:111`)
distinguishes the two variants in JSON; its values must never be renamed.
`CalendarRule` has a hand-written decoder (`Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceRule.swift:56`)
so untrusted JSON funnels through the same interval normalization as the
memberwise init; the invariant is `interval` always in `1...maxInterval`, enforced
at `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceRule.swift:93`.
`RecurrenceExpander` is a stateless enum namespace with only static funcs.
`RecurrenceSpawner.spawnIfNeeded` assumes it runs synchronously on the caller's
managed-object-context queue inside `context.perform`, and the caller owns the
subsequent `save()` (`Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceSpawner.swift:24`);
re-opening a closed task never spawns.

## External deps

- Foundation — `Calendar`/`DateComponents` drive all occurrence math; `Codable` for rule JSON
- CoreData — `RecurrenceSpawner` creates/reads `NSManagedObject` instances (`LillistTask`, `Series`)
- os — `Logger` backs `RecurrenceLog` for normalization warnings

## Gotchas

- `interval == 0` divide-by-zero-crashes the monthly expander and loop-traps daily/weekly; a negative walks backwards forever — clamped, not thrown, at `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceRule.swift:93`.
- `clampedInterval` is re-applied silently at every expander step even post-construction, since a rule's `interval` can be forced out of range after init (`Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceExpander.swift:52`).
- `byMonthDay = 31` skips short months rather than coercing to the 30th (`Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceExpander.swift:195`).
- `countReached` excludes soft-deleted instances so trashing one doesn't stall a `count = N` series one short (`Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceSpawner.swift:121`).
- `Weekday` raw values and `calendarComponent` bridge Lillist's Monday-first order to Apple's Sunday=1 scheme; never renumber (`Packages/LillistCore/Sources/LillistCore/Recurrence/Weekday.swift:18`).
