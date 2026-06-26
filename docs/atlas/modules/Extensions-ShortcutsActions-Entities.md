---
module: Extensions/ShortcutsActions/Entities
summary: "App Intents entity layer: TaskEntity, StatusAppEnum, and EntityQuery bridge LillistCore DTOs to Shortcuts/Spotlight"
read_when: "Touching Shortcuts task entity or query"
sources:
  - path: Extensions/ShortcutsActions/Entities/StatusAppEnum.swift
    blob: 9014b1f271976eceb9cca9e9307258a7d4dcac9d
  - path: Extensions/ShortcutsActions/Entities/TaskEntity.swift
    blob: 61233f71d3aa63d6858122a3e92651961a03c853
  - path: Extensions/ShortcutsActions/Entities/TaskEntityQuery.swift
    blob: 1187dea2d080b75705127c87e392ee2c50ad0503
references_modules: [Packages-LillistCore-Sources-LillistCore-Rules]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Extensions/ShortcutsActions/Entities

## Purpose

This module is the App Intents entity layer: it exposes LillistCore tasks to Shortcuts, Spotlight, and Lock Screen by wrapping internal DTO types (TaskStore.TaskRecord, Status) as AppEntity and AppEnum conformances the framework can serialize, display, and resolve. TaskEntityQuery bridges the two worlds at query time, using IntentSupport.makePersistence() to acquire a MigrationGate-gated, syncMode-aware store before any lookup. Without this module, no Shortcuts action could reference or suggest Lillist tasks by name.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `StatusAppEnum` | enum | `Extensions/ShortcutsActions/Entities/StatusAppEnum.swift:4` | Bidirectional AppEnum bridge: callers get four Shortcuts-displayable status cases and convert to LillistCore.Status via `coreStatus`, or wrap a Status via init(_:). |
| `TaskEntity` | struct | `Extensions/ShortcutsActions/Entities/TaskEntity.swift:9` | Immutable AppEntity snapshot of a task; callers may bind id, title, status, and deadline as Shortcuts parameters and round-trip through TaskEntityQuery. |
| `TaskEntity` | extension | `Extensions/ShortcutsActions/Entities/TaskEntity.swift:34` | Convenience init from TaskStore.TaskRecord; constructs a TaskEntity without manual field mapping, guaranteed non-failable for any valid record. |
| `TaskEntityQuery` | struct | `Extensions/ShortcutsActions/Entities/TaskEntityQuery.swift:14` | EntityQuery conformance point; acquires a gated persistence store per call via IntentSupport.makePersistence() — no shared state is retained between invocations. |
| `entities` | func | `Extensions/ShortcutsActions/Entities/TaskEntityQuery.swift:15` | Resolves task UUIDs to TaskEntity values; missing IDs are silently skipped; throws LillistError.storeUnavailable if MigrationGate aborts store acquisition. |
| `suggestedEntities` | func | `Extensions/ShortcutsActions/Entities/TaskEntityQuery.swift:27` | Returns up to 20 non-trashed, non-closed tasks sorted by most-recently-modified for Shortcuts dynamic entity suggestions. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

- `Extensions-ShortcutsActions-Entities.suggestedEntities -> Packages-LillistCore-Sources-LillistCore-Rules.Leaf (calls)`
- `Extensions-ShortcutsActions-Entities.suggestedEntities -> Packages-LillistCore-Sources-LillistCore-Rules.PredicateGroup (calls)`

## Type notes

All three types are value types (struct/enum) with no actor isolation — AppIntents invokes them off-main on the cooperative thread pool. TaskEntity.swift:9-32: @Property macros on title, status, and deadline expose those fields as Shortcuts-parameterizable; the bare id field satisfies Identifiable with a UUID. StatusAppEnum.swift:18-25: `coreStatus` converts to LillistCore.Status; StatusAppEnum.swift:27-34: init(_ status: Status) makes the mapping symmetric and exhaustive at compile time. TaskEntityQuery.swift:15-26: persistence is acquired per call with no shared mutable state, keeping query invocations independently threadsafe.

## External deps

- AppIntents — imported
- Foundation — imported
- LillistCore — imported

## Gotchas

Extensions/ShortcutsActions/Entities/TaskEntityQuery.swift:6-13 documents that when MigrationGate aborts, IntentSupport.makePersistence() throws LillistError.storeUnavailable; this propagates through both `entities` and `suggestedEntities` so Shortcuts surfaces a retry message rather than operating on a half-swapped store. The suggested-entities filter is hardcoded inline (TaskEntityQuery.swift:30-35) and not backed by a user SmartFilter — changing the suggestion heuristic requires a code change.
