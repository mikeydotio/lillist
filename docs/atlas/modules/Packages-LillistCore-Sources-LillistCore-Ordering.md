---
module: Packages/LillistCore/Sources/LillistCore/Ordering
summary: "Gap-based fractional ordering math and canonical sibling sort for reorderable rows"
read_when: "row reorder position math"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/Ordering/FractionalPosition.swift
  - path: Packages/LillistCore/Sources/LillistCore/Ordering/PositionCompactor.swift
  - path: Packages/LillistCore/Sources/LillistCore/Ordering/SiblingOrder.swift
references_modules: [Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistUI-Sources-LillistUI-iOS-Tasks, Apps-Lillist-macOS-Sources-Views-TaskList]
generator: cartographer/1 model=claude-sonnet-4-6
---

# Module: Packages/LillistCore/Sources/LillistCore/Ordering

## Purpose

Pure, stateless arithmetic for ordering reorderable sibling rows (tasks, tags,
smart filters) by a `Double` position. The design idea: insert a new row at the
midpoint of its neighbors' positions so reordering never renumbers the whole
list — accepting that repeated bisection eventually underflows and must be
healed by recompaction. These three enums are the single source of truth for
position math and tie-broken sort order; without them every store would
reinvent (and drift on) the same fragile float arithmetic.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `FractionalPosition` | enum | `Packages/LillistCore/Sources/LillistCore/Ordering/FractionalPosition.swift:9` | Namespace for gap-based position math; all methods `static`, no state |
| `FractionalPosition.anchorsAreOutOfOrder(after:before:)` | func | `Packages/LillistCore/Sources/LillistCore/Ordering/FractionalPosition.swift:36` | True when two real anchors are equal/inverted; nil anchor (list end) is never out of order |
| `FractionalPosition.gapIsTooSmall(after:before:)` | func | `Packages/LillistCore/Sources/LillistCore/Ordering/FractionalPosition.swift:27` | True when `before - after <= after.ulp * 4`, i.e. bisection would underflow |
| `FractionalPosition.needsCompaction(after:before:)` | func | `Packages/LillistCore/Sources/LillistCore/Ordering/FractionalPosition.swift:46` | True only when both neighbors are real and `gapIsTooSmall`; head/tail inserts return false |
| `FractionalPosition.position(after:before:)` | func | `Packages/LillistCore/Sources/LillistCore/Ordering/FractionalPosition.swift:12` | Position for a new row: midpoint of neighbors, `±1.0` at ends, `1.0` for empty |
| `PositionCompactor` | enum | `Packages/LillistCore/Sources/LillistCore/Ordering/PositionCompactor.swift:8` | Namespace for position re-spacing; method is `static`, no state |
| `PositionCompactor.recompact(positions:)` | func | `Packages/LillistCore/Sources/LillistCore/Ordering/PositionCompactor.swift:9` | Re-spaces an already-ordered list to even gaps of 1.0 (`1...count`); preserves order |
| `SiblingOrder` | enum | `Packages/LillistCore/Sources/LillistCore/Ordering/SiblingOrder.swift:11` | Namespace for the canonical sibling sort; method is `static`, no state |
| `SiblingOrder.precedes(positionA:idA:positionB:idB:)` | func | `Packages/LillistCore/Sources/LillistCore/Ordering/SiblingOrder.swift:12` | Canonical order: position ascending, then `id.uuidString` ascending on ties |

## Load-bearing internals

None — every symbol in this module is public surface.

## Relationships

- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore -> Packages-LillistCore-Sources-LillistCore-Ordering.FractionalPosition (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore -> Packages-LillistCore-Sources-LillistCore-Ordering.PositionCompactor (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore -> Packages-LillistCore-Sources-LillistCore-Ordering.SiblingOrder (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SmartFilterStore -> Packages-LillistCore-Sources-LillistCore-Ordering.FractionalPosition (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SmartFilterStore -> Packages-LillistCore-Sources-LillistCore-Ordering.PositionCompactor (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SmartFilterStore -> Packages-LillistCore-Sources-LillistCore-Ordering.SiblingOrder (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TagStore -> Packages-LillistCore-Sources-LillistCore-Ordering.FractionalPosition (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.TaskTree -> Packages-LillistCore-Sources-LillistCore-Ordering.SiblingOrder (calls)`
- `Apps-Lillist-macOS-Sources-Views-TaskList.TaskListView -> Packages-LillistCore-Sources-LillistCore-Ordering.SiblingOrder (calls)`

## Type notes

All three types are caseless `enum`s used as static namespaces — they hold no
state, are never instantiated, and every method is `public static`, so any
isolation context (MainActor views, background store actors, tests) can call
them freely.

`recompact` is order-preserving, not order-defining: it normalizes values but
trusts the caller to pass an already-sorted list — typically the output of
`SiblingOrder.precedes` (`Packages/LillistCore/Sources/LillistCore/Ordering/PositionCompactor.swift:5`).

The compaction protocol is a contract split across `FractionalPosition`:
`needsCompaction` gates whether the caller must run `PositionCompactor.recompact`
on siblings before recomputing a target with `position`, and head/tail inserts
(a nil neighbor) place at `±1.0` and never collide
(`Packages/LillistCore/Sources/LillistCore/Ordering/FractionalPosition.swift:42`).

## External deps

- Foundation — `UUID` for the `SiblingOrder` tie-break key; `Double.ulp` for the gap threshold

## Gotchas

- Never sort the UUID `id` via `NSSortDescriptor`: Core Data orders UUIDs as raw bytes, which is not guaranteed to equal Swift's `uuidString` lexical order — always sort in Swift in-memory (`Packages/LillistCore/Sources/LillistCore/Ordering/SiblingOrder.swift:8`).
