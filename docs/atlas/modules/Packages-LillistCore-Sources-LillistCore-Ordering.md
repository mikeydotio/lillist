---
module: Packages/LillistCore/Sources/LillistCore/Ordering
summary: "Fractional-index ordering math: midpoint insertion, underflow detection, compaction, and canonical sibling sort."
read_when: "Touching row reorder or position compaction"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/Ordering/FractionalPosition.swift
    blob: 6fbaf3984109921be4e307d398ad898e7862c2fe
  - path: Packages/LillistCore/Sources/LillistCore/Ordering/PositionCompactor.swift
    blob: 3d0bf5e1c4d35ae2c6804e901366317858e98e04
  - path: Packages/LillistCore/Sources/LillistCore/Ordering/SiblingOrder.swift
    blob: ad5e6ff0259801e3fe4c769c3e1122c0dcb7782d
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistCore/Sources/LillistCore/Ordering

## Purpose

Provides the pure mathematics for fractional-index row ordering: computing midpoint insertion positions, detecting floating-point underflow that requires compaction, renormalizing positions after compaction, and defining the canonical tie-breaking sort order for siblings. All three types are caseless enum namespaces with no mutable state, making them safely callable from any actor or context. If this module vanished, every insertion, drag-reorder, and sort across TaskStore and its presenters would need independent ad-hoc midpoint logic with no shared underflow or tie-break guarantees.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `FractionalPosition` | enum | `Packages/LillistCore/Sources/LillistCore/Ordering/FractionalPosition.swift:9` | Namespace for fractional-index ordering math; callers use its four static functions and never instantiate it. |
| `PositionCompactor` | enum | `Packages/LillistCore/Sources/LillistCore/Ordering/PositionCompactor.swift:8` | Namespace for position normalization after compaction; callers use `recompact` and never instantiate it. |
| `SiblingOrder` | enum | `Packages/LillistCore/Sources/LillistCore/Ordering/SiblingOrder.swift:11` | Namespace for canonical sibling comparison used by all presenters; callers use `precedes` and never instantiate it. |
| `anchorsAreOutOfOrder` | func | `Packages/LillistCore/Sources/LillistCore/Ordering/FractionalPosition.swift:36` | Returns `true` when both anchors are non-nil and `after >= before`; a nil anchor means list-end and always returns `false`. |
| `gapIsTooSmall` | func | `Packages/LillistCore/Sources/LillistCore/Ordering/FractionalPosition.swift:27` | Returns `true` when `before - after` <= `after.ulp * 4`; caller must pass `after < before` — the check is magnitude-adaptive, not a fixed epsilon. |
| `needsCompaction` | func | `Packages/LillistCore/Sources/LillistCore/Ordering/FractionalPosition.swift:46` | Returns `true` only when both neighbors are non-nil and their gap is too small to bisect safely; nil (head/tail insert) always returns `false`. |
| `position` | func | `Packages/LillistCore/Sources/LillistCore/Ordering/FractionalPosition.swift:12` | Returns midpoint of `after` and `before` when both are non-nil; `after + 1.0` when `before` is nil; `before - 1.0` when `after` is nil; `1.0` for an empty list. |
| `precedes` | func | `Packages/LillistCore/Sources/LillistCore/Ordering/SiblingOrder.swift:12` | Returns `true` when A sorts before B: position ascending, then `uuidString` ascending on ties; must replace any `NSSortDescriptor` on the UUID attribute. |
| `recompact` | func | `Packages/LillistCore/Sources/LillistCore/Ordering/PositionCompactor.swift:9` | Takes a pre-sorted slice of positions and returns `[1.0, 2.0, ..., n.0]`; caller must sort the input — order is preserved, values are renumbered from 1. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

All three types (`FractionalPosition`, `PositionCompactor`, `SiblingOrder`) are caseless `enum` namespaces — no instances, no stored state, all operations are pure static functions. No actor isolation is declared or required; callers on any actor invoke these freely without crossing an isolation boundary. `FractionalPosition.gapIsTooSmall` uses `after.ulp * 4` as the precision floor (magnitude-adaptive, not a fixed epsilon) at `Packages/LillistCore/Sources/LillistCore/Ordering/FractionalPosition.swift:28`. `PositionCompactor.recompact` is order-preserving but not order-imposing — callers must pre-sort the input slice before passing it (`Packages/LillistCore/Sources/LillistCore/Ordering/PositionCompactor.swift:5-6`). `SiblingOrder.precedes` is the single source of truth for presenter sort order across iOS and macOS (`Packages/LillistCore/Sources/LillistCore/Ordering/SiblingOrder.swift:3-6`).

## External deps

- Foundation — imported

## Gotchas

- `NSSortDescriptor` on the UUID `id` attribute is explicitly banned for sibling ordering: Core Data sorts UUIDs as raw bytes, which does NOT equal Swift's `uuidString` lexical order — always sort in-memory via `SiblingOrder.precedes` (`Packages/LillistCore/Sources/LillistCore/Ordering/SiblingOrder.swift:8-10`).
- `gapIsTooSmall` uses `after.ulp * 4` as the precision floor, not a fixed epsilon — the threshold adapts to the magnitude of position values, so positions in the millions have a proportionally larger compaction threshold (`Packages/LillistCore/Sources/LillistCore/Ordering/FractionalPosition.swift:28`).
