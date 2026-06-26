---
module: Packages/LillistCore/Sources/LillistCore/Recurrence
summary: "Recurrence rule model, calendar-aware date expansion, and series-spawn logic"
read_when: "Touching recurrence rules or series spawning"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceExpander.swift
    blob: 8295dbcad3f9a43df5e169e244d796d4d3d7b63a
  - path: Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceLog.swift
    blob: 55b7d80ab7c66ff89937fb4a172e225bc868d3ee
  - path: Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceRule.swift
    blob: 2eccd5ea55c65114c042d959e25ff2de10d92981
  - path: Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceSpawner.swift
    blob: 91043a0cae6e354e0eb9267264606d0f09860c0a
  - path: Packages/LillistCore/Sources/LillistCore/Recurrence/Weekday.swift
    blob: 721acfa8295d34af2f90c59b1561c5fb3c606493
references_modules: [Packages-LillistCore-Sources-LillistCore-ManagedObjects]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistCore/Sources/LillistCore/Recurrence

## Purpose

Defines, serializes, and evaluates recurrence rules for task series. RecurrenceRule models two strategies — a calendar-based RRULE-subset and an after-completion time offset — encoded as JSON in Series.ruleJSON. RecurrenceExpander expands those rules into occurrence dates using Calendar-aware arithmetic, and RecurrenceSpawner materializes the next task instance when a series member closes. Without this module, recurring tasks cannot advance past their first instance.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AfterCompletionRule` | struct | `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceRule.swift:104` | Carries a TimeInterval offset from completion time; interval is absolute seconds (not Calendar-aware); Codable/Sendable value type. |
| `CalendarRule` | struct | `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceRule.swift:21` | RRULE-subset value type; interval is normalized to 1..1000 on init and decode; mutating the interval field directly after construction can violate that invariant. |
| `Frequency` | enum | `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceRule.swift:17` | Persisted as String raw values in JSON; never rename or remove cases without migrating existing serialized data. |
| `RecurrenceExpander` | enum | `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceExpander.swift:9` | Stateless namespace; callers supply a Calendar and receive value-type dates; never mutates its inputs or holds state. |
| `RecurrenceLog` | enum | `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceLog.swift:12` | Provides the os.Logger for recurrence interval-normalization warnings; subsystem string is stable for log filtering in field diagnostics. |
| `RecurrenceRule` | enum | `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceRule.swift:13` | Codable enum with stable 'type' discriminator; never rename discriminator strings without migrating on-disk and CloudKit-synced rule JSON. |
| `RecurrenceSpawner` | enum | `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceSpawner.swift:12` | Internal-visibility namespace; must be invoked inside context.perform on the Core Data context queue; caller owns context.save() after the call. |
| `Weekday` | enum | `Packages/LillistCore/Sources/LillistCore/Recurrence/Weekday.swift:6` | RRULE day-of-week codes persisted as String raw values; never change raw values; calendarComponent bridges to Apple Calendar's Sunday=1 scheme. |
| `clampedInterval` | func | `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceRule.swift:82` | Clamps raw to 1..1000 silently without logging; the shared clamping primitive used by effectiveInterval in the expander and by normalizedInterval on init/decode paths. |
| `encode` | func | `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceRule.swift:132` | Emits a {type, rule} envelope with stable discriminator strings; decode and encode are symmetric and must stay in sync. |
| `nextAfterCompletion` | func | `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceExpander.swift:37` | Returns completedAt + rule.interval in absolute seconds; DST-unsafe by design — use CalendarRule for wall-clock-stable recurrence. |
| `nextOccurrences` | func | `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceExpander.swift:13` | Returns up to min(count, rule.count) dates strictly after seed, stopping at rule.until; returns [] for count <= 0 or an exhausted rule. |
| `spawnIfNeeded` | func | `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceSpawner.swift:24` | Creates the next series task and advances series.nextOccurrenceAfter; returns the spawned UUID for notification reconciliation, or nil if no spawn was needed. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `CodingKeys` | enum | `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceRule.swift:48` | Enables the hand-written CalendarRule decoder that enforces interval normalization; without it the synthesized decoder would bypass normalizedInterval and allow interval=0 to crash or loop-trap the expander (RecurrenceRule.swift:48-65). |
| `CodingKeys` | enum | `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceRule.swift:111` | Defines the stable 'type'/'rule' discriminator keys for RecurrenceRule's Codable envelope; changing these keys silently breaks all persisted and CloudKit-synced rule JSON (RecurrenceRule.swift:111-114). |
| `advance` | func | `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceSpawner.swift:100` | Dispatches both rule variants to RecurrenceExpander and writes the result to series.nextOccurrenceAfter; sole gatekeeper for series date advancement, called on every spawn cycle (RecurrenceSpawner.swift:100-116). |
| `step` | func | `Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceExpander.swift:56` | Central frequency dispatcher for `nextOccurrences`: its single call site (RecurrenceExpander.swift:25) drives the entire calendar-aware expansion loop. Routes `.daily` inline and delegates `.weekly`/`.monthly`/`.yearly` to their respective steppers — removing or misrouting it would silently break all non-daily recurrence expansion without a compile error. |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-Recurrence.deepCopy -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.stampCurrentSchemaVersion (writes)`
- `Packages-LillistCore-Sources-LillistCore-Recurrence.spawnIfNeeded -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.stampCurrentSchemaVersion (writes)`

## Type notes

RecurrenceRule is Codable/Sendable with a hand-written decoder that enforces interval normalization on every decode path, including untrusted CloudKit/Importer/CLI input (RecurrenceRule.swift:56-65). CalendarRule.interval is always in 1..1000 after init or decode; direct field mutation after construction can violate this invariant (RecurrenceRule.swift:82-84). RecurrenceExpander is a pure stateless enum with no actor isolation; all methods are static and safe to call from any context. RecurrenceSpawner is internal-visibility and must be called inside context.perform on the Core Data context queue — it runs synchronously and shares the caller's save (RecurrenceSpawner.swift:6-8). Weekday raw values are persisted in JSON; calendarComponent bridges to Apple Calendar's Sunday=1 scheme (Weekday.swift:15-17). AfterCompletionRule.interval is an absolute TimeInterval in seconds, making it DST-unsafe by design (RecurrenceExpander.swift:41).

## External deps

- CoreData — imported
- Foundation — imported
- os — imported
- previous: — imported

## Gotchas

afterCompletion expansion uses addingTimeInterval (absolute seconds, not Calendar-aware) by design — the rule is defined in seconds (RecurrenceExpander.swift:41). Interval normalization clamps to 1..1000 rather than throwing so a single corrupt CloudKit sync record cannot strip recurrence from the series entirely (RecurrenceRule.swift:93-101). yearlyStep loops up to 40 years to skip months where the exact date does not exist (e.g. Feb 29 on non-leap years), returning nil only if no valid year is found within that window (RecurrenceExpander.swift:229). Count-limit check filters out soft-deleted instances so trashing one instance of a count-bounded series does not permanently exhaust its budget one short (RecurrenceSpawner.swift:129-130).
