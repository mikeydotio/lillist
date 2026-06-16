---
module: Extensions/ShortcutsActions/Entities
summary: "AppEntity + EntityQuery surface exposing tasks to Shortcuts, Spotlight, and Lock Screen"
read_when: Shortcuts task entity
sources:
  - path: Extensions/ShortcutsActions/Entities/StatusAppEnum.swift
    blob: 9014b1f271976eceb9cca9e9307258a7d4dcac9d
  - path: Extensions/ShortcutsActions/Entities/TaskEntity.swift
    blob: 61233f71d3aa63d6858122a3e92651961a03c853
  - path: Extensions/ShortcutsActions/Entities/TaskEntityQuery.swift
    blob: 1187dea2d080b75705127c87e392ee2c50ad0503
references_modules: [Extensions-ShortcutsActions-misc, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistCore-Sources-LillistCore-Model, Packages-LillistCore-Sources-LillistCore-Rules]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
---

# Module: Extensions/ShortcutsActions/Entities

## Purpose

The AppIntents data surface for the Shortcuts extension: it adapts LillistCore's
value-type task records into `AppEntity`/`AppEnum` types the system can show in
Shortcuts, Spotlight, and the Lock Screen. The design idea is a one-way DTO
boundary — `TaskEntity` is constructed from `TaskStore.TaskRecord` so no
`NSManagedObject` crosses into AppIntents land. Remove this module and every
intent loses its typed task parameter and the system loses its task suggestions.

## Public API

These types are referenced across the sibling intent files, but all are
default (module-internal) access — the App Intents extension is a single
compilation unit, so "public surface" here means the entity types intents reach
for.

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `StatusAppEnum` | enum | `Extensions/ShortcutsActions/Entities/StatusAppEnum.swift:4` | `AppEnum` mirror of `Status`; round-trips via `coreStatus` and `init(_:)` |
| `TaskEntity` | struct | `Extensions/ShortcutsActions/Entities/TaskEntity.swift:9` | `AppEntity` for a task; built from `TaskStore.TaskRecord` via `init(_:)` |
| `TaskEntityQuery` | struct | `Extensions/ShortcutsActions/Entities/TaskEntityQuery.swift:14` | `EntityQuery` resolving `TaskEntity` by id and supplying suggestions |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `TaskEntity.init(_:)` | init | `Extensions/ShortcutsActions/Entities/TaskEntity.swift:35` | The DTO seam: converts `TaskStore.TaskRecord` into the entity |
| `StatusAppEnum.coreStatus` | property | `Extensions/ShortcutsActions/Entities/StatusAppEnum.swift:18` | Maps the AppEnum back to LillistCore `Status` for intent writes |
| `entities(for:)` | func | `Extensions/ShortcutsActions/Entities/TaskEntityQuery.swift:15` | Resolves ids to entities; opens a gated store and best-effort fetches |
| `suggestedEntities()` | func | `Extensions/ShortcutsActions/Entities/TaskEntityQuery.swift:27` | Builds the recent-task suggestion list via a predicate evaluation |

## Relationships

- `Extensions-ShortcutsActions-Entities.TaskEntityQuery -> Extensions-ShortcutsActions-misc.IntentSupport (calls)`
- `Extensions-ShortcutsActions-Entities.TaskEntityQuery -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (calls)`
- `Extensions-ShortcutsActions-Entities.TaskEntityQuery -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SmartFilterStore (calls)`
- `Extensions-ShortcutsActions-Entities.TaskEntity -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (reads)`
- `Extensions-ShortcutsActions-Entities.StatusAppEnum -> Packages-LillistCore-Sources-LillistCore-Model.Status (reads)`
- `Extensions-ShortcutsActions-Entities.TaskEntityQuery -> Packages-LillistCore-Sources-LillistCore-Rules.PredicateGroup (calls)`
- `Extensions-ShortcutsActions-Entities.TaskEntityQuery -> Packages-LillistCore-Sources-LillistCore-Rules.Leaf (calls)`

## Type notes

`TaskEntity` is value-typed (`struct`) and `Identifiable` on `UUID`
(`Extensions/ShortcutsActions/Entities/TaskEntity.swift:9-10`); its
`@Property` fields are what Shortcuts shows. `defaultQuery` wires the entity to
`TaskEntityQuery` (`Extensions/ShortcutsActions/Entities/TaskEntity.swift:24`).
`StatusAppEnum` conforms to `AppEnum` and is isomorphic to the concrete
LillistCore `Status` enum; the two are kept in lockstep by `init(_:)` and
`coreStatus`, so adding a status requires editing both ends of the switch
(`Extensions/ShortcutsActions/Entities/StatusAppEnum.swift:18-34`).
Both query methods are `async throws`: persistence is acquired through the
shared gated factory, and `entities(for:)` swallows per-id fetch failures
(`try?`) so one missing task does not abort the batch
(`Extensions/ShortcutsActions/Entities/TaskEntityQuery.swift:20`), while a gate
abort propagates `LillistError.storeUnavailable` out of either method.

## External deps

- AppIntents — `AppEntity`, `AppEnum`, `EntityQuery`, `@Property`, `DisplayRepresentation`
- Foundation — `UUID`, `Date` field types on `TaskEntity`
