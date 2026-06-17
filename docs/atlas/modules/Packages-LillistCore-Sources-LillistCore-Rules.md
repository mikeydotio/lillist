---
module: Packages/LillistCore/Sources/LillistCore/Rules
summary: "Smart-filter rule engine — predicate AST types, twin NSPredicate/Swift evaluators, date resolution"
read_when: "Touching smart filters, predicate evaluation, or filter serialization"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/Rules/AttachmentKindMatch.swift
    blob: 071e2efdc3c7c46c931283caa2463829e29128d5
  - path: Packages/LillistCore/Sources/LillistCore/Rules/Field.swift
    blob: 49d5f767e230d29c01450cd67027888abd48f3d7
  - path: Packages/LillistCore/Sources/LillistCore/Rules/Leaf.swift
    blob: a40f275c65b2e79af210f0cb93e6db05620d3275
  - path: Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift
    blob: 78267b3f92158b51995acd741547a0c97b4c2319
  - path: Packages/LillistCore/Sources/LillistCore/Rules/Op.swift
    blob: eb24e7cb50a1ccb191828c2a08e76a5df68516cc
  - path: Packages/LillistCore/Sources/LillistCore/Rules/Predicate.swift
    blob: d3edfffb5ac1b7c574dce97f7de4e90ac41a5ce3
  - path: Packages/LillistCore/Sources/LillistCore/Rules/PredicateGroup.swift
    blob: d4cf3e1c1bcb84742898f223a149256da197aa7e
  - path: Packages/LillistCore/Sources/LillistCore/Rules/PredicateLimits.swift
    blob: 3f8122a6a5f83afc8ff06406e0b99bfcda52e827
  - path: Packages/LillistCore/Sources/LillistCore/Rules/RelativeDate.swift
    blob: 1cbb98f43dd21fb84cc8da757427b96186248779
  - path: Packages/LillistCore/Sources/LillistCore/Rules/RelativeDateResolver.swift
    blob: 087cfd03ba37d608c7de44999e6d837fa0d98ff0
  - path: Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift
    blob: 0736ee0213facdca48d5bdccb767249190d44b04
  - path: Packages/LillistCore/Sources/LillistCore/Rules/Value.swift
    blob: ded7f8565dde48e25d60dd17266298baa5d173a7
references_modules: [Packages-LillistCore-Sources-LillistCore-Model, Packages-LillistCore-Sources-LillistCore-ManagedObjects, Packages-LillistCore-Sources-LillistCore-misc]
generator: cartographer/1
baseline: 1a1562b636e43ebbdc35c7939ab6989b387f50e9
verified: true
---

# Module: Packages/LillistCore/Sources/LillistCore/Rules

## Purpose

The rule engine for smart filters. A `PredicateGroup` is a Codable, recursive
field/operator/value tree (design Section 5) that gets executed two ways that
must stay behaviorally identical: `NSPredicateCompiler` lowers it to an
`NSPredicate` for live Core Data fetches, and `SwiftEvaluator` runs it in pure
Swift over a denormalized `TaskSnapshot`. Stable discriminator-keyed JSON lets
saved filters survive schema evolution; the twin evaluators are kept in lockstep
by a parity fixture suite, so a divergence here silently breaks filter results.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AttachmentKindMatch` | struct | `Packages/LillistCore/Sources/LillistCore/Rules/AttachmentKindMatch.swift:7` | Companion value for `hasAttachments`; `kind == nil` matches any kind |
| `Field` | enum | `Packages/LillistCore/Sources/LillistCore/Rules/Field.swift:7` | Queryable task fields; raw strings are stable JSON/CLI keys — reordering breaks serialization |
| `Leaf` | struct | `Packages/LillistCore/Sources/LillistCore/Rules/Leaf.swift:4` | One field/op/value triple; the predicate tree's terminal node |
| `NSPredicateCompiler` | enum | `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift:19` | Stateless namespace lowering a group to an `NSPredicate` over `LillistTask` |
| `NSPredicateCompiler.compile` | func | `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift:24` | Top-level lowering; auto-conjoins `deletedAt`/`archivedAt` nil guards unless opted out |
| `Op` | enum | `Packages/LillistCore/Sources/LillistCore/Rules/Op.swift:7` | Operators a `Leaf` may use; stable raw strings; `is`/`isNot` are backtick-escaped |
| `Predicate` | enum | `Packages/LillistCore/Sources/LillistCore/Rules/Predicate.swift:8` | Recursive `.leaf`/`.group` node; hand-written Codable with `type`/`payload` keys |
| `PredicateGroup` | struct | `Packages/LillistCore/Sources/LillistCore/Rules/PredicateGroup.swift:6` | Combinator (`all`/`any`) over child predicates; the engine's root input type |
| `PredicateGroup.Combinator` | enum | `Packages/LillistCore/Sources/LillistCore/Rules/PredicateGroup.swift:7` | `all` (AND) / `any` (OR) over the group's children |
| `PredicateLimits` | enum | `Packages/LillistCore/Sources/LillistCore/Rules/PredicateLimits.swift:7` | Shared numeric bounds; `maxAncestorDepth = 8` caps every ancestor traversal |
| `RelativeDate` | enum | `Packages/LillistCore/Sources/LillistCore/Rules/RelativeDate.swift:9` | Relative date kinds; resolved at eval time so "next 7 days" tracks now |
| `RelativeDate.parse` | func | `Packages/LillistCore/Sources/LillistCore/Rules/RelativeDate.swift:73` | Parses DSL (`today`, `+Nd`, `Nw`); throws `LillistError.validationFailed` on bad input |
| `RelativeDateResolver` | enum | `Packages/LillistCore/Sources/LillistCore/Rules/RelativeDateResolver.swift:6` | Pure, isolation-safe resolver of `RelativeDate` to an absolute `Date` |
| `RelativeDateResolver.resolve` | func | `Packages/LillistCore/Sources/LillistCore/Rules/RelativeDateResolver.swift:7` | Resolves a `RelativeDate` via supplied `now`/`Calendar`; never traps |
| `SwiftEvaluator` | enum | `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift:8` | Stateless pure-Swift evaluator; behavior mirrors `NSPredicateCompiler` |
| `SwiftEvaluator.TaskSnapshot` | struct | `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift:12` | Denormalized per-task input; carries every field the engine can query |
| `SwiftEvaluator.TaskSnapshot.from` | func | `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift:292` | Builds a snapshot from a `LillistTask`; must run inside the MO's context |
| `SwiftEvaluator.evaluate` | func | `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift:78` | Runs a group against a snapshot; applies the same implicit-trash exclusion |
| `Value` | enum | `Packages/LillistCore/Sources/LillistCore/Rules/Value.swift:5` | Discriminated RHS of a `Leaf`; stable `kind` JSON; sorted sets for determinism |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `NSPredicateCompiler.containsField` | func | `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift:325` | Detects an explicit `.inTrash` leaf; gates the implicit-trash rule for BOTH evaluators |
| `NSPredicateCompiler.compileAncestor` | func | `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift:299` | Unrolls `parent.…id` key-paths to `maxAncestorDepth` since `NSPredicate` lacks transitive closure |
| `RelativeDateResolver.endOfDay` | func | `Packages/LillistCore/Sources/LillistCore/Rules/RelativeDateResolver.swift:55` | Shared 23:59:59 boundary used by `on`/`withinNextDays`/end-of-week/month in both evaluators |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-Rules.NSPredicateCompiler -> Packages-LillistCore-Sources-LillistCore-Rules.RelativeDateResolver (calls)`
- `Packages-LillistCore-Sources-LillistCore-Rules.SwiftEvaluator -> Packages-LillistCore-Sources-LillistCore-Rules.RelativeDateResolver (calls)`
- `Packages-LillistCore-Sources-LillistCore-Rules.SwiftEvaluator -> Packages-LillistCore-Sources-LillistCore-Rules.NSPredicateCompiler (calls)`
- `Packages-LillistCore-Sources-LillistCore-Rules.Value -> Packages-LillistCore-Sources-LillistCore-Model.Status (owns)`
- `Packages-LillistCore-Sources-LillistCore-Rules.AttachmentKindMatch -> Packages-LillistCore-Sources-LillistCore-Model.AttachmentKind (owns)`
- `Packages-LillistCore-Sources-LillistCore-Rules.NSPredicateCompiler -> Packages-LillistCore-Sources-LillistCore-Model.JournalEntryKind (reads)`
- `Packages-LillistCore-Sources-LillistCore-Rules.SwiftEvaluator -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.LillistTask (reads)`
- `Packages-LillistCore-Sources-LillistCore-Rules.SwiftEvaluator -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.Tag (reads)`
- `Packages-LillistCore-Sources-LillistCore-Rules.SwiftEvaluator -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.JournalEntry (reads)`
- `Packages-LillistCore-Sources-LillistCore-Rules.SwiftEvaluator -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.Attachment (reads)`
- `Packages-LillistCore-Sources-LillistCore-Rules.RelativeDate -> Packages-LillistCore-Sources-LillistCore-misc.LillistError (emits)`

## Type notes

All engine types are `Codable + Sendable + Equatable` value types. `Predicate`,
`Value`, and `RelativeDate` hand-roll Codable with discriminator keys: `Predicate`
because automatic synthesis fails on the mutual recursion with `PredicateGroup`
(`Packages/LillistCore/Sources/LillistCore/Rules/Predicate.swift:8`); `Value`/`RelativeDate`
to keep JSON stable and human-readable. `Value` encodes sets sorted for
deterministic output (`Packages/LillistCore/Sources/LillistCore/Rules/Value.swift:58`).
`NSPredicateCompiler`, `SwiftEvaluator`, and `RelativeDateResolver` are stateless
`enum` namespaces (static methods only), so they are safe from any isolation
context. Parity invariant: the two evaluators must agree — `isAncestorOf` is
deliberately stubbed `false` in both rather than diverge
(`Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift:174`,
`Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift:312`).
`TaskSnapshot.from` must be invoked inside `context.perform` to touch relationships safely
(`Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift:288`).

## External deps

- Foundation — `Date`, `Calendar`, `NSRegularExpression`, JSON Codable plumbing
- CoreData — `NSPredicate`/`NSCompoundPredicate` construction and `LillistTask` key-paths

## Gotchas

- Implicit-trash/archive: `compile` conjoins `deletedAt == nil` (and `archivedAt == nil` unless `includeArchived`) unless a `.inTrash` leaf is present (`Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift:32`).
- `tag.isSet`/`isUnset` are handled before the `uuidSet` guard so the "No Tags" default filter compiles (`Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift:274`).
- `weeksFromNow` saturates the ×7 multiply so a corrupt decoded count never traps (`Packages/LillistCore/Sources/LillistCore/Rules/RelativeDateResolver.swift:27`).
- Ancestor depth beyond `maxAncestorDepth` (8) is not matched by ancestor predicates (`Packages/LillistCore/Sources/LillistCore/Rules/PredicateLimits.swift:21`).
