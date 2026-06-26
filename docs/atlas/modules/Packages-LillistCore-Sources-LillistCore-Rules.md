---
module: Packages/LillistCore/Sources/LillistCore/Rules
summary: "Smart-filter rule engine: Field/Op/Value/Leaf/PredicateGroup AST + NSPredicate compiler + parity Swift evaluator."
read_when: "Touching smart filters or predicate queries"
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
references_modules: [Packages-LillistCore-Sources-LillistCore-CLIBridge-misc, Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistUI-Sources-LillistUI-Recurrence]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistCore/Sources/LillistCore/Rules

## Purpose

This module is the predicate rule engine for smart filters: it defines the full AST vocabulary (Field, Op, Value, Leaf, PredicateGroup, Predicate, RelativeDate) plus two execution backends that must stay in parity — NSPredicateCompiler translates the tree to NSPredicate for Core Data fetch requests, and SwiftEvaluator runs the same logic in pure Swift over denormalized TaskSnapshot values for in-memory results, exports, and CLI queries. If the module vanished, every smart filter in the app would have no way to describe, serialize, or evaluate what tasks it matches.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AttachmentKindMatch` | struct | `Packages/LillistCore/Sources/LillistCore/Rules/AttachmentKindMatch.swift:7` | Callers may pass kind: nil to match any attachment type; kind set to a specific AttachmentKind restricts the match. present flips between must-have and must-not-have. |
| `Combinator` | enum | `Packages/LillistCore/Sources/LillistCore/Rules/PredicateGroup.swift:7` | Two-case enum (all = AND, any = OR); controls how compileGroup and evaluateGroup combine child predicates. |
| `Field` | enum | `Packages/LillistCore/Sources/LillistCore/Rules/Field.swift:7` | Stable String rawValues per design Section 5; reordering or removing cases breaks serialized smart filters and CLI argument parsing. |
| `Leaf` | struct | `Packages/LillistCore/Sources/LillistCore/Rules/Leaf.swift:4` | Codable-synthesized triple (field, op, value); callers rely on round-trip fidelity and Equatable for filter-state diffing. |
| `NSPredicateCompiler` | enum | `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift:19` | Caseless namespace that translates a PredicateGroup to NSPredicate; conjoins implicit deletedAt==nil and archivedAt==nil unless the group opts out or includeArchived is passed. |
| `Op` | enum | `Packages/LillistCore/Sources/LillistCore/Rules/Op.swift:7` | Stable String rawValues per design Section 5; `is` and `isNot` are Swift keywords and must be backtick-escaped at call sites. |
| `PredicateGroup` | struct | `Packages/LillistCore/Sources/LillistCore/Rules/PredicateGroup.swift:6` | Codable, Sendable, Equatable value combining a [Predicate] slice under .all or .any; recursive-ready for nested groups. |
| `PredicateLimits` | enum | `Packages/LillistCore/Sources/LillistCore/Rules/PredicateLimits.swift:7` | Single shared constant (maxAncestorDepth=8) governing ancestor-chain depth in both evaluators and CLI traversals; change it in one place and all paths agree. |
| `RelativeDate` | enum | `Packages/LillistCore/Sources/LillistCore/Rules/RelativeDate.swift:9` | Discriminated-union date relative to 'now'; resolved to an absolute Date at evaluation time so stored filters always use the current window. |
| `RelativeDateResolver` | enum | `Packages/LillistCore/Sources/LillistCore/Rules/RelativeDateResolver.swift:6` | Stateless caseless-enum namespace; converts RelativeDate → concrete Date using caller-supplied now and Calendar, safe from any isolation context. |
| `SwiftEvaluator` | enum | `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift:8` | Caseless-enum namespace; mirrors NSPredicateCompiler field-for-field and applies the same implicit trash exclusion via containsField check. |
| `SwiftEvaluator` | extension | `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift:288` | Extension housing TaskSnapshot.from(managedObject:); callers must invoke inside context.perform to safely touch managed object relationships. |
| `TaskSnapshot` | struct | `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift:12` | Denormalized value-type image of a LillistTask with pre-expanded relations (tagIDs, ancestorIDs, journalNoteBodies, attachmentKinds); passed to evaluate so the evaluator never touches NSManagedObject. |
| `Value` | enum | `Packages/LillistCore/Sources/LillistCore/Rules/Value.swift:5` | Discriminated union for the right-hand side of a Leaf; stable kind+value JSON encoding survives schema evolution; callers must not assume synthesized encoding. |
| `compile` | func | `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift:24` | Top-level compilation entry; relative-date semantics are live at compile time, so callers wanting rolling windows must recompile on a timer. |
| `compileAncestor` | func | `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift:299` | Unrolls a fixed OR chain of parent.…parent.id key paths up to PredicateLimits.maxAncestorDepth; isAncestorOf stubs false (no surfaced caller). |
| `compileBool` | func | `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift:135` | Compiles a boolean equality check on a key path; returns false predicate for any op other than .is or non-bool value. |
| `compileDate` | func | `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift:178` | Compiles date range predicates; Field.rawValue is used as the Core Data key path, so field raw values must match entity attribute names exactly. |
| `compileGroup` | func | `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift:42` | Empty group returns NSPredicate(value: true); otherwise ANDs or ORs compiled children per combinator. |
| `compileHasAttachments` | func | `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift:236` | Compiles a SUBQUERY over task.attachments; kind=nil in the match matches any attachment type. Only .is op is supported. |
| `compileHasChildren` | func | `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift:151` | Compiles a children.@count comparison; only .is op with a bool value is supported. |
| `compileHasNudges` | func | `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift:160` | Compiles a notificationSpecs.@count comparison; only .is op with a bool value is supported. |
| `compileInTrash` | func | `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift:142` | Compiles a deletedAt nil/non-nil check; only .is op with a bool value is supported. |
| `compileJournalText` | func | `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift:253` | Compiles a SUBQUERY over journalEntries for note-kind entries containing the search string; only .contains op is supported. |
| `compileLeaf` | func | `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift:70` | Dispatches a Leaf to the appropriate field-specific compile helper; unsupported field/op combinations yield NSPredicate(value: false). |
| `compilePredicate` | func | `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift:57` | Dispatches a Predicate case to compileLeaf or compileGroup; no logic of its own. |
| `compileRecurrence` | func | `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift:169` | Compiles a series nil/non-nil check for recurrence presence; only .is op with a bool value is supported. |
| `compileStatus` | func | `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift:123` | Compiles a statusRaw IN / NOT IN check against a set of Status values; only .is and .isNot ops are supported. |
| `compileString` | func | `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift:107` | Compiles CONTAINS[cd], ==[cd], or BEGINSWITH[cd] on a key path; unsupported ops return false predicate. |
| `compileTag` | func | `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift:269` | Handles isSet/isUnset by count before the uuidSet guard; includesAll expands to per-id SUBQUERY ANDs. isDescendantOf/isAncestorOf are handled via compileAncestor. |
| `containsField` | func | `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift:325` | Recursively scans a PredicateGroup for a specific Field; used by compile to decide whether to conjoin the implicit trash predicate. |
| `encode` | func | `Packages/LillistCore/Sources/LillistCore/Rules/Predicate.swift:32` | Hand-written type-discriminated encoder (type + payload keys) for the mutually-recursive Predicate; changing key strings breaks deserialized saved filters. |
| `encode` | func | `Packages/LillistCore/Sources/LillistCore/Rules/RelativeDate.swift:46` | Hand-written encoder with stable {kind, count} discriminator; changing key strings breaks deserialized saved filters. |
| `encode` | func | `Packages/LillistCore/Sources/LillistCore/Rules/Value.swift:49` | Hand-written encoder; sorts uuidSet and statusSet arrays for deterministic JSON output before encoding. |
| `endOfDay` | func | `Packages/LillistCore/Sources/LillistCore/Rules/RelativeDateResolver.swift:55` | Returns 23:59:59 on the same calendar day via Calendar.date(byAdding:); used internally by resolve and compileDate for end-of-day bounds. |
| `evaluate` | func | `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift:78` | Top-level in-memory entry; implicitly excludes trashed tasks unless the group contains an inTrash leaf, mirroring NSPredicateCompiler.compile behavior. |
| `evaluateGroup` | func | `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift:90` | Empty group returns true; otherwise applies allSatisfy or contains over evaluated child predicates per the combinator. |
| `evaluateLeaf` | func | `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift:123` | Dispatches a Leaf to the appropriate field-specific match helper; mirrors compileLeaf field-by-field for parity. |
| `evaluatePredicate` | func | `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift:109` | Dispatches a Predicate case to evaluateLeaf or evaluateGroup; no logic of its own. |
| `from` | func | `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift:292` | Builds a TaskSnapshot from a LillistTask MO; ancestor walk is depth-bounded by PredicateLimits.maxAncestorDepth to match NSPredicateCompiler's unrolled OR chain. |
| `matchAncestor` | func | `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift:170` | Tests ancestorIDs set intersection for isDescendantOf; isAncestorOf stubs false symmetrically with compileAncestor. |
| `matchBool` | func | `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift:282` | Returns actual == target; only .is op with a bool value is supported; other combinations return false. |
| `matchDate` | func | `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift:202` | Mirrors compileDate window logic in pure Swift; equalsModifiedAt requires otherDate to be non-nil or returns false. |
| `matchHasAttachments` | func | `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift:189` | Filters the kinds array by optional kind qualifier then checks present/absent; only .is op is supported. |
| `matchJournalText` | func | `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift:184` | Uses localizedStandardContains on each journal note body; only .contains op is supported. |
| `matchStatus` | func | `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift:273` | Tests Status membership in a statusSet; only .is and .isNot ops are supported. |
| `matchString` | func | `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift:255` | Uses localizedStandardContains / compare with [.caseInsensitive, .diacriticInsensitive] to mirror NSPredicate's [cd] flag; unsupported ops return false. |
| `matchTag` | func | `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift:152` | Handles isSet/isUnset by cardinality before the uuidSet guard; includesAny/includesAll/excludesAll use Set intersection ops. |
| `parse` | func | `Packages/LillistCore/Sources/LillistCore/Rules/RelativeDate.swift:73` | Parses DSL strings (+Nd, -Nw, today, startOfWeek…) into RelativeDate; throws LillistError.validationFailed on unrecognized or empty input. |
| `resolve` | func | `Packages/LillistCore/Sources/LillistCore/Rules/RelativeDateResolver.swift:7` | Resolves any RelativeDate case to an absolute Date; uses overflow-safe multiply for weeksFromNow to survive pathological decoded counts. |
| `resolveAbsolute` | func | `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift:226` | Extracts a concrete Date from Value.absoluteDate or Value.relativeDate; returns nil for all other Value cases. |
| `resolveAbsolute` | func | `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift:245` | Mirror of NSPredicateCompiler.resolveAbsolute; extracts concrete Date from Value.absoluteDate or Value.relativeDate, nil for all other cases. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `CodingKeys` | enum | `Packages/LillistCore/Sources/LillistCore/Rules/Predicate.swift:12` | Guards the wire format for saved Predicate JSON: the string keys 'type' and 'payload' are the on-disk discriminator contract. Any change silently breaks deserialization of every stored smart filter. (Packages/LillistCore/Sources/LillistCore/Rules/Predicate.swift:12) |
| `CodingKeys` | enum | `Packages/LillistCore/Sources/LillistCore/Rules/RelativeDate.swift:22` | Guards the wire format for saved RelativeDate JSON: the string keys 'kind' and 'count' are the on-disk discriminator contract. Any change silently breaks deserialization of every stored smart filter containing a relative-date value. (Packages/LillistCore/Sources/LillistCore/Rules/RelativeDate.swift:22) |
| `CodingKeys` | enum | `Packages/LillistCore/Sources/LillistCore/Rules/Value.swift:17` | Guards the wire format for saved Value JSON: the string keys 'kind' and 'value' are the on-disk discriminator contract. Any change silently breaks deserialization of every stored smart filter leaf. (Packages/LillistCore/Sources/LillistCore/Rules/Value.swift:17) |
| `Kind` | enum | `Packages/LillistCore/Sources/LillistCore/Rules/Predicate.swift:14` | Defines the discriminator strings 'leaf' and 'group' burned into saved smart filter JSON. Renaming or removing a case breaks deserialization of all existing Predicate values. (Packages/LillistCore/Sources/LillistCore/Rules/Predicate.swift:14-17) |
| `Kind` | enum | `Packages/LillistCore/Sources/LillistCore/Rules/RelativeDate.swift:24` | Defines the discriminator strings (today, tomorrow, daysFromNow…) burned into saved smart filter JSON. Renaming or removing a case breaks deserialization of existing RelativeDate values. (Packages/LillistCore/Sources/LillistCore/Rules/RelativeDate.swift:24-28) |
| `Kind` | enum | `Packages/LillistCore/Sources/LillistCore/Rules/Value.swift:19` | Defines the discriminator strings (string, uuidSet, statusSet, bool, absoluteDate, relativeDate, dayCount, attachmentKind) burned into saved smart filter JSON. Renaming or removing a case breaks deserialization of existing Value payloads. (Packages/LillistCore/Sources/LillistCore/Rules/Value.swift:19-22) |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-Rules.Kind -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Packages-LillistCore-Sources-LillistCore-Rules.Value -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Packages-LillistCore-Sources-LillistCore-Rules.compileDate -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.startOfDay (calls)`
- `Packages-LillistCore-Sources-LillistCore-Rules.compileJournalText -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Packages-LillistCore-Sources-LillistCore-Rules.compileString -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Packages-LillistCore-Sources-LillistCore-Rules.encode -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Packages-LillistCore-Sources-LillistCore-Rules.endOfDay -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.startOfDay (calls)`
- `Packages-LillistCore-Sources-LillistCore-Rules.matchDate -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.startOfDay (calls)`
- `Packages-LillistCore-Sources-LillistCore-Rules.matchJournalText -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Packages-LillistCore-Sources-LillistCore-Rules.matchString -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Packages-LillistCore-Sources-LillistCore-Rules.parse -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistCore-Sources-LillistCore-Rules.parse -> Packages-LillistCore-Sources-LillistCore-LinkPreview.firstMatch (calls)`
- `Packages-LillistCore-Sources-LillistCore-Rules.resolve -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.startOfDay (calls)`

## Type notes

All public types are value types (struct or enum), Codable, and Sendable, making them safe to pass across actor boundaries without copies being an issue. Predicate is `indirect enum` to support mutual recursion with PredicateGroup (Packages/LillistCore/Sources/LillistCore/Rules/Predicate.swift:8). Codable is hand-written on Predicate, RelativeDate, and Value to produce stable discriminated JSON (kind+payload / kind+count / kind+value keys) so saved smart filters survive schema evolution; callers must not assume synthesized encoding. NSPredicateCompiler and SwiftEvaluator are caseless public enums used as namespaces — they have no instances and no actor isolation. TaskSnapshot (SwiftEvaluator.TaskSnapshot) is the managed-object bridge: it denormalizes relationships (tags, ancestors, journal bodies, attachment kinds) from a LillistTask MO and must be built inside context.perform (Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift:290-291). PredicateLimits.maxAncestorDepth=8 is the single shared ceiling for ancestor-chain depth in both evaluators and the CLI; NSPredicateCompiler unrolls a fixed OR chain to this depth because NSPredicate cannot express transitive closure over SQL (Packages/LillistCore/Sources/LillistCore/Rules/PredicateLimits.swift:13-21). RelativeDate is resolved to an absolute Date at evaluation time, never at save time, so 'next 7 days' always means now+7 when the filter runs.

## External deps

- CoreData — imported
- Foundation — imported

## Gotchas

Predicate is `indirect enum` because automatic Codable synthesis fails on its mutually-recursive relationship with PredicateGroup.predicates: [Predicate] — both hand-write their Codable (Packages/LillistCore/Sources/LillistCore/Rules/Predicate.swift:3-7). `isAncestorOf` is deliberately stubbed `false` in both NSPredicateCompiler and SwiftEvaluator with a shared YAGNI comment — the two stubs must be wired up together (Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift:314-317, Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift:174-179). compileDate maps Field.rawValue directly to Core Data key paths (Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift:185), so Field raw string values must stay in sync with entity attribute names or predicates silently return false. compileTag and matchTag both handle isSet/isUnset before the uuidSet guard because the 'No Tags' default smart filter pairs .isUnset with .bool(true), not .uuidSet — guard-first would fall through to false (Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift:270-278, Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift:154-159). weeksFromNow uses overflow-safe multiply in RelativeDateResolver.resolve to handle pathological decoded counts (Packages/LillistCore/Sources/LillistCore/Rules/RelativeDateResolver.swift:27-29).
