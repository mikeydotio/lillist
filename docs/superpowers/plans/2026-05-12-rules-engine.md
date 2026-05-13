# Lillist Plan 3 — Rules Engine and Smart Filters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the predicate engine and `SmartFilter` persistence layer described in design Section 5 on top of Plan 1's `LillistCore` package. Deliver: a `Predicate` recursive enum with `PredicateGroup` and `Leaf`; complete `Field`/`Op`/`Value` taxonomies; absolute and relative date values plus a DSL parser; an `NSPredicateCompiler` for Core Data fetch requests; a pure-`SwiftEvaluator` for in-memory checks and the CLI; a shared fixture parity suite that runs every fixture through both paths and fails on divergence; a `SmartFilter` Core Data entity (CloudKit-compatible schema) and a matching `SmartFilterStore` with create / fetch / list / update / delete / setPinned / reorder.

**Architecture:** Plan 3 introduces a new `Sources/LillistCore/Rules/` subtree alongside the existing `Model/`, `Persistence/`, `Stores/`, and `Validation/` directories from Plan 1. The predicate types are pure value types: `Predicate`, `PredicateGroup`, `Leaf`, `Field`, `Op`, `Value`, `RelativeDate`, `AttachmentKindMatch` — all `Codable + Sendable`. `RelativeDateResolver` is an actor-free utility resolving a `RelativeDate` to a concrete `Date` given `now` and a `Calendar`. `NSPredicateCompiler` walks a `PredicateGroup` and produces an `NSPredicate` over the `LillistTask` entity. `SwiftEvaluator` evaluates the same group against a `TaskStore.TaskRecord` (with optional lazily-fetched augmentation for relational fields). Both paths share semantics; the fixture parity suite is the regression backbone (design Section 9, Block 2). The `SmartFilter` entity extends `LillistModel.xcdatamodeld` with all-optional attributes (CloudKit rule), and `SmartFilterStore` serializes `PredicateGroup` to a JSON string stored at `predicateGroupJSON`.

**Tech Stack:** Swift 6, Swift Package Manager, Core Data (`NSPersistentContainer` from Plan 1; `NSPersistentCloudKitContainer` after Plan 2 — same store interface), Swift Testing (`@Test`, `#expect`), Foundation. No third-party dependencies.

**Depends on:** Plan 1 (Foundation). Every file under `Packages/LillistCore/` listed in Plan 1's File Structure is assumed to exist with the API described there. In particular: `LillistTask` / `Tag` / `JournalEntry` / `Attachment` managed objects with the attribute and relationship names shown in `LillistModel.xcdatamodeld`, `PersistenceController`, `TaskStore.TaskRecord`, `Status`, `AttachmentKind`, `JournalEntryKind`, `SortField`, and `LillistError`.

---

## File Structure

```
Packages/LillistCore/
├── Sources/
│   └── LillistCore/
│       ├── Model/
│       │   └── LillistModel.xcdatamodeld/
│       │       └── LillistModel.xcdatamodel/
│       │           └── contents                  (extended: add SmartFilter entity)
│       ├── ManagedObjects/
│       │   └── SmartFilter+CoreData.swift        (new: typed accessors)
│       ├── Rules/
│       │   ├── Field.swift                       (Field enum)
│       │   ├── Op.swift                          (Op enum)
│       │   ├── AttachmentKindMatch.swift         (typed sub-value for hasAttachments ofKind)
│       │   ├── RelativeDate.swift                (RelativeDate value + DSL parser)
│       │   ├── RelativeDateResolver.swift        (resolves to absolute Date)
│       │   ├── Value.swift                       (Value typed-union + Codable)
│       │   ├── Leaf.swift                        (Leaf struct)
│       │   ├── PredicateGroup.swift              (PredicateGroup + Combinator)
│       │   ├── Predicate.swift                   (recursive enum + Codable)
│       │   ├── NSPredicateCompiler.swift         (PredicateGroup -> NSPredicate)
│       │   └── SwiftEvaluator.swift              (PredicateGroup -> Bool against TaskRecord)
│       └── Stores/
│           └── SmartFilterStore.swift            (CRUD + setPinned + reorder + evaluate/count)
└── Tests/
    └── LillistCoreTests/
        ├── Rules/
        │   ├── FieldTests.swift
        │   ├── OpTests.swift
        │   ├── RelativeDateDSLTests.swift
        │   ├── RelativeDateResolverTests.swift
        │   ├── ValueCodableTests.swift
        │   ├── PredicateCodableTests.swift
        │   ├── NSPredicateCompilerTests.swift
        │   ├── SwiftEvaluatorTests.swift
        │   ├── ParityFixtures.swift              (the shared fixture set)
        │   ├── ParitySuiteTests.swift            (runs both paths over fixtures)
        │   └── RelativeDateParityTests.swift     (property-based parity for date ops)
        └── Stores/
            └── SmartFilterStoreTests.swift
```

All new sources live under `Packages/LillistCore/Sources/LillistCore/Rules/` (plus one new managed-object extension and one new store). The Core Data model file gains one entity, and no existing entity is modified.

---

## Notes for the Implementer

**TDD discipline.** Every functional task follows red → green → refactor → commit, matching Plan 1's pattern. Write the test first, run it, watch it fail, write minimal code, watch it pass, commit. Conventional-commit prefixes throughout.

**Why two evaluators?** Per design Section 5, `NSPredicateCompiler` powers live smart-filter views via `NSFetchedResultsController` against Core Data. `SwiftEvaluator` runs in pure Swift for badge counts on pinned filters (where iterating fetched records is faster than re-querying), and for the CLI in Plan 6 where filtering can happen over a result set already in memory. Behavior must be identical, which is what the fixture parity suite enforces.

**Recursive Codable for `Predicate`.** Swift's automatic synthesis cannot derive `Codable` for an `indirect enum` whose associated values include other `Codable` types whose own synthesis depends on the enum (mutual recursion via `PredicateGroup.predicates: [Predicate]`). We write the encoder/decoder explicitly using a discriminator key. The same pattern applies to `Value` — its associated values are heterogeneous and need a discriminator. Both are spelled out in full below.

**Implicit `inTrash` rule.** Per design Section 5, smart filters are evaluated against non-trashed tasks unless the predicate group explicitly sets `inTrash`. Both compiler paths append `inTrash == false` automatically when no leaf has `field == .inTrash`.

**Relative dates are stored as structured values.** Storing a resolved absolute `Date` would freeze "next 7 days" at filter-save time. Instead, `RelativeDate` is itself `Codable`, and `RelativeDateResolver.resolve(_:now:calendar:)` is called *at evaluation time* by both compiler and evaluator. The DSL parser is consumed by the CLI in Plan 6 (mention only; CLI is out of scope here).

**CloudKit-compatible schema.** Like every other entity in Plan 1, all `SmartFilter` attributes are optional at the schema level — required-ness is enforced in `SmartFilterStore`. No `Deny` deletion rules.

**Concurrency.** Predicate / value types are `Sendable`. `NSPredicateCompiler` and `SwiftEvaluator` are stateless utilities (static methods or `enum` namespaces). `SmartFilterStore` mirrors Plan 1's `*Store` pattern: `@unchecked Sendable`, all operations run inside `context.perform`, value-type `SmartFilterRecord` DTOs returned across boundaries.

**Verification command throughout:** `cd Packages/LillistCore && swift test`. Plan 3 is considered complete when the full Plan-1 + Plan-3 suite passes green, the parity suite covers every fixture twice (NSPredicate path and Swift path), the relative-date property test passes, and the Self-Review Checklist is complete.

**Plan 6 forward reference (informational only):** The CLI in Plan 6 will (a) consume `RelativeDate.parse(_:)` to turn `+7d` / `endOfWeek` into `RelativeDate` values for `lillist filter --deadline-before +3d`-style flags, and (b) call `SwiftEvaluator.evaluate(group:against:)` on already-fetched records for the `lillist eval` and `lillist filter --json` pipelines. Plan 3 implements both; Plan 6 wires them up.

---

## Task 1: Extend `LillistModel.xcdatamodeld` with the `SmartFilter` entity

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/LillistModel.xcdatamodel/contents`

- [ ] **Step 1: Add the `SmartFilter` entity to the model contents XML**

Open `Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/LillistModel.xcdatamodel/contents` and insert a new `<entity>` block immediately before the closing `</model>` tag. The full entity block to insert:

```xml
    <entity name="SmartFilter" representedClassName="SmartFilter" syncable="YES">
        <attribute name="id" optional="YES" attributeType="UUID" usesScalarValueType="NO"/>
        <attribute name="name" optional="YES" attributeType="String"/>
        <attribute name="predicateGroupJSON" optional="YES" attributeType="String"/>
        <attribute name="tintColor" optional="YES" attributeType="String"/>
        <attribute name="sortFieldRaw" optional="YES" attributeType="String" defaultValueString="deadline"/>
        <attribute name="sortAscending" optional="YES" attributeType="Boolean" defaultValueString="YES" usesScalarValueType="YES"/>
        <attribute name="isPinned" optional="YES" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>
        <attribute name="position" optional="YES" attributeType="Double" defaultValueString="0" usesScalarValueType="YES"/>
        <attribute name="createdAt" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="modifiedAt" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
    </entity>
```

All attributes are optional (CloudKit-compatibility rule; required-ness enforced in `SmartFilterStore`). No relationships to other entities — a smart filter is a pure query value, not connected to specific tasks or tags. `predicateGroupJSON` carries the serialized `PredicateGroup`.

- [ ] **Step 2: Add a regression test for the new entity**

Append the following test to `Packages/LillistCore/Tests/LillistCoreTests/Persistence/PersistenceControllerTests.swift` (extend the existing `entitiesPresent` test or add a new one — your call; this plan assumes a new sibling test):

```swift
    @Test("Model contains SmartFilter entity with expected attributes")
    func smartFilterEntityShape() async throws {
        let controller = try await PersistenceController(configuration: .inMemory)
        let model = controller.container.managedObjectModel
        guard let entity = model.entitiesByName["SmartFilter"] else {
            Issue.record("SmartFilter entity missing")
            return
        }
        let attrs = Set(entity.attributesByName.keys)
        for required in ["id", "name", "predicateGroupJSON", "tintColor",
                         "sortFieldRaw", "sortAscending", "isPinned", "position",
                         "createdAt", "modifiedAt"] {
            #expect(attrs.contains(required), "missing attribute \(required)")
        }
        // CloudKit rule: every attribute must be optional at the schema level.
        for (_, attr) in entity.attributesByName {
            #expect(attr.isOptional == true, "\(attr.name) must be optional")
        }
    }
```

- [ ] **Step 3: Run the test to verify it passes**

Run: `cd Packages/LillistCore && swift test --filter PersistenceControllerTests`
Expected: PASS, including the new `smartFilterEntityShape` test. If it fails because Core Data auto-generated classes don't yet include `SmartFilter`, that's fine — class generation happens at build time and will be picked up by Task 2.

- [ ] **Step 4: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/LillistModel.xcdatamodel/contents \
        Packages/LillistCore/Tests/LillistCoreTests/Persistence/PersistenceControllerTests.swift
git commit -m "feat: add SmartFilter entity to Core Data model"
```

---

## Task 2: Typed accessors on the `SmartFilter` managed object

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/ManagedObjects/SmartFilter+CoreData.swift`

The auto-generated `SmartFilter` class has `sortFieldRaw: String?` and a generic `Bool` interface. We add a typed `sortField: SortField` accessor matching the pattern from Plan 1 Task 8.

- [ ] **Step 1: Write the extension**

Write `Packages/LillistCore/Sources/LillistCore/ManagedObjects/SmartFilter+CoreData.swift`:

```swift
import Foundation
import CoreData

extension SmartFilter {
    /// Typed accessor over `sortFieldRaw`.
    public var sortField: SortField {
        get { SortField(rawValue: sortFieldRaw ?? "deadline") ?? .deadline }
        set { sortFieldRaw = newValue.rawValue }
    }
}
```

- [ ] **Step 2: Build**

Run: `cd Packages/LillistCore && swift build`
Expected: build succeeds. Core Data auto-generation provides `SmartFilter` as an `NSManagedObject` subclass; the extension above compiles against it.

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/ManagedObjects/SmartFilter+CoreData.swift
git commit -m "feat: add typed sortField accessor on SmartFilter managed object"
```

---

## Task 3: `Field` enum

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Rules/Field.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Rules/FieldTests.swift`

Per design Section 5, every queryable field gets a case here. Raw values are stable strings used both in `Codable` encoding and in CLI argument parsing (Plan 6).

- [ ] **Step 1: Write the failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Rules/FieldTests.swift`:

```swift
import Testing
@testable import LillistCore

@Suite("Field")
struct FieldTests {
    @Test("Raw values are stable")
    func rawValuesStable() {
        #expect(Field.title.rawValue == "title")
        #expect(Field.notes.rawValue == "notes")
        #expect(Field.journalText.rawValue == "journalText")
        #expect(Field.tag.rawValue == "tag")
        #expect(Field.status.rawValue == "status")
        #expect(Field.start.rawValue == "start")
        #expect(Field.deadline.rawValue == "deadline")
        #expect(Field.createdAt.rawValue == "createdAt")
        #expect(Field.modifiedAt.rawValue == "modifiedAt")
        #expect(Field.closedAt.rawValue == "closedAt")
        #expect(Field.hasAttachments.rawValue == "hasAttachments")
        #expect(Field.hasChildren.rawValue == "hasChildren")
        #expect(Field.hasNudges.rawValue == "hasNudges")
        #expect(Field.isPinned.rawValue == "isPinned")
        #expect(Field.ancestor.rawValue == "ancestor")
        #expect(Field.recurrence.rawValue == "recurrence")
        #expect(Field.inTrash.rawValue == "inTrash")
    }

    @Test("All design Section 5 fields enumerated")
    func allCases() {
        #expect(Field.allCases.count == 17)
    }

    @Test("Codable round-trips")
    func codable() throws {
        for f in Field.allCases {
            let data = try JSONEncoder().encode(f)
            let decoded = try JSONDecoder().decode(Field.self, from: data)
            #expect(decoded == f)
        }
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/LillistCore && swift test --filter FieldTests`
Expected: FAIL — `Field` undefined.

- [ ] **Step 3: Write the implementation**

Write `Packages/LillistCore/Sources/LillistCore/Rules/Field.swift`:

```swift
import Foundation

/// Every queryable field on a task, per design Section 5.
///
/// Raw values are stable strings used in JSON serialization and CLI argument
/// parsing. Reordering or removing cases is a breaking change.
public enum Field: String, CaseIterable, Codable, Sendable {
    case title
    case notes
    case journalText
    case tag
    case status
    case start
    case deadline
    case createdAt
    case modifiedAt
    case closedAt
    case hasAttachments
    case hasChildren
    case hasNudges
    case isPinned
    case ancestor
    case recurrence
    case inTrash
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `cd Packages/LillistCore && swift test --filter FieldTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Rules/Field.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Rules/FieldTests.swift
git commit -m "feat: add Field enum covering every queryable field from design Section 5"
```

---

## Task 4: `Op` enum

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Rules/Op.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Rules/OpTests.swift`

Every operator that appears in design Section 5's table.

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Rules/OpTests.swift`:

```swift
import Testing
@testable import LillistCore

@Suite("Op")
struct OpTests {
    @Test("Raw values are stable")
    func rawValuesStable() {
        #expect(Op.contains.rawValue == "contains")
        #expect(Op.equals.rawValue == "equals")
        #expect(Op.startsWith.rawValue == "startsWith")
        #expect(Op.includesAny.rawValue == "includesAny")
        #expect(Op.includesAll.rawValue == "includesAll")
        #expect(Op.excludesAll.rawValue == "excludesAll")
        #expect(Op.is.rawValue == "is")
        #expect(Op.isNot.rawValue == "isNot")
        #expect(Op.before.rawValue == "before")
        #expect(Op.after.rawValue == "after")
        #expect(Op.on.rawValue == "on")
        #expect(Op.withinLastDays.rawValue == "withinLastDays")
        #expect(Op.withinNextDays.rawValue == "withinNextDays")
        #expect(Op.isSet.rawValue == "isSet")
        #expect(Op.isUnset.rawValue == "isUnset")
        #expect(Op.equalsModifiedAt.rawValue == "equalsModifiedAt")
        #expect(Op.isDescendantOf.rawValue == "isDescendantOf")
        #expect(Op.isAncestorOf.rawValue == "isAncestorOf")
    }

    @Test("All design Section 5 operators enumerated")
    func allCases() {
        #expect(Op.allCases.count == 18)
    }

    @Test("Codable round-trips")
    func codable() throws {
        for op in Op.allCases {
            let data = try JSONEncoder().encode(op)
            let decoded = try JSONDecoder().decode(Op.self, from: data)
            #expect(decoded == op)
        }
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/LillistCore && swift test --filter OpTests`
Expected: FAIL — `Op` undefined.

- [ ] **Step 3: Write the implementation**

Write `Packages/LillistCore/Sources/LillistCore/Rules/Op.swift`:

```swift
import Foundation

/// Every operator that may appear in a `Leaf`, per design Section 5.
///
/// `is`/`isNot` is a Swift keyword in some contexts; backtick-escape at use
/// sites: `Op.is`, `Op.isNot`.
public enum Op: String, CaseIterable, Codable, Sendable {
    case contains
    case equals
    case startsWith
    case includesAny
    case includesAll
    case excludesAll
    case `is`
    case isNot
    case before
    case after
    case on
    case withinLastDays
    case withinNextDays
    case isSet
    case isUnset
    case equalsModifiedAt
    case isDescendantOf
    case isAncestorOf
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `cd Packages/LillistCore && swift test --filter OpTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Rules/Op.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Rules/OpTests.swift
git commit -m "feat: add Op enum covering every operator from design Section 5"
```

---

## Task 5: `AttachmentKindMatch` typed sub-value

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Rules/AttachmentKindMatch.swift`

The `hasAttachments` field accepts an optional `ofKind` qualifier (design Section 5 — "optional `ofKind`"). To keep `Value` discriminated cleanly, we expose this as its own typed sub-value used only when the `Value` case is `.attachmentKind`.

- [ ] **Step 1: Write the type**

Write `Packages/LillistCore/Sources/LillistCore/Rules/AttachmentKindMatch.swift`:

```swift
import Foundation

/// Companion value for `Field.hasAttachments` with the optional `ofKind` qualifier.
///
/// When `kind` is nil, the leaf matches any attachment kind. When set, only
/// attachments of that kind count.
public struct AttachmentKindMatch: Codable, Sendable, Equatable {
    public var present: Bool
    public var kind: AttachmentKind?

    public init(present: Bool, kind: AttachmentKind? = nil) {
        self.present = present
        self.kind = kind
    }
}
```

- [ ] **Step 2: Build**

Run: `cd Packages/LillistCore && swift build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Rules/AttachmentKindMatch.swift
git commit -m "feat: add AttachmentKindMatch sub-value for hasAttachments leaves"
```

---

## Task 6: `RelativeDate` value type and DSL parser

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Rules/RelativeDate.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Rules/RelativeDateDSLTests.swift`

`RelativeDate` is `Codable + Sendable`. The DSL parser produces a `RelativeDate` from CLI-style strings (`today`, `tomorrow`, `+7d`, `-2w`, `startOfWeek`, etc.). Plan 6 (CLI) consumes the parser; Plan 3 ships and tests it.

- [ ] **Step 1: Write failing DSL tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Rules/RelativeDateDSLTests.swift`:

```swift
import Testing
@testable import LillistCore

@Suite("RelativeDate DSL")
struct RelativeDateDSLTests {
    @Test("Keyword phrases parse")
    func keywords() throws {
        #expect(try RelativeDate.parse("today") == .today)
        #expect(try RelativeDate.parse("tomorrow") == .tomorrow)
        #expect(try RelativeDate.parse("yesterday") == .yesterday)
        #expect(try RelativeDate.parse("startOfWeek") == .startOfWeek)
        #expect(try RelativeDate.parse("endOfWeek") == .endOfWeek)
        #expect(try RelativeDate.parse("startOfMonth") == .startOfMonth)
        #expect(try RelativeDate.parse("endOfMonth") == .endOfMonth)
    }

    @Test("Keyword parsing is case-insensitive")
    func caseInsensitive() throws {
        #expect(try RelativeDate.parse("Today") == .today)
        #expect(try RelativeDate.parse("STARTOFWEEK") == .startOfWeek)
    }

    @Test("Offset forms parse")
    func offsets() throws {
        #expect(try RelativeDate.parse("+7d") == .daysFromNow(7))
        #expect(try RelativeDate.parse("-2d") == .daysFromNow(-2))
        #expect(try RelativeDate.parse("+0d") == .daysFromNow(0))
        #expect(try RelativeDate.parse("+3w") == .weeksFromNow(3))
        #expect(try RelativeDate.parse("-1w") == .weeksFromNow(-1))
    }

    @Test("Unsigned integer day count parses as +N days")
    func bareInteger() throws {
        #expect(try RelativeDate.parse("7d") == .daysFromNow(7))
        #expect(try RelativeDate.parse("2w") == .weeksFromNow(2))
    }

    @Test("Invalid strings throw validationFailed")
    func invalid() {
        #expect(throws: LillistError.self) { _ = try RelativeDate.parse("") }
        #expect(throws: LillistError.self) { _ = try RelativeDate.parse("nextMonday") }
        #expect(throws: LillistError.self) { _ = try RelativeDate.parse("+xd") }
        #expect(throws: LillistError.self) { _ = try RelativeDate.parse("7q") }
        #expect(throws: LillistError.self) { _ = try RelativeDate.parse("startOf") }
    }

    @Test("Codable round-trips every variant")
    func codable() throws {
        let cases: [RelativeDate] = [
            .today, .tomorrow, .yesterday,
            .daysFromNow(7), .daysFromNow(-3),
            .weeksFromNow(2), .weeksFromNow(-1),
            .startOfWeek, .endOfWeek, .startOfMonth, .endOfMonth
        ]
        for c in cases {
            let data = try JSONEncoder().encode(c)
            let decoded = try JSONDecoder().decode(RelativeDate.self, from: data)
            #expect(decoded == c)
        }
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/LillistCore && swift test --filter RelativeDateDSLTests`
Expected: FAIL — `RelativeDate` undefined.

- [ ] **Step 3: Write the implementation**

Write `Packages/LillistCore/Sources/LillistCore/Rules/RelativeDate.swift`:

```swift
import Foundation

/// A date expressed relative to "now". Resolved to an absolute `Date` at
/// evaluation time so "next 7 days" always means *now's* +7 — never frozen
/// at smart-filter save time.
///
/// Codable + Sendable. The associated-value cases are encoded with a
/// discriminator key so JSON output is human-readable and stable.
public enum RelativeDate: Codable, Sendable, Equatable {
    case today
    case tomorrow
    case yesterday
    case daysFromNow(Int)
    case weeksFromNow(Int)
    case startOfWeek
    case endOfWeek
    case startOfMonth
    case endOfMonth

    // MARK: - Codable (manual, for stable discriminator JSON)

    private enum CodingKeys: String, CodingKey { case kind, count }

    private enum Kind: String, Codable {
        case today, tomorrow, yesterday
        case daysFromNow, weeksFromNow
        case startOfWeek, endOfWeek, startOfMonth, endOfMonth
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .today: self = .today
        case .tomorrow: self = .tomorrow
        case .yesterday: self = .yesterday
        case .daysFromNow: self = .daysFromNow(try c.decode(Int.self, forKey: .count))
        case .weeksFromNow: self = .weeksFromNow(try c.decode(Int.self, forKey: .count))
        case .startOfWeek: self = .startOfWeek
        case .endOfWeek: self = .endOfWeek
        case .startOfMonth: self = .startOfMonth
        case .endOfMonth: self = .endOfMonth
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .today: try c.encode(Kind.today, forKey: .kind)
        case .tomorrow: try c.encode(Kind.tomorrow, forKey: .kind)
        case .yesterday: try c.encode(Kind.yesterday, forKey: .kind)
        case .daysFromNow(let n):
            try c.encode(Kind.daysFromNow, forKey: .kind)
            try c.encode(n, forKey: .count)
        case .weeksFromNow(let n):
            try c.encode(Kind.weeksFromNow, forKey: .kind)
            try c.encode(n, forKey: .count)
        case .startOfWeek: try c.encode(Kind.startOfWeek, forKey: .kind)
        case .endOfWeek: try c.encode(Kind.endOfWeek, forKey: .kind)
        case .startOfMonth: try c.encode(Kind.startOfMonth, forKey: .kind)
        case .endOfMonth: try c.encode(Kind.endOfMonth, forKey: .kind)
        }
    }

    // MARK: - DSL parser

    /// Parse a DSL string into a `RelativeDate`.
    ///
    /// Accepted forms: keywords (`today`, `tomorrow`, `yesterday`,
    /// `startOfWeek`, `endOfWeek`, `startOfMonth`, `endOfMonth`); signed offset
    /// forms `+Nd` / `-Nd` / `+Nw` / `-Nw`; and bare unsigned forms `Nd` / `Nw`
    /// which behave as `+Nd` / `+Nw`. Case-insensitive.
    public static func parse(_ raw: String) throws -> RelativeDate {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty {
            throw LillistError.validationFailed([
                .init(field: "relativeDate", message: "must not be empty")
            ])
        }
        let lower = s.lowercased()
        switch lower {
        case "today": return .today
        case "tomorrow": return .tomorrow
        case "yesterday": return .yesterday
        case "startofweek": return .startOfWeek
        case "endofweek": return .endOfWeek
        case "startofmonth": return .startOfMonth
        case "endofmonth": return .endOfMonth
        default: break
        }
        // Offset forms: optional sign, digits, unit suffix
        let pattern = #"^([+-]?)(\d+)([dw])$"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: []),
            let match = regex.firstMatch(
                in: lower,
                options: [],
                range: NSRange(lower.startIndex..., in: lower)
            ),
            match.numberOfRanges == 4
        else {
            throw LillistError.validationFailed([
                .init(field: "relativeDate", message: "unrecognized syntax: \(raw)")
            ])
        }
        let signRange = Range(match.range(at: 1), in: lower)!
        let numRange = Range(match.range(at: 2), in: lower)!
        let unitRange = Range(match.range(at: 3), in: lower)!
        let signStr = String(lower[signRange])
        let numStr = String(lower[numRange])
        let unit = String(lower[unitRange])
        guard let magnitude = Int(numStr) else {
            throw LillistError.validationFailed([
                .init(field: "relativeDate", message: "invalid integer: \(raw)")
            ])
        }
        let signed = (signStr == "-") ? -magnitude : magnitude
        switch unit {
        case "d": return .daysFromNow(signed)
        case "w": return .weeksFromNow(signed)
        default:
            throw LillistError.validationFailed([
                .init(field: "relativeDate", message: "unknown unit: \(unit)")
            ])
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/LillistCore && swift test --filter RelativeDateDSLTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Rules/RelativeDate.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Rules/RelativeDateDSLTests.swift
git commit -m "feat: add RelativeDate value type with Codable and DSL parser"
```

---

## Task 7: `RelativeDateResolver`

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Rules/RelativeDateResolver.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Rules/RelativeDateResolverTests.swift`

Resolution returns either a single `Date` (for point-in-time meanings like `today`) or, conceptually, a range. For uniformity, `resolve(_:now:calendar:)` returns the **start-of-day** date for keyword forms; range-shaped operators (`withinLastDays`, `withinNextDays`, `on`) construct their own ranges from this anchor. `endOfWeek` / `endOfMonth` resolve to the **last instant of the day** at the boundary (end of Saturday for `endOfWeek` under a Sunday-start calendar). The compiler and the evaluator both rely on this.

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Rules/RelativeDateResolverTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("RelativeDateResolver")
struct RelativeDateResolverTests {
    /// A fixed reference moment: 2026-05-12 (Tuesday) 14:30 UTC.
    static let now: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 12
        c.hour = 14; c.minute = 30; c.second = 0
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }()

    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 1 // Sunday
        return cal
    }

    @Test("today resolves to start of current day")
    func today() {
        let d = RelativeDateResolver.resolve(.today, now: Self.now, calendar: Self.calendar)
        let comps = Self.calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
        #expect(comps.year == 2026)
        #expect(comps.month == 5)
        #expect(comps.day == 12)
        #expect(comps.hour == 0)
        #expect(comps.minute == 0)
        #expect(comps.second == 0)
    }

    @Test("tomorrow is today + 1 day")
    func tomorrow() {
        let d = RelativeDateResolver.resolve(.tomorrow, now: Self.now, calendar: Self.calendar)
        let comps = Self.calendar.dateComponents([.year, .month, .day], from: d)
        #expect(comps.day == 13)
    }

    @Test("yesterday is today - 1 day")
    func yesterday() {
        let d = RelativeDateResolver.resolve(.yesterday, now: Self.now, calendar: Self.calendar)
        let comps = Self.calendar.dateComponents([.year, .month, .day], from: d)
        #expect(comps.day == 11)
    }

    @Test("daysFromNow(7) is today + 7 days")
    func plus7d() {
        let d = RelativeDateResolver.resolve(.daysFromNow(7), now: Self.now, calendar: Self.calendar)
        let comps = Self.calendar.dateComponents([.year, .month, .day], from: d)
        #expect(comps.day == 19)
    }

    @Test("weeksFromNow(-2) is today - 14 days")
    func minus2w() {
        let d = RelativeDateResolver.resolve(.weeksFromNow(-2), now: Self.now, calendar: Self.calendar)
        let comps = Self.calendar.dateComponents([.year, .month, .day], from: d)
        #expect(comps.month == 4)
        #expect(comps.day == 28)
    }

    @Test("startOfWeek with Sunday-firstWeekday resolves to Sunday 2026-05-10")
    func startOfWeek() {
        let d = RelativeDateResolver.resolve(.startOfWeek, now: Self.now, calendar: Self.calendar)
        let comps = Self.calendar.dateComponents([.year, .month, .day, .weekday], from: d)
        #expect(comps.day == 10)
        #expect(comps.weekday == 1) // Sunday
    }

    @Test("endOfWeek with Sunday-firstWeekday resolves to end of Saturday 2026-05-16")
    func endOfWeek() {
        let d = RelativeDateResolver.resolve(.endOfWeek, now: Self.now, calendar: Self.calendar)
        let comps = Self.calendar.dateComponents([.year, .month, .day, .hour], from: d)
        #expect(comps.day == 16)
        // Last instant of the day = 23:59:59
        #expect(comps.hour == 23)
    }

    @Test("startOfMonth is first day of current month")
    func startOfMonth() {
        let d = RelativeDateResolver.resolve(.startOfMonth, now: Self.now, calendar: Self.calendar)
        let comps = Self.calendar.dateComponents([.year, .month, .day, .hour], from: d)
        #expect(comps.month == 5)
        #expect(comps.day == 1)
        #expect(comps.hour == 0)
    }

    @Test("endOfMonth is last instant of last day of current month")
    func endOfMonth() {
        let d = RelativeDateResolver.resolve(.endOfMonth, now: Self.now, calendar: Self.calendar)
        let comps = Self.calendar.dateComponents([.year, .month, .day, .hour], from: d)
        #expect(comps.month == 5)
        #expect(comps.day == 31)
        #expect(comps.hour == 23)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/LillistCore && swift test --filter RelativeDateResolverTests`
Expected: FAIL — `RelativeDateResolver` undefined.

- [ ] **Step 3: Write the implementation**

Write `Packages/LillistCore/Sources/LillistCore/Rules/RelativeDateResolver.swift`:

```swift
import Foundation

/// Resolves a `RelativeDate` to an absolute `Date` using a supplied `now`
/// and `Calendar`. Pure utility — no shared state, safe to call from any
/// isolation context.
public enum RelativeDateResolver {
    public static func resolve(
        _ value: RelativeDate,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        switch value {
        case .today:
            return startOfToday
        case .tomorrow:
            return calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
        case .yesterday:
            return calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        case .daysFromNow(let n):
            return calendar.date(byAdding: .day, value: n, to: startOfToday) ?? startOfToday
        case .weeksFromNow(let n):
            return calendar.date(byAdding: .day, value: n * 7, to: startOfToday) ?? startOfToday
        case .startOfWeek:
            var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            comps.weekday = calendar.firstWeekday
            return calendar.date(from: comps) ?? startOfToday
        case .endOfWeek:
            var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            comps.weekday = calendar.firstWeekday
            guard let start = calendar.date(from: comps) else { return startOfToday }
            let endOfWeekDay = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            return Self.endOfDay(for: endOfWeekDay, calendar: calendar)
        case .startOfMonth:
            var comps = calendar.dateComponents([.year, .month], from: now)
            comps.day = 1
            return calendar.date(from: comps) ?? startOfToday
        case .endOfMonth:
            var comps = calendar.dateComponents([.year, .month], from: now)
            comps.day = 1
            guard let firstOfMonth = calendar.date(from: comps) else { return startOfToday }
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: firstOfMonth) ?? firstOfMonth
            let lastOfMonth = calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? firstOfMonth
            return Self.endOfDay(for: lastOfMonth, calendar: calendar)
        }
    }

    /// 23:59:59 on the same day as `date`.
    static func endOfDay(for date: Date, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        var comps = DateComponents()
        comps.day = 1
        comps.second = -1
        return calendar.date(byAdding: comps, to: startOfDay) ?? startOfDay
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `cd Packages/LillistCore && swift test --filter RelativeDateResolverTests`
Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Rules/RelativeDateResolver.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Rules/RelativeDateResolverTests.swift
git commit -m "feat: add RelativeDateResolver for evaluation-time date resolution"
```

---

## Task 8: `Value` typed union with explicit Codable

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Rules/Value.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Rules/ValueCodableTests.swift`

`Value` is the heterogeneous right-hand-side of a `Leaf`. Each case carries a distinctly-typed payload. Codable is implemented manually so each case is tagged with a stable `kind` discriminator in JSON — required for forward/backward compatibility and human-readable saved filters.

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Rules/ValueCodableTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("Value Codable")
struct ValueCodableTests {
    private func roundTrip(_ value: Value) throws -> Value {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(Value.self, from: data)
    }

    @Test("string round-trips")
    func string() throws {
        #expect(try roundTrip(.string("hello world")) == .string("hello world"))
    }

    @Test("uuidSet round-trips and is order-insensitive in equality? — sets are unordered")
    func uuidSet() throws {
        let a = UUID(); let b = UUID()
        let v: Value = .uuidSet([a, b])
        let decoded = try roundTrip(v)
        if case .uuidSet(let set) = decoded {
            #expect(set == Set([a, b]))
        } else {
            Issue.record("expected .uuidSet")
        }
    }

    @Test("statusSet round-trips")
    func statusSet() throws {
        let v: Value = .statusSet([.todo, .started])
        let decoded = try roundTrip(v)
        if case .statusSet(let set) = decoded {
            #expect(set == Set([.todo, .started]))
        } else {
            Issue.record("expected .statusSet")
        }
    }

    @Test("bool round-trips")
    func bool() throws {
        #expect(try roundTrip(.bool(true)) == .bool(true))
        #expect(try roundTrip(.bool(false)) == .bool(false))
    }

    @Test("absoluteDate round-trips (within millisecond precision)")
    func absoluteDate() throws {
        let now = Date(timeIntervalSince1970: 1_715_500_000)
        let decoded = try roundTrip(.absoluteDate(now))
        if case .absoluteDate(let d) = decoded {
            #expect(abs(d.timeIntervalSince(now)) < 0.001)
        } else {
            Issue.record("expected .absoluteDate")
        }
    }

    @Test("relativeDate round-trips")
    func relativeDate() throws {
        #expect(try roundTrip(.relativeDate(.daysFromNow(7))) == .relativeDate(.daysFromNow(7)))
        #expect(try roundTrip(.relativeDate(.endOfWeek)) == .relativeDate(.endOfWeek))
    }

    @Test("dayCount round-trips")
    func dayCount() throws {
        #expect(try roundTrip(.dayCount(14)) == .dayCount(14))
    }

    @Test("attachmentKind round-trips with and without ofKind")
    func attachmentKind() throws {
        #expect(try roundTrip(.attachmentKind(.init(present: true))) == .attachmentKind(.init(present: true)))
        #expect(try roundTrip(.attachmentKind(.init(present: true, kind: .image))) == .attachmentKind(.init(present: true, kind: .image)))
    }

    @Test("JSON output uses a stable 'kind' discriminator")
    func discriminator() throws {
        let data = try JSONEncoder().encode(Value.string("hi"))
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"kind\""))
        #expect(json.contains("\"string\""))
    }

    @Test("Unknown discriminator throws")
    func unknownDiscriminator() {
        let bogus = #"{"kind":"unicorn","value":1}"#.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(Value.self, from: bogus)
        }
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/LillistCore && swift test --filter ValueCodableTests`
Expected: FAIL — `Value` undefined.

- [ ] **Step 3: Write the implementation**

Write `Packages/LillistCore/Sources/LillistCore/Rules/Value.swift`:

```swift
import Foundation

/// The right-hand side of a `Leaf`. A discriminated union with a stable
/// `kind` field in JSON, so saved filters survive schema evolution.
public enum Value: Codable, Sendable, Equatable {
    case string(String)
    case uuidSet(Set<UUID>)
    case statusSet(Set<Status>)
    case bool(Bool)
    case absoluteDate(Date)
    case relativeDate(RelativeDate)
    case dayCount(Int)
    case attachmentKind(AttachmentKindMatch)

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey { case kind, value }

    private enum Kind: String, Codable {
        case string, uuidSet, statusSet, bool
        case absoluteDate, relativeDate, dayCount, attachmentKind
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .string:
            self = .string(try c.decode(String.self, forKey: .value))
        case .uuidSet:
            let arr = try c.decode([UUID].self, forKey: .value)
            self = .uuidSet(Set(arr))
        case .statusSet:
            let arr = try c.decode([Status].self, forKey: .value)
            self = .statusSet(Set(arr))
        case .bool:
            self = .bool(try c.decode(Bool.self, forKey: .value))
        case .absoluteDate:
            self = .absoluteDate(try c.decode(Date.self, forKey: .value))
        case .relativeDate:
            self = .relativeDate(try c.decode(RelativeDate.self, forKey: .value))
        case .dayCount:
            self = .dayCount(try c.decode(Int.self, forKey: .value))
        case .attachmentKind:
            self = .attachmentKind(try c.decode(AttachmentKindMatch.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let s):
            try c.encode(Kind.string, forKey: .kind)
            try c.encode(s, forKey: .value)
        case .uuidSet(let set):
            try c.encode(Kind.uuidSet, forKey: .kind)
            // Sort for deterministic JSON output.
            try c.encode(set.sorted(by: { $0.uuidString < $1.uuidString }), forKey: .value)
        case .statusSet(let set):
            try c.encode(Kind.statusSet, forKey: .kind)
            try c.encode(set.sorted(by: { $0.rawValue < $1.rawValue }), forKey: .value)
        case .bool(let b):
            try c.encode(Kind.bool, forKey: .kind)
            try c.encode(b, forKey: .value)
        case .absoluteDate(let d):
            try c.encode(Kind.absoluteDate, forKey: .kind)
            try c.encode(d, forKey: .value)
        case .relativeDate(let r):
            try c.encode(Kind.relativeDate, forKey: .kind)
            try c.encode(r, forKey: .value)
        case .dayCount(let n):
            try c.encode(Kind.dayCount, forKey: .kind)
            try c.encode(n, forKey: .value)
        case .attachmentKind(let m):
            try c.encode(Kind.attachmentKind, forKey: .kind)
            try c.encode(m, forKey: .value)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `cd Packages/LillistCore && swift test --filter ValueCodableTests`
Expected: PASS, 10 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Rules/Value.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Rules/ValueCodableTests.swift
git commit -m "feat: add Value typed-union with discriminator-tagged Codable"
```

---

## Task 9: `Leaf`, `PredicateGroup`, and recursive `Predicate`

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Rules/Leaf.swift`
- Create: `Packages/LillistCore/Sources/LillistCore/Rules/PredicateGroup.swift`
- Create: `Packages/LillistCore/Sources/LillistCore/Rules/Predicate.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Rules/PredicateCodableTests.swift`

`Predicate` is an `indirect enum` with `.leaf(Leaf)` and `.group(PredicateGroup)`. `PredicateGroup.predicates: [Predicate]` makes the types mutually recursive. We hand-write `Codable` for `Predicate` so the recursion is explicit. `Leaf` and `PredicateGroup` get auto-synthesized `Codable`.

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Rules/PredicateCodableTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("Predicate Codable")
struct PredicateCodableTests {
    @Test("Leaf round-trips")
    func leafRoundTrip() throws {
        let leaf = Leaf(field: .title, op: .contains, value: .string("design"))
        let data = try JSONEncoder().encode(leaf)
        let decoded = try JSONDecoder().decode(Leaf.self, from: data)
        #expect(decoded == leaf)
    }

    @Test("Flat group with two leaves round-trips")
    func flatGroupRoundTrip() throws {
        let g = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .title, op: .contains, value: .string("foo"))),
            .leaf(.init(field: .status, op: .is, value: .statusSet([.todo])))
        ])
        let data = try JSONEncoder().encode(g)
        let decoded = try JSONDecoder().decode(PredicateGroup.self, from: data)
        #expect(decoded.combinator == .all)
        #expect(decoded.predicates.count == 2)
    }

    @Test("Predicate with nested group round-trips")
    func nestedGroupRoundTrip() throws {
        let p: Predicate = .group(.init(combinator: .all, predicates: [
            .leaf(.init(field: .title, op: .contains, value: .string("a"))),
            .group(.init(combinator: .any, predicates: [
                .leaf(.init(field: .status, op: .is, value: .statusSet([.todo]))),
                .leaf(.init(field: .status, op: .is, value: .statusSet([.started])))
            ]))
        ]))
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(Predicate.self, from: data)
        if case .group(let g) = decoded {
            #expect(g.predicates.count == 2)
            if case .group(let inner) = g.predicates[1] {
                #expect(inner.combinator == .any)
                #expect(inner.predicates.count == 2)
            } else {
                Issue.record("expected inner group")
            }
        } else {
            Issue.record("expected outer group")
        }
    }

    @Test("Predicate JSON uses 'type' discriminator")
    func discriminator() throws {
        let p: Predicate = .leaf(.init(field: .title, op: .contains, value: .string("x")))
        let data = try JSONEncoder().encode(p)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"type\""))
        #expect(json.contains("\"leaf\""))
    }

    @Test("Unknown Predicate type throws on decode")
    func unknownType() {
        let bogus = #"{"type":"sandwich","payload":{}}"#.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(Predicate.self, from: bogus)
        }
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/LillistCore && swift test --filter PredicateCodableTests`
Expected: FAIL — types undefined.

- [ ] **Step 3: Write `Leaf`**

Write `Packages/LillistCore/Sources/LillistCore/Rules/Leaf.swift`:

```swift
import Foundation

/// A single field/operator/value triple. Codable synthesis is automatic.
public struct Leaf: Codable, Sendable, Equatable {
    public var field: Field
    public var op: Op
    public var value: Value

    public init(field: Field, op: Op, value: Value) {
        self.field = field
        self.op = op
        self.value = value
    }
}
```

- [ ] **Step 4: Write `PredicateGroup`**

Write `Packages/LillistCore/Sources/LillistCore/Rules/PredicateGroup.swift`:

```swift
import Foundation

/// A combinator over zero-or-more child predicates. Per design Section 5,
/// v1's authoring UI is flat AND/OR; the data model is already recursive to
/// accommodate v2's nested groups.
public struct PredicateGroup: Codable, Sendable, Equatable {
    public enum Combinator: String, Codable, Sendable { case all, any }

    public var combinator: Combinator
    public var predicates: [Predicate]

    public init(combinator: Combinator, predicates: [Predicate]) {
        self.combinator = combinator
        self.predicates = predicates
    }
}
```

- [ ] **Step 5: Write `Predicate`**

Write `Packages/LillistCore/Sources/LillistCore/Rules/Predicate.swift`:

```swift
import Foundation

/// The recursive predicate type. v1 UIs build only single-level groups; the
/// data model is already nested for v2 nested-group authoring.
///
/// Codable is hand-written: automatic synthesis fails on mutually-recursive
/// types (`Predicate` ↔ `PredicateGroup.predicates: [Predicate]`).
public indirect enum Predicate: Codable, Sendable, Equatable {
    case leaf(Leaf)
    case group(PredicateGroup)

    private enum CodingKeys: String, CodingKey { case type, payload }

    private enum Kind: String, Codable {
        case leaf
        case group
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .type)
        switch kind {
        case .leaf:
            let leaf = try c.decode(Leaf.self, forKey: .payload)
            self = .leaf(leaf)
        case .group:
            let group = try c.decode(PredicateGroup.self, forKey: .payload)
            self = .group(group)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .leaf(let l):
            try c.encode(Kind.leaf, forKey: .type)
            try c.encode(l, forKey: .payload)
        case .group(let g):
            try c.encode(Kind.group, forKey: .type)
            try c.encode(g, forKey: .payload)
        }
    }
}
```

- [ ] **Step 6: Run tests to verify pass**

Run: `cd Packages/LillistCore && swift test --filter PredicateCodableTests`
Expected: PASS, 5 tests.

- [ ] **Step 7: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Rules/Leaf.swift \
        Packages/LillistCore/Sources/LillistCore/Rules/PredicateGroup.swift \
        Packages/LillistCore/Sources/LillistCore/Rules/Predicate.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Rules/PredicateCodableTests.swift
git commit -m "feat: add Leaf, PredicateGroup, and recursive Predicate with hand-written Codable"
```

---

## Task 10: `NSPredicateCompiler` — scalar and string leaves

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Rules/NSPredicateCompilerTests.swift`

We build the compiler in three slices so each commit is small. Slice 1: scalar leaves (`status`, `isPinned`, `hasChildren` via count, `inTrash`) and string leaves (`title`, `notes`). The implicit-`inTrash` rule is enforced at the top-level `compile(_:)` entry point.

- [ ] **Step 1: Write failing tests for slice 1**

Write `Packages/LillistCore/Tests/LillistCoreTests/Rules/NSPredicateCompilerTests.swift`:

```swift
import Testing
import Foundation
import CoreData
@testable import LillistCore

@Suite("NSPredicateCompiler — scalar/string slice")
struct NSPredicateCompilerTests {
    @Test("Empty group matches all non-trashed (implicit inTrash filter)")
    func emptyGroupAppliesImplicitTrashFilter() {
        let group = PredicateGroup(combinator: .all, predicates: [])
        let p = NSPredicateCompiler.compile(group)
        let format = p.predicateFormat
        #expect(format.contains("deletedAt") || format.contains("inTrash") || format.contains("== nil"))
    }

    @Test("title contains compiles to CONTAINS[cd]")
    func titleContains() {
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .title, op: .contains, value: .string("design")))
        ])
        let p = NSPredicateCompiler.compile(group)
        #expect(p.predicateFormat.contains("title"))
        #expect(p.predicateFormat.uppercased().contains("CONTAINS"))
    }

    @Test("status is statusSet compiles to IN")
    func statusIs() {
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .status, op: .is, value: .statusSet([.todo, .started])))
        ])
        let p = NSPredicateCompiler.compile(group)
        #expect(p.predicateFormat.contains("statusRaw"))
        #expect(p.predicateFormat.uppercased().contains("IN"))
    }

    @Test("isPinned is bool(true) compiles to == YES")
    func isPinned() {
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .isPinned, op: .is, value: .bool(true)))
        ])
        let p = NSPredicateCompiler.compile(group)
        #expect(p.predicateFormat.contains("isPinned"))
    }

    @Test("Explicit inTrash leaf suppresses implicit trash filter")
    func explicitInTrashSuppressesImplicit() {
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .inTrash, op: .is, value: .bool(true)))
        ])
        let p = NSPredicateCompiler.compile(group)
        // The compiled predicate should reference deletedAt only once
        // (from the explicit leaf), not twice (explicit + implicit).
        let occurrences = p.predicateFormat.components(separatedBy: "deletedAt").count - 1
        #expect(occurrences == 1)
    }

    @Test("Compiled predicate evaluates against a real fetched task")
    func evaluatesAgainstFetchedTask() async throws {
        let controller = try await TestStore.make()
        let ctx = controller.container.viewContext
        try await ctx.perform {
            let t = LillistTask(context: ctx)
            t.id = UUID()
            t.title = "Design review"
            t.notes = ""
            t.status = .todo
            t.isPinned = false
            t.createdAt = Date()
            t.modifiedAt = Date()
            try ctx.save()
        }
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .title, op: .contains, value: .string("design")))
        ])
        let p = NSPredicateCompiler.compile(group)
        let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
        req.predicate = p
        let results = try await ctx.perform { try ctx.fetch(req) }
        #expect(results.count == 1)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/LillistCore && swift test --filter NSPredicateCompilerTests`
Expected: FAIL — `NSPredicateCompiler` undefined.

- [ ] **Step 3: Write the slice-1 implementation**

Write `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift`:

```swift
import Foundation
import CoreData

/// Translates a `PredicateGroup` into an `NSPredicate` over the `LillistTask`
/// entity. The compiled predicate is suitable for `NSFetchRequest.predicate`
/// and `NSFetchedResultsController`.
///
/// The implicit-trash rule (design Section 5): unless the group contains a
/// leaf with `field == .inTrash`, the compiled top-level predicate
/// conjoins `deletedAt == nil` so smart filters never surface Trash.
public enum NSPredicateCompiler {
    /// Top-level entry point. `now` and `calendar` are used to resolve
    /// `RelativeDate` values at compile time. Callers wishing live-updating
    /// "rolling 7 days" semantics must recompile on a timer (handled by the
    /// SmartFilter view layer in later plans).
    public static func compile(
        _ group: PredicateGroup,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> NSPredicate {
        let base = compileGroup(group, now: now, calendar: calendar)
        if containsField(.inTrash, in: group) {
            return base
        }
        let trashFilter = NSPredicate(format: "deletedAt == nil")
        return NSCompoundPredicate(andPredicateWithSubpredicates: [base, trashFilter])
    }

    static func compileGroup(
        _ group: PredicateGroup,
        now: Date,
        calendar: Calendar
    ) -> NSPredicate {
        if group.predicates.isEmpty {
            return NSPredicate(value: true)
        }
        let subs = group.predicates.map { compilePredicate($0, now: now, calendar: calendar) }
        switch group.combinator {
        case .all: return NSCompoundPredicate(andPredicateWithSubpredicates: subs)
        case .any: return NSCompoundPredicate(orPredicateWithSubpredicates: subs)
        }
    }

    static func compilePredicate(
        _ predicate: Predicate,
        now: Date,
        calendar: Calendar
    ) -> NSPredicate {
        switch predicate {
        case .leaf(let leaf):
            return compileLeaf(leaf, now: now, calendar: calendar)
        case .group(let g):
            return compileGroup(g, now: now, calendar: calendar)
        }
    }

    static func compileLeaf(
        _ leaf: Leaf,
        now: Date,
        calendar: Calendar
    ) -> NSPredicate {
        switch leaf.field {
        case .title: return compileString(keyPath: "title", op: leaf.op, value: leaf.value)
        case .notes: return compileString(keyPath: "notes", op: leaf.op, value: leaf.value)
        case .status: return compileStatus(op: leaf.op, value: leaf.value)
        case .isPinned: return compileBool(keyPath: "isPinned", op: leaf.op, value: leaf.value)
        case .inTrash: return compileInTrash(op: leaf.op, value: leaf.value)
        case .hasChildren: return compileHasChildren(op: leaf.op, value: leaf.value)
        // Slices 2 and 3 add the remaining fields.
        default:
            // Unreachable until later slices wire in remaining fields.
            return NSPredicate(value: false)
        }
    }

    // MARK: - String

    static func compileString(keyPath: String, op: Op, value: Value) -> NSPredicate {
        guard case .string(let s) = value else { return NSPredicate(value: false) }
        switch op {
        case .contains:
            return NSPredicate(format: "%K CONTAINS[cd] %@", keyPath, s)
        case .equals:
            return NSPredicate(format: "%K ==[cd] %@", keyPath, s)
        case .startsWith:
            return NSPredicate(format: "%K BEGINSWITH[cd] %@", keyPath, s)
        default:
            return NSPredicate(value: false)
        }
    }

    // MARK: - Status

    static func compileStatus(op: Op, value: Value) -> NSPredicate {
        guard case .statusSet(let set) = value else { return NSPredicate(value: false) }
        let raws = set.map { Int16($0.rawValue) } as [Int16]
        switch op {
        case .is: return NSPredicate(format: "statusRaw IN %@", raws)
        case .isNot: return NSPredicate(format: "NOT (statusRaw IN %@)", raws)
        default: return NSPredicate(value: false)
        }
    }

    // MARK: - Bool

    static func compileBool(keyPath: String, op: Op, value: Value) -> NSPredicate {
        guard case .bool(let b) = value, op == .is else { return NSPredicate(value: false) }
        return NSPredicate(format: "%K == %@", keyPath, NSNumber(value: b))
    }

    // MARK: - inTrash

    static func compileInTrash(op: Op, value: Value) -> NSPredicate {
        guard case .bool(let b) = value, op == .is else { return NSPredicate(value: false) }
        return b
            ? NSPredicate(format: "deletedAt != nil")
            : NSPredicate(format: "deletedAt == nil")
    }

    // MARK: - hasChildren

    static func compileHasChildren(op: Op, value: Value) -> NSPredicate {
        guard case .bool(let b) = value, op == .is else { return NSPredicate(value: false) }
        return b
            ? NSPredicate(format: "children.@count > 0")
            : NSPredicate(format: "children.@count == 0")
    }

    // MARK: - Field-presence check (for implicit trash rule)

    static func containsField(_ target: Field, in group: PredicateGroup) -> Bool {
        for p in group.predicates {
            switch p {
            case .leaf(let l) where l.field == target: return true
            case .group(let g) where containsField(target, in: g): return true
            default: continue
            }
        }
        return false
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `cd Packages/LillistCore && swift test --filter NSPredicateCompilerTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Rules/NSPredicateCompilerTests.swift
git commit -m "feat: add NSPredicateCompiler covering string/status/bool/inTrash leaves"
```

---

## Task 11: `NSPredicateCompiler` — date leaves and `hasAttachments`/`hasNudges`/`recurrence`

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift`
- Modify: `Packages/LillistCore/Tests/LillistCoreTests/Rules/NSPredicateCompilerTests.swift`

Slice 2: date leaves (`start`, `deadline`, `createdAt`, `modifiedAt`, `closedAt` — operators `before`, `after`, `on`, `withinLastDays`, `withinNextDays`, `isSet`, `isUnset`, plus `equalsModifiedAt` on `createdAt`). Also adds the simple existence-shaped fields: `hasAttachments` (with optional `ofKind`), `hasNudges` (via JournalEntry/NotificationSpec — note: `NotificationSpec` doesn't exist until Plan 4, so `hasNudges` is compiled as `false` for now and tests gate it accordingly), and `recurrence` (Series doesn't exist until Plan 5, same treatment).

> **Forward-compatibility shim.** `hasNudges` and `recurrence` produce a `NSPredicate(value: false)` for now and a comment marker. Plan 4 wires up `hasNudges`; Plan 5 wires up `recurrence`. The fixture suite in Tasks 17–18 excludes these two fields until those plans land.

- [ ] **Step 1: Append failing tests for date and attachment leaves**

Append to `Packages/LillistCore/Tests/LillistCoreTests/Rules/NSPredicateCompilerTests.swift` a new sibling suite:

```swift
@Suite("NSPredicateCompiler — date/attachment slice")
struct NSPredicateCompilerDateTests {
    @Test("deadline before absoluteDate")
    func deadlineBeforeAbsolute() {
        let d = Date()
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .deadline, op: .before, value: .absoluteDate(d)))
        ])
        let p = NSPredicateCompiler.compile(group)
        #expect(p.predicateFormat.contains("deadline"))
        #expect(p.predicateFormat.contains("<"))
    }

    @Test("start withinNextDays(7) resolves at compile time")
    func startWithinNextDays() {
        let now = Date(timeIntervalSince1970: 1_715_500_000)
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .start, op: .withinNextDays, value: .dayCount(7)))
        ])
        let p = NSPredicateCompiler.compile(group, now: now, calendar: .current)
        #expect(p.predicateFormat.contains("start"))
    }

    @Test("deadline isSet vs isUnset")
    func deadlineIsSet() {
        let setGroup = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .deadline, op: .isSet, value: .bool(true)))
        ])
        let unsetGroup = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .deadline, op: .isUnset, value: .bool(true)))
        ])
        #expect(NSPredicateCompiler.compile(setGroup).predicateFormat.contains("!= nil"))
        #expect(NSPredicateCompiler.compile(unsetGroup).predicateFormat.contains("== nil"))
    }

    @Test("createdAt equalsModifiedAt")
    func createdEqualsModified() {
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .createdAt, op: .equalsModifiedAt, value: .bool(true)))
        ])
        let p = NSPredicateCompiler.compile(group)
        let f = p.predicateFormat
        #expect(f.contains("createdAt"))
        #expect(f.contains("modifiedAt"))
    }

    @Test("hasAttachments is bool(true) with no ofKind")
    func hasAttachmentsAny() {
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .hasAttachments, op: .is, value: .attachmentKind(.init(present: true))))
        ])
        let p = NSPredicateCompiler.compile(group)
        #expect(p.predicateFormat.contains("attachments"))
    }

    @Test("hasAttachments is bool(true) with ofKind = image")
    func hasAttachmentsImage() {
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .hasAttachments, op: .is, value: .attachmentKind(.init(present: true, kind: .image))))
        ])
        let p = NSPredicateCompiler.compile(group)
        #expect(p.predicateFormat.contains("kindRaw"))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/LillistCore && swift test --filter NSPredicateCompilerDateTests`
Expected: FAIL — date/attachment cases not yet handled.

- [ ] **Step 3: Extend the compiler**

Edit `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift`. Replace the `default:` branch in `compileLeaf` with explicit handling, and add the supporting helpers. The final `compileLeaf` body:

```swift
    static func compileLeaf(
        _ leaf: Leaf,
        now: Date,
        calendar: Calendar
    ) -> NSPredicate {
        switch leaf.field {
        case .title: return compileString(keyPath: "title", op: leaf.op, value: leaf.value)
        case .notes: return compileString(keyPath: "notes", op: leaf.op, value: leaf.value)
        case .status: return compileStatus(op: leaf.op, value: leaf.value)
        case .isPinned: return compileBool(keyPath: "isPinned", op: leaf.op, value: leaf.value)
        case .inTrash: return compileInTrash(op: leaf.op, value: leaf.value)
        case .hasChildren: return compileHasChildren(op: leaf.op, value: leaf.value)

        case .start, .deadline, .createdAt, .modifiedAt, .closedAt:
            return compileDate(field: leaf.field, op: leaf.op, value: leaf.value, now: now, calendar: calendar)

        case .hasAttachments:
            return compileHasAttachments(op: leaf.op, value: leaf.value)

        case .journalText:
            return compileJournalText(op: leaf.op, value: leaf.value)

        case .tag:
            return compileTag(op: leaf.op, value: leaf.value)

        case .ancestor:
            return compileAncestor(op: leaf.op, value: leaf.value)

        case .hasNudges, .recurrence:
            // Wired up by Plans 4 and 5 respectively.
            return NSPredicate(value: false)
        }
    }
```

Append the new helpers (after `compileHasChildren`):

```swift
    // MARK: - Dates

    static func compileDate(
        field: Field,
        op: Op,
        value: Value,
        now: Date,
        calendar: Calendar
    ) -> NSPredicate {
        let keyPath = field.rawValue // matches Core Data attribute name
        switch op {
        case .before:
            guard let d = resolveAbsolute(value, now: now, calendar: calendar) else {
                return NSPredicate(value: false)
            }
            return NSPredicate(format: "%K < %@", keyPath, d as NSDate)
        case .after:
            guard let d = resolveAbsolute(value, now: now, calendar: calendar) else {
                return NSPredicate(value: false)
            }
            return NSPredicate(format: "%K > %@", keyPath, d as NSDate)
        case .on:
            guard let d = resolveAbsolute(value, now: now, calendar: calendar) else {
                return NSPredicate(value: false)
            }
            let startOfDay = calendar.startOfDay(for: d)
            let endOfDay = RelativeDateResolver.endOfDay(for: startOfDay, calendar: calendar)
            return NSPredicate(format: "%K >= %@ AND %K <= %@", keyPath, startOfDay as NSDate, keyPath, endOfDay as NSDate)
        case .withinLastDays:
            guard case .dayCount(let n) = value else { return NSPredicate(value: false) }
            let startOfToday = calendar.startOfDay(for: now)
            let cutoff = calendar.date(byAdding: .day, value: -n, to: startOfToday) ?? startOfToday
            return NSPredicate(format: "%K >= %@ AND %K <= %@", keyPath, cutoff as NSDate, keyPath, now as NSDate)
        case .withinNextDays:
            guard case .dayCount(let n) = value else { return NSPredicate(value: false) }
            let startOfToday = calendar.startOfDay(for: now)
            let horizon = calendar.date(byAdding: .day, value: n, to: startOfToday) ?? startOfToday
            let horizonEnd = RelativeDateResolver.endOfDay(for: horizon, calendar: calendar)
            return NSPredicate(format: "%K >= %@ AND %K <= %@", keyPath, now as NSDate, keyPath, horizonEnd as NSDate)
        case .isSet:
            return NSPredicate(format: "%K != nil", keyPath)
        case .isUnset:
            return NSPredicate(format: "%K == nil", keyPath)
        case .equalsModifiedAt where field == .createdAt:
            return NSPredicate(format: "createdAt == modifiedAt")
        default:
            return NSPredicate(value: false)
        }
    }

    static func resolveAbsolute(_ value: Value, now: Date, calendar: Calendar) -> Date? {
        switch value {
        case .absoluteDate(let d): return d
        case .relativeDate(let r): return RelativeDateResolver.resolve(r, now: now, calendar: calendar)
        default: return nil
        }
    }

    // MARK: - Attachments

    static func compileHasAttachments(op: Op, value: Value) -> NSPredicate {
        guard case .attachmentKind(let match) = value, op == .is else {
            return NSPredicate(value: false)
        }
        if let kind = match.kind {
            let kindRaw = Int16(kind.rawValue)
            let sub = NSPredicate(format: "SUBQUERY(attachments, $a, $a.kindRaw == %d).@count > 0", kindRaw)
            return match.present ? sub : NSCompoundPredicate(notPredicateWithSubpredicate: sub)
        } else {
            return match.present
                ? NSPredicate(format: "attachments.@count > 0")
                : NSPredicate(format: "attachments.@count == 0")
        }
    }

    // MARK: - Journal text (slice 3 fills these)

    static func compileJournalText(op: Op, value: Value) -> NSPredicate {
        // Stub — Task 12 wires up the subquery shape.
        return NSPredicate(value: false)
    }

    static func compileTag(op: Op, value: Value) -> NSPredicate {
        return NSPredicate(value: false)
    }

    static func compileAncestor(op: Op, value: Value) -> NSPredicate {
        return NSPredicate(value: false)
    }
```

- [ ] **Step 4: Run tests to verify pass**

Run: `cd Packages/LillistCore && swift test --filter NSPredicateCompiler`
Expected: PASS for all NSPredicateCompiler tests (~12 by now).

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Rules/NSPredicateCompilerTests.swift
git commit -m "feat: extend NSPredicateCompiler with date and attachment-kind leaves"
```

---

## Task 12: `NSPredicateCompiler` — `journalText`, `tag.*`, `ancestor.*` subqueries

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift`
- Modify: `Packages/LillistCore/Tests/LillistCoreTests/Rules/NSPredicateCompilerTests.swift`

The trickiest leaves — relationship-shaped, require `SUBQUERY` / set-comparison forms.

- [ ] **Step 1: Append failing tests**

Append to `Packages/LillistCore/Tests/LillistCoreTests/Rules/NSPredicateCompilerTests.swift`:

```swift
@Suite("NSPredicateCompiler — subquery slice")
struct NSPredicateCompilerSubqueryTests {
    @Test("journalText contains compiles to SUBQUERY over note-kind journal entries")
    func journalTextContains() {
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .journalText, op: .contains, value: .string("blocker")))
        ])
        let p = NSPredicateCompiler.compile(group)
        let f = p.predicateFormat.uppercased()
        #expect(f.contains("SUBQUERY"))
        #expect(p.predicateFormat.contains("journalEntries"))
        #expect(p.predicateFormat.contains("body"))
    }

    @Test("tag includesAny compiles to ANY tags.id IN <set>")
    func tagIncludesAny() {
        let a = UUID(); let b = UUID()
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .tag, op: .includesAny, value: .uuidSet([a, b])))
        ])
        let p = NSPredicateCompiler.compile(group)
        #expect(p.predicateFormat.uppercased().contains("ANY") || p.predicateFormat.uppercased().contains("SUBQUERY"))
        #expect(p.predicateFormat.contains("tags"))
    }

    @Test("tag includesAll compiles to per-id SUBQUERY count == n")
    func tagIncludesAll() {
        let a = UUID(); let b = UUID()
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .tag, op: .includesAll, value: .uuidSet([a, b])))
        ])
        let p = NSPredicateCompiler.compile(group)
        #expect(p.predicateFormat.uppercased().contains("SUBQUERY"))
        #expect(p.predicateFormat.contains("tags"))
    }

    @Test("tag excludesAll compiles to NONE form")
    func tagExcludesAll() {
        let a = UUID()
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .tag, op: .excludesAll, value: .uuidSet([a])))
        ])
        let p = NSPredicateCompiler.compile(group)
        let f = p.predicateFormat.uppercased()
        #expect(f.contains("NONE") || f.contains("NOT"))
    }

    @Test("ancestor isDescendantOf uses parent traversal predicate")
    func ancestorIsDescendantOf() {
        let id = UUID()
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .ancestor, op: .isDescendantOf, value: .uuidSet([id])))
        ])
        let p = NSPredicateCompiler.compile(group)
        #expect(p.predicateFormat.contains("parent"))
    }

    @Test("End-to-end: journalText subquery returns the right task")
    func journalTextEndToEnd() async throws {
        let controller = try await TestStore.make()
        let ctx = controller.container.viewContext
        let id = UUID()
        try await ctx.perform {
            let t = LillistTask(context: ctx)
            t.id = id
            t.title = "T"
            t.notes = ""
            t.status = .todo
            t.createdAt = Date(); t.modifiedAt = Date()
            let j = JournalEntry(context: ctx)
            j.id = UUID()
            j.kind = .note
            j.body = "Blocked by external dependency"
            j.createdAt = Date()
            j.task = t
            try ctx.save()
        }
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .journalText, op: .contains, value: .string("dependency")))
        ])
        let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
        req.predicate = NSPredicateCompiler.compile(group)
        let results = try await ctx.perform { try ctx.fetch(req) }
        #expect(results.count == 1)
        #expect(results.first?.id == id)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/LillistCore && swift test --filter NSPredicateCompilerSubqueryTests`
Expected: FAIL — subquery helpers still return `false`.

- [ ] **Step 3: Replace the three stub helpers with real implementations**

In `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift`, replace `compileJournalText`, `compileTag`, and `compileAncestor` with:

```swift
    // MARK: - Journal text

    static func compileJournalText(op: Op, value: Value) -> NSPredicate {
        guard op == .contains, case .string(let s) = value else {
            return NSPredicate(value: false)
        }
        let noteKindRaw = Int16(JournalEntryKind.note.rawValue)
        // Find tasks whose `journalEntries` include at least one note-kind
        // entry whose body contains the search string.
        return NSPredicate(
            format: "SUBQUERY(journalEntries, $j, $j.kindRaw == %d AND $j.body CONTAINS[cd] %@).@count > 0",
            noteKindRaw,
            s
        )
    }

    // MARK: - Tags

    static func compileTag(op: Op, value: Value) -> NSPredicate {
        guard case .uuidSet(let ids) = value else { return NSPredicate(value: false) }
        let idArr = Array(ids)
        switch op {
        case .includesAny:
            return NSPredicate(format: "SUBQUERY(tags, $t, $t.id IN %@).@count > 0", idArr)
        case .includesAll:
            // The task must have at least one matching tag per id.
            let subs: [NSPredicate] = idArr.map { id in
                NSPredicate(format: "SUBQUERY(tags, $t, $t.id == %@).@count > 0", id as CVarArg)
            }
            return NSCompoundPredicate(andPredicateWithSubpredicates: subs)
        case .excludesAll:
            return NSPredicate(format: "SUBQUERY(tags, $t, $t.id IN %@).@count == 0", idArr)
        default:
            return NSPredicate(value: false)
        }
    }

    // MARK: - Ancestor

    static func compileAncestor(op: Op, value: Value) -> NSPredicate {
        guard case .uuidSet(let ids) = value else { return NSPredicate(value: false) }
        switch op {
        case .isDescendantOf:
            // Task whose parent (or transitive ancestor) is one of the ids.
            // Core Data does not expose transitive closure in predicate format,
            // so we OR a fixed depth of parent.id checks. v1 supports depth ≤ 8.
            let depths = (1...8).map { depth -> NSPredicate in
                let keyPath = (0..<depth).map { _ in "parent" }.joined(separator: ".") + ".id"
                return NSPredicate(format: "%K IN %@", keyPath, Array(ids))
            }
            return NSCompoundPredicate(orPredicateWithSubpredicates: depths)
        case .isAncestorOf:
            // Task whose `id` is the parent (or transitive ancestor) of one of
            // the given task ids. Without a reverse traversal helper this
            // would require a fetch — we fall back to a runtime SUBQUERY over
            // `children`, again bounded to depth 8.
            let depths = (1...8).map { depth -> NSPredicate in
                let keyPath = (0..<depth).map { _ in "children" }.joined(separator: ".") + ".id"
                return NSPredicate(format: "ANY %K IN %@", keyPath, Array(ids))
            }
            return NSCompoundPredicate(orPredicateWithSubpredicates: depths)
        default:
            return NSPredicate(value: false)
        }
    }
```

- [ ] **Step 4: Run tests to verify pass**

Run: `cd Packages/LillistCore && swift test --filter NSPredicateCompiler`
Expected: PASS for all NSPredicateCompiler suites.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Rules/NSPredicateCompilerTests.swift
git commit -m "feat: extend NSPredicateCompiler with journalText/tag/ancestor subqueries"
```

---

## Task 13: `SwiftEvaluator` — input shape and scalar/string leaves

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Rules/SwiftEvaluatorTests.swift`

`SwiftEvaluator` evaluates a `PredicateGroup` against a snapshot of a task. To stay symmetrical with the `NSPredicateCompiler` path and to support every field, the evaluator works against a `SwiftEvaluator.TaskSnapshot` — a denormalized value type carrying everything the rule engine might need (status flags, tag ids, journal note bodies, ancestor ids, child count). Callers build snapshots from either `TaskStore.TaskRecord` + the relational helpers (used in `SmartFilter.evaluate(persistence:)`) or directly from fetched `LillistTask` objects.

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Rules/SwiftEvaluatorTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("SwiftEvaluator — scalar/string slice")
struct SwiftEvaluatorTests {
    private func snapshot(
        title: String = "T",
        notes: String = "",
        status: Status = .todo,
        isPinned: Bool = false,
        inTrash: Bool = false,
        hasChildren: Bool = false
    ) -> SwiftEvaluator.TaskSnapshot {
        SwiftEvaluator.TaskSnapshot(
            id: UUID(),
            title: title,
            notes: notes,
            status: status,
            start: nil, startHasTime: false,
            deadline: nil, deadlineHasTime: false,
            createdAt: Date(), modifiedAt: Date(),
            closedAt: nil,
            isPinned: isPinned,
            inTrash: inTrash,
            hasChildren: hasChildren,
            childCount: hasChildren ? 1 : 0,
            tagIDs: [],
            ancestorIDs: [],
            journalNoteBodies: [],
            attachmentKinds: [],
            hasNudges: false,
            isRecurring: false
        )
    }

    @Test("Empty group matches non-trashed snapshot")
    func emptyGroup() {
        let g = PredicateGroup(combinator: .all, predicates: [])
        #expect(SwiftEvaluator.evaluate(group: g, against: snapshot()) == true)
        #expect(SwiftEvaluator.evaluate(group: g, against: snapshot(inTrash: true)) == false)
    }

    @Test("title contains")
    func titleContains() {
        let g = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .title, op: .contains, value: .string("design")))
        ])
        #expect(SwiftEvaluator.evaluate(group: g, against: snapshot(title: "Design review")) == true)
        #expect(SwiftEvaluator.evaluate(group: g, against: snapshot(title: "Spec writing")) == false)
    }

    @Test("title equals is case-insensitive")
    func titleEqualsCaseInsensitive() {
        let g = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .title, op: .equals, value: .string("Inbox")))
        ])
        #expect(SwiftEvaluator.evaluate(group: g, against: snapshot(title: "inbox")) == true)
    }

    @Test("status is statusSet")
    func statusIs() {
        let g = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .status, op: .is, value: .statusSet([.todo, .started])))
        ])
        #expect(SwiftEvaluator.evaluate(group: g, against: snapshot(status: .todo)) == true)
        #expect(SwiftEvaluator.evaluate(group: g, against: snapshot(status: .closed)) == false)
    }

    @Test("isPinned is bool")
    func isPinned() {
        let g = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .isPinned, op: .is, value: .bool(true)))
        ])
        #expect(SwiftEvaluator.evaluate(group: g, against: snapshot(isPinned: true)) == true)
        #expect(SwiftEvaluator.evaluate(group: g, against: snapshot(isPinned: false)) == false)
    }

    @Test("hasChildren is bool")
    func hasChildren() {
        let g = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .hasChildren, op: .is, value: .bool(true)))
        ])
        #expect(SwiftEvaluator.evaluate(group: g, against: snapshot(hasChildren: true)) == true)
        #expect(SwiftEvaluator.evaluate(group: g, against: snapshot(hasChildren: false)) == false)
    }

    @Test("Explicit inTrash leaf suppresses implicit trash filter")
    func explicitInTrash() {
        let g = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .inTrash, op: .is, value: .bool(true)))
        ])
        #expect(SwiftEvaluator.evaluate(group: g, against: snapshot(inTrash: true)) == true)
        #expect(SwiftEvaluator.evaluate(group: g, against: snapshot(inTrash: false)) == false)
    }

    @Test("Combinator .any matches at least one leaf")
    func anyCombinator() {
        let g = PredicateGroup(combinator: .any, predicates: [
            .leaf(.init(field: .title, op: .contains, value: .string("zzz"))),
            .leaf(.init(field: .status, op: .is, value: .statusSet([.todo])))
        ])
        #expect(SwiftEvaluator.evaluate(group: g, against: snapshot(status: .todo)) == true)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/LillistCore && swift test --filter SwiftEvaluatorTests`
Expected: FAIL — `SwiftEvaluator` undefined.

- [ ] **Step 3: Write the implementation**

Write `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift`:

```swift
import Foundation

/// Pure-Swift evaluator for a `PredicateGroup`. Operates on a denormalized
/// snapshot so callers can prepare the per-task data however they like
/// (in-memory fetched results, exported records, CLI input). Behavior
/// matches `NSPredicateCompiler` — the parity fixture suite enforces it.
public enum SwiftEvaluator {
    /// Denormalized snapshot of a task. Includes every field the rule engine
    /// might query, including relational fan-outs (tag ids, ancestor ids,
    /// journal note bodies, attachment kinds).
    public struct TaskSnapshot: Sendable, Equatable {
        public var id: UUID
        public var title: String
        public var notes: String
        public var status: Status
        public var start: Date?
        public var startHasTime: Bool
        public var deadline: Date?
        public var deadlineHasTime: Bool
        public var createdAt: Date
        public var modifiedAt: Date
        public var closedAt: Date?
        public var isPinned: Bool
        public var inTrash: Bool
        public var hasChildren: Bool
        public var childCount: Int
        public var tagIDs: Set<UUID>
        public var ancestorIDs: Set<UUID>
        public var journalNoteBodies: [String]
        public var attachmentKinds: [AttachmentKind]
        public var hasNudges: Bool
        public var isRecurring: Bool

        public init(
            id: UUID,
            title: String,
            notes: String,
            status: Status,
            start: Date?, startHasTime: Bool,
            deadline: Date?, deadlineHasTime: Bool,
            createdAt: Date, modifiedAt: Date,
            closedAt: Date?,
            isPinned: Bool,
            inTrash: Bool,
            hasChildren: Bool,
            childCount: Int,
            tagIDs: Set<UUID>,
            ancestorIDs: Set<UUID>,
            journalNoteBodies: [String],
            attachmentKinds: [AttachmentKind],
            hasNudges: Bool,
            isRecurring: Bool
        ) {
            self.id = id
            self.title = title
            self.notes = notes
            self.status = status
            self.start = start; self.startHasTime = startHasTime
            self.deadline = deadline; self.deadlineHasTime = deadlineHasTime
            self.createdAt = createdAt; self.modifiedAt = modifiedAt
            self.closedAt = closedAt
            self.isPinned = isPinned
            self.inTrash = inTrash
            self.hasChildren = hasChildren
            self.childCount = childCount
            self.tagIDs = tagIDs
            self.ancestorIDs = ancestorIDs
            self.journalNoteBodies = journalNoteBodies
            self.attachmentKinds = attachmentKinds
            self.hasNudges = hasNudges
            self.isRecurring = isRecurring
        }
    }

    // MARK: - Top-level entry

    public static func evaluate(
        group: PredicateGroup,
        against snapshot: TaskSnapshot,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        if !NSPredicateCompiler.containsField(.inTrash, in: group), snapshot.inTrash {
            return false
        }
        return evaluateGroup(group, snapshot: snapshot, now: now, calendar: calendar)
    }

    static func evaluateGroup(
        _ group: PredicateGroup,
        snapshot: TaskSnapshot,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        if group.predicates.isEmpty { return true }
        switch group.combinator {
        case .all:
            return group.predicates.allSatisfy {
                evaluatePredicate($0, snapshot: snapshot, now: now, calendar: calendar)
            }
        case .any:
            return group.predicates.contains {
                evaluatePredicate($0, snapshot: snapshot, now: now, calendar: calendar)
            }
        }
    }

    static func evaluatePredicate(
        _ predicate: Predicate,
        snapshot: TaskSnapshot,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        switch predicate {
        case .leaf(let l): return evaluateLeaf(l, snapshot: snapshot, now: now, calendar: calendar)
        case .group(let g): return evaluateGroup(g, snapshot: snapshot, now: now, calendar: calendar)
        }
    }

    // MARK: - Leaf dispatch (slice 1)

    static func evaluateLeaf(
        _ leaf: Leaf,
        snapshot s: TaskSnapshot,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        switch leaf.field {
        case .title: return matchString(s.title, op: leaf.op, value: leaf.value)
        case .notes: return matchString(s.notes, op: leaf.op, value: leaf.value)
        case .status: return matchStatus(s.status, op: leaf.op, value: leaf.value)
        case .isPinned: return matchBool(s.isPinned, op: leaf.op, value: leaf.value)
        case .inTrash: return matchBool(s.inTrash, op: leaf.op, value: leaf.value)
        case .hasChildren: return matchBool(s.hasChildren, op: leaf.op, value: leaf.value)
        case .hasNudges: return matchBool(s.hasNudges, op: leaf.op, value: leaf.value)
        case .recurrence: return matchBool(s.isRecurring, op: leaf.op, value: leaf.value)
        // Slice 2 fills the remaining fields.
        default: return false
        }
    }

    // MARK: - Primitive matchers (slice 1)

    static func matchString(_ haystack: String, op: Op, value: Value) -> Bool {
        guard case .string(let needle) = value else { return false }
        switch op {
        case .contains: return haystack.localizedStandardContains(needle)
        case .equals: return haystack.localizedCaseInsensitiveCompare(needle) == .orderedSame
        case .startsWith:
            return haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
        default: return false
        }
    }

    static func matchStatus(_ status: Status, op: Op, value: Value) -> Bool {
        guard case .statusSet(let set) = value else { return false }
        switch op {
        case .is: return set.contains(status)
        case .isNot: return !set.contains(status)
        default: return false
        }
    }

    static func matchBool(_ actual: Bool, op: Op, value: Value) -> Bool {
        guard case .bool(let target) = value, op == .is else { return false }
        return actual == target
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `cd Packages/LillistCore && swift test --filter SwiftEvaluatorTests`
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Rules/SwiftEvaluatorTests.swift
git commit -m "feat: add SwiftEvaluator with TaskSnapshot and scalar/string/status leaves"
```

---

## Task 14: `SwiftEvaluator` — date leaves

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift`
- Modify: `Packages/LillistCore/Tests/LillistCoreTests/Rules/SwiftEvaluatorTests.swift`

- [ ] **Step 1: Append failing date tests**

Append to `Packages/LillistCore/Tests/LillistCoreTests/Rules/SwiftEvaluatorTests.swift`:

```swift
@Suite("SwiftEvaluator — date slice")
struct SwiftEvaluatorDateTests {
    static let now = Date(timeIntervalSince1970: 1_715_500_000)
    static var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func snap(deadline: Date? = nil, start: Date? = nil, created: Date = now, modified: Date = now, closed: Date? = nil) -> SwiftEvaluator.TaskSnapshot {
        SwiftEvaluator.TaskSnapshot(
            id: UUID(), title: "t", notes: "",
            status: .todo,
            start: start, startHasTime: false,
            deadline: deadline, deadlineHasTime: false,
            createdAt: created, modifiedAt: modified, closedAt: closed,
            isPinned: false, inTrash: false,
            hasChildren: false, childCount: 0,
            tagIDs: [], ancestorIDs: [],
            journalNoteBodies: [], attachmentKinds: [],
            hasNudges: false, isRecurring: false
        )
    }

    @Test("deadline before absoluteDate")
    func before() {
        let cutoff = SwiftEvaluatorDateTests.now.addingTimeInterval(60)
        let before = SwiftEvaluatorDateTests.now.addingTimeInterval(-60)
        let after = SwiftEvaluatorDateTests.now.addingTimeInterval(120)
        let g = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .deadline, op: .before, value: .absoluteDate(cutoff)))
        ])
        #expect(SwiftEvaluator.evaluate(group: g, against: snap(deadline: before), now: SwiftEvaluatorDateTests.now, calendar: SwiftEvaluatorDateTests.cal) == true)
        #expect(SwiftEvaluator.evaluate(group: g, against: snap(deadline: after), now: SwiftEvaluatorDateTests.now, calendar: SwiftEvaluatorDateTests.cal) == false)
    }

    @Test("deadline withinNextDays(7)")
    func withinNext() {
        let inThree = SwiftEvaluatorDateTests.cal.date(byAdding: .day, value: 3, to: SwiftEvaluatorDateTests.now)!
        let inTen = SwiftEvaluatorDateTests.cal.date(byAdding: .day, value: 10, to: SwiftEvaluatorDateTests.now)!
        let g = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .deadline, op: .withinNextDays, value: .dayCount(7)))
        ])
        #expect(SwiftEvaluator.evaluate(group: g, against: snap(deadline: inThree), now: SwiftEvaluatorDateTests.now, calendar: SwiftEvaluatorDateTests.cal) == true)
        #expect(SwiftEvaluator.evaluate(group: g, against: snap(deadline: inTen), now: SwiftEvaluatorDateTests.now, calendar: SwiftEvaluatorDateTests.cal) == false)
    }

    @Test("deadline isSet vs isUnset")
    func isSet() {
        let setG = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .deadline, op: .isSet, value: .bool(true)))
        ])
        let unsetG = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .deadline, op: .isUnset, value: .bool(true)))
        ])
        #expect(SwiftEvaluator.evaluate(group: setG, against: snap(deadline: Date())) == true)
        #expect(SwiftEvaluator.evaluate(group: setG, against: snap(deadline: nil)) == false)
        #expect(SwiftEvaluator.evaluate(group: unsetG, against: snap(deadline: nil)) == true)
    }

    @Test("createdAt equalsModifiedAt")
    func createdEqualsModified() {
        let t = Date(timeIntervalSince1970: 1_000_000)
        let g = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .createdAt, op: .equalsModifiedAt, value: .bool(true)))
        ])
        #expect(SwiftEvaluator.evaluate(group: g, against: snap(created: t, modified: t)) == true)
        #expect(SwiftEvaluator.evaluate(group: g, against: snap(created: t, modified: t.addingTimeInterval(1))) == false)
    }

    @Test("start withinNextDays resolves relative to provided now")
    func relativeToNow() {
        let t = SwiftEvaluatorDateTests.cal.date(byAdding: .day, value: 2, to: SwiftEvaluatorDateTests.now)!
        let g = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .start, op: .withinNextDays, value: .dayCount(5)))
        ])
        #expect(SwiftEvaluator.evaluate(group: g, against: snap(start: t), now: SwiftEvaluatorDateTests.now, calendar: SwiftEvaluatorDateTests.cal) == true)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/LillistCore && swift test --filter SwiftEvaluatorDateTests`
Expected: FAIL — date dispatch returns `false`.

- [ ] **Step 3: Extend the evaluator**

Edit `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift`. Replace the leaf-dispatch `default:` branch with explicit date handling and add a date matcher:

Update `evaluateLeaf` to add cases for `.start`, `.deadline`, `.createdAt`, `.modifiedAt`, `.closedAt`:

```swift
        case .start: return matchDate(s.start, otherDate: nil, op: leaf.op, value: leaf.value, now: now, calendar: calendar)
        case .deadline: return matchDate(s.deadline, otherDate: nil, op: leaf.op, value: leaf.value, now: now, calendar: calendar)
        case .createdAt: return matchDate(s.createdAt, otherDate: s.modifiedAt, op: leaf.op, value: leaf.value, now: now, calendar: calendar)
        case .modifiedAt: return matchDate(s.modifiedAt, otherDate: nil, op: leaf.op, value: leaf.value, now: now, calendar: calendar)
        case .closedAt: return matchDate(s.closedAt, otherDate: nil, op: leaf.op, value: leaf.value, now: now, calendar: calendar)
```

And add the helper:

```swift
    static func matchDate(
        _ date: Date?,
        otherDate: Date?,
        op: Op,
        value: Value,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        switch op {
        case .isSet: return date != nil
        case .isUnset: return date == nil
        case .equalsModifiedAt:
            guard let a = date, let b = otherDate else { return false }
            return a == b
        case .before, .after, .on:
            guard let actual = date,
                  let target = resolveAbsolute(value, now: now, calendar: calendar) else {
                return false
            }
            switch op {
            case .before: return actual < target
            case .after: return actual > target
            case .on:
                let startOfDay = calendar.startOfDay(for: target)
                let endOfDay = RelativeDateResolver.endOfDay(for: startOfDay, calendar: calendar)
                return actual >= startOfDay && actual <= endOfDay
            default: return false
            }
        case .withinLastDays:
            guard let actual = date, case .dayCount(let n) = value else { return false }
            let startOfToday = calendar.startOfDay(for: now)
            let cutoff = calendar.date(byAdding: .day, value: -n, to: startOfToday) ?? startOfToday
            return actual >= cutoff && actual <= now
        case .withinNextDays:
            guard let actual = date, case .dayCount(let n) = value else { return false }
            let startOfToday = calendar.startOfDay(for: now)
            let horizon = calendar.date(byAdding: .day, value: n, to: startOfToday) ?? startOfToday
            let horizonEnd = RelativeDateResolver.endOfDay(for: horizon, calendar: calendar)
            return actual >= now && actual <= horizonEnd
        default: return false
        }
    }

    static func resolveAbsolute(_ value: Value, now: Date, calendar: Calendar) -> Date? {
        switch value {
        case .absoluteDate(let d): return d
        case .relativeDate(let r): return RelativeDateResolver.resolve(r, now: now, calendar: calendar)
        default: return nil
        }
    }
```

- [ ] **Step 4: Run tests to verify pass**

Run: `cd Packages/LillistCore && swift test --filter SwiftEvaluator`
Expected: all SwiftEvaluator suites pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Rules/SwiftEvaluatorTests.swift
git commit -m "feat: extend SwiftEvaluator with date leaf evaluation"
```

---

## Task 15: `SwiftEvaluator` — relational leaves (`tag.*`, `ancestor.*`, `journalText`, `hasAttachments`)

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift`
- Modify: `Packages/LillistCore/Tests/LillistCoreTests/Rules/SwiftEvaluatorTests.swift`

- [ ] **Step 1: Append failing tests**

Append to `Packages/LillistCore/Tests/LillistCoreTests/Rules/SwiftEvaluatorTests.swift`:

```swift
@Suite("SwiftEvaluator — relational slice")
struct SwiftEvaluatorRelationalTests {
    private func snap(
        tagIDs: Set<UUID> = [],
        ancestorIDs: Set<UUID> = [],
        journalNoteBodies: [String] = [],
        attachmentKinds: [AttachmentKind] = []
    ) -> SwiftEvaluator.TaskSnapshot {
        SwiftEvaluator.TaskSnapshot(
            id: UUID(), title: "t", notes: "", status: .todo,
            start: nil, startHasTime: false,
            deadline: nil, deadlineHasTime: false,
            createdAt: Date(), modifiedAt: Date(), closedAt: nil,
            isPinned: false, inTrash: false,
            hasChildren: false, childCount: 0,
            tagIDs: tagIDs, ancestorIDs: ancestorIDs,
            journalNoteBodies: journalNoteBodies, attachmentKinds: attachmentKinds,
            hasNudges: false, isRecurring: false
        )
    }

    @Test("tag includesAny")
    func tagIncludesAny() {
        let a = UUID(); let b = UUID(); let c = UUID()
        let g = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .tag, op: .includesAny, value: .uuidSet([a, b])))
        ])
        #expect(SwiftEvaluator.evaluate(group: g, against: snap(tagIDs: [a])) == true)
        #expect(SwiftEvaluator.evaluate(group: g, against: snap(tagIDs: [c])) == false)
    }

    @Test("tag includesAll")
    func tagIncludesAll() {
        let a = UUID(); let b = UUID()
        let g = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .tag, op: .includesAll, value: .uuidSet([a, b])))
        ])
        #expect(SwiftEvaluator.evaluate(group: g, against: snap(tagIDs: [a, b])) == true)
        #expect(SwiftEvaluator.evaluate(group: g, against: snap(tagIDs: [a])) == false)
    }

    @Test("tag excludesAll")
    func tagExcludesAll() {
        let a = UUID(); let b = UUID()
        let g = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .tag, op: .excludesAll, value: .uuidSet([a, b])))
        ])
        #expect(SwiftEvaluator.evaluate(group: g, against: snap(tagIDs: [])) == true)
        #expect(SwiftEvaluator.evaluate(group: g, against: snap(tagIDs: [a])) == false)
    }

    @Test("ancestor isDescendantOf")
    func descendantOf() {
        let root = UUID()
        let other = UUID()
        let g = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .ancestor, op: .isDescendantOf, value: .uuidSet([root])))
        ])
        #expect(SwiftEvaluator.evaluate(group: g, against: snap(ancestorIDs: [root])) == true)
        #expect(SwiftEvaluator.evaluate(group: g, against: snap(ancestorIDs: [other])) == false)
    }

    @Test("journalText contains")
    func journalText() {
        let g = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .journalText, op: .contains, value: .string("blocker")))
        ])
        #expect(SwiftEvaluator.evaluate(group: g, against: snap(journalNoteBodies: ["fixed blocker today"])) == true)
        #expect(SwiftEvaluator.evaluate(group: g, against: snap(journalNoteBodies: ["all good"])) == false)
    }

    @Test("hasAttachments any vs of kind")
    func hasAttachments() {
        let any = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .hasAttachments, op: .is, value: .attachmentKind(.init(present: true))))
        ])
        let image = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .hasAttachments, op: .is, value: .attachmentKind(.init(present: true, kind: .image))))
        ])
        #expect(SwiftEvaluator.evaluate(group: any, against: snap(attachmentKinds: [.file])) == true)
        #expect(SwiftEvaluator.evaluate(group: any, against: snap(attachmentKinds: [])) == false)
        #expect(SwiftEvaluator.evaluate(group: image, against: snap(attachmentKinds: [.file])) == false)
        #expect(SwiftEvaluator.evaluate(group: image, against: snap(attachmentKinds: [.file, .image])) == true)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/LillistCore && swift test --filter SwiftEvaluatorRelationalTests`
Expected: FAIL — relational dispatch returns `false`.

- [ ] **Step 3: Extend the evaluator**

In `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift`, add cases to `evaluateLeaf` for `.tag`, `.ancestor`, `.journalText`, `.hasAttachments`:

```swift
        case .tag: return matchTag(s.tagIDs, op: leaf.op, value: leaf.value)
        case .ancestor: return matchAncestor(s.ancestorIDs, op: leaf.op, value: leaf.value)
        case .journalText: return matchJournalText(s.journalNoteBodies, op: leaf.op, value: leaf.value)
        case .hasAttachments: return matchHasAttachments(s.attachmentKinds, op: leaf.op, value: leaf.value)
```

Append the helpers:

```swift
    static func matchTag(_ tagIDs: Set<UUID>, op: Op, value: Value) -> Bool {
        guard case .uuidSet(let ids) = value else { return false }
        switch op {
        case .includesAny: return !tagIDs.isDisjoint(with: ids)
        case .includesAll: return ids.isSubset(of: tagIDs)
        case .excludesAll: return tagIDs.isDisjoint(with: ids)
        default: return false
        }
    }

    static func matchAncestor(_ ancestorIDs: Set<UUID>, op: Op, value: Value) -> Bool {
        guard case .uuidSet(let ids) = value else { return false }
        switch op {
        case .isDescendantOf: return !ancestorIDs.isDisjoint(with: ids)
        case .isAncestorOf:
            // Symmetry: a snapshot of an ancestor task has the descendant ids
            // in `ancestorIDs`? No — `isAncestorOf` asks "is THIS task an
            // ancestor of any of the given ids?" That requires the caller
            // to supply descendant-id reachability; not represented in the
            // snapshot today. Return false; the parity suite excludes this
            // op for SwiftEvaluator until a snapshot extension is added.
            return false
        default: return false
        }
    }

    static func matchJournalText(_ bodies: [String], op: Op, value: Value) -> Bool {
        guard op == .contains, case .string(let needle) = value else { return false }
        return bodies.contains { $0.localizedStandardContains(needle) }
    }

    static func matchHasAttachments(_ kinds: [AttachmentKind], op: Op, value: Value) -> Bool {
        guard op == .is, case .attachmentKind(let match) = value else { return false }
        let pool: [AttachmentKind]
        if let kindFilter = match.kind {
            pool = kinds.filter { $0 == kindFilter }
        } else {
            pool = kinds
        }
        return match.present ? !pool.isEmpty : pool.isEmpty
    }
```

- [ ] **Step 4: Run tests to verify pass**

Run: `cd Packages/LillistCore && swift test --filter SwiftEvaluator`
Expected: all SwiftEvaluator suites pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Rules/SwiftEvaluatorTests.swift
git commit -m "feat: extend SwiftEvaluator with tag/ancestor/journalText/hasAttachments matchers"
```

---

## Task 16: Snapshot builder from `LillistTask` managed object

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift`

To make `SwiftEvaluator` usable from both the parity suite and (later) `SmartFilter.evaluate(persistence:)`, we add a convenience initializer that takes an `LillistTask` and builds a `TaskSnapshot`. Must be called inside the owning context's `perform` block.

- [ ] **Step 1: Add a focused test**

Append to `Packages/LillistCore/Tests/LillistCoreTests/Rules/SwiftEvaluatorTests.swift`:

```swift
@Suite("SwiftEvaluator.TaskSnapshot.from(managedObject:)")
struct SwiftEvaluatorSnapshotBuilderTests {
    @Test("Snapshot reflects every interesting attribute of the managed object")
    func builderRoundTrips() async throws {
        let controller = try await TestStore.make()
        let ctx = controller.container.viewContext
        let id = UUID()
        let parentID = UUID()
        try await ctx.perform {
            let parent = LillistTask(context: ctx)
            parent.id = parentID
            parent.title = "Parent"
            parent.notes = ""
            parent.status = .todo
            parent.createdAt = Date(); parent.modifiedAt = Date()

            let child = LillistTask(context: ctx)
            child.id = id
            child.title = "Child"
            child.notes = "n"
            child.status = .started
            child.isPinned = true
            child.createdAt = Date(); child.modifiedAt = Date()
            child.parent = parent

            let tag = Tag(context: ctx)
            tag.id = UUID(); tag.name = "work"; tag.tintColor = "#888888"
            child.addToTags(tag)

            let j = JournalEntry(context: ctx)
            j.id = UUID(); j.kind = .note; j.body = "note body"
            j.createdAt = Date()
            j.task = child

            let att = Attachment(context: ctx)
            att.id = UUID(); att.kind = .image
            att.filename = "f"; att.uti = "public.image"
            att.byteSize = 0
            att.task = child
            att.journalEntry = j

            try ctx.save()
        }

        let snap = try await ctx.perform { () throws -> SwiftEvaluator.TaskSnapshot in
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            let m = try ctx.fetch(req).first!
            return SwiftEvaluator.TaskSnapshot.from(managedObject: m)
        }

        #expect(snap.title == "Child")
        #expect(snap.status == .started)
        #expect(snap.isPinned == true)
        #expect(snap.ancestorIDs.contains(parentID))
        #expect(snap.tagIDs.count == 1)
        #expect(snap.journalNoteBodies == ["note body"])
        #expect(snap.attachmentKinds == [.image])
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/LillistCore && swift test --filter SwiftEvaluatorSnapshotBuilderTests`
Expected: FAIL — `TaskSnapshot.from(managedObject:)` undefined.

- [ ] **Step 3: Implement the builder**

Append to `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift`:

```swift
import CoreData

extension SwiftEvaluator.TaskSnapshot {
    /// Build a snapshot from a fetched `LillistTask`. Caller must invoke
    /// inside the managed object's context (via `context.perform`) to
    /// safely touch relationships.
    public static func from(managedObject m: LillistTask) -> SwiftEvaluator.TaskSnapshot {
        // Tag ids
        let tagIDs: Set<UUID> = {
            guard let tags = m.tags as? Set<Tag> else { return [] }
            return Set(tags.compactMap { $0.id })
        }()
        // Ancestor chain (depth-bounded at 32 to match the compiler's safe ceiling)
        var ancestorIDs: Set<UUID> = []
        var cursor: LillistTask? = m.parent
        var depth = 0
        while let p = cursor, depth < 32 {
            if let pid = p.id { ancestorIDs.insert(pid) }
            cursor = p.parent
            depth += 1
        }
        // Journal note bodies
        let noteBodies: [String] = {
            guard let entries = m.journalEntries as? Set<JournalEntry> else { return [] }
            return entries
                .filter { $0.kind == .note }
                .compactMap { $0.body }
        }()
        // Attachment kinds
        let kinds: [AttachmentKind] = {
            guard let attachments = m.attachments as? Set<Attachment> else { return [] }
            return attachments.map { $0.kind }
        }()
        let childCount: Int = (m.children as? Set<LillistTask>)?.count ?? 0
        return SwiftEvaluator.TaskSnapshot(
            id: m.id ?? UUID(),
            title: m.title ?? "",
            notes: m.notes ?? "",
            status: m.status,
            start: m.start, startHasTime: m.startHasTime,
            deadline: m.deadline, deadlineHasTime: m.deadlineHasTime,
            createdAt: m.createdAt ?? Date(),
            modifiedAt: m.modifiedAt ?? Date(),
            closedAt: m.closedAt,
            isPinned: m.isPinned,
            inTrash: m.deletedAt != nil,
            hasChildren: childCount > 0,
            childCount: childCount,
            tagIDs: tagIDs,
            ancestorIDs: ancestorIDs,
            journalNoteBodies: noteBodies,
            attachmentKinds: kinds,
            hasNudges: false,     // Plan 4
            isRecurring: false    // Plan 5
        )
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `cd Packages/LillistCore && swift test --filter SwiftEvaluatorSnapshotBuilderTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Rules/SwiftEvaluatorTests.swift
git commit -m "feat: add SwiftEvaluator.TaskSnapshot builder from LillistTask managed object"
```

---

## Task 17: Parity fixture set (~30 cases)

**Files:**
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Rules/ParityFixtures.swift`

The fixture suite is the regression backbone per design Sections 5 and 9. Each fixture is a `(name, PredicateGroup, [seed tasks], expected matching ids)` tuple. Tasks 18 and 19 run each fixture through both evaluation paths and fail on divergence.

- [ ] **Step 1: Write the fixture file**

Write `Packages/LillistCore/Tests/LillistCoreTests/Rules/ParityFixtures.swift`:

```swift
import Foundation
@testable import LillistCore

/// One parity fixture. Seed each task with a stable id so expectations are
/// deterministic; expected ids are the ones that should pass the predicate.
struct ParityFixture: Sendable {
    let name: String
    let group: PredicateGroup
    let seeds: [SeedTask]
    let expected: Set<UUID>
}

/// A serializable description of a task to seed before running a fixture.
/// Mirrors `LillistTask`'s queryable fields plus a few relational fan-outs.
struct SeedTask: Sendable {
    var id: UUID = UUID()
    var title: String = "task"
    var notes: String = ""
    var status: Status = .todo
    var start: Date? = nil
    var deadline: Date? = nil
    var createdAt: Date = ParityFixtures.now
    var modifiedAt: Date = ParityFixtures.now
    var closedAt: Date? = nil
    var deletedAt: Date? = nil
    var isPinned: Bool = false
    var parentID: UUID? = nil
    var tagIDs: [UUID] = []
    var journalNoteBodies: [String] = []
    var attachmentKinds: [AttachmentKind] = []
}

enum ParityFixtures {
    /// Fixed "now" for relative-date fixtures: 2026-05-12 12:00 UTC.
    static let now: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 12
        c.hour = 12; c.minute = 0
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }()

    static var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 1
        return c
    }()

    static func days(_ n: Int, from date: Date = now) -> Date {
        calendar.date(byAdding: .day, value: n, to: date)!
    }

    // Deterministic id pool for predictable expectations.
    static let id1 = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let id2 = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let id3 = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    static let id4 = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    static let id5 = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!

    static let tagWork = UUID(uuidString: "00000000-0000-0000-0001-000000000001")!
    static let tagHome = UUID(uuidString: "00000000-0000-0000-0001-000000000002")!
    static let tagUrgent = UUID(uuidString: "00000000-0000-0000-0001-000000000003")!

    static let parentA = UUID(uuidString: "00000000-0000-0000-0002-000000000001")!

    static let all: [ParityFixture] = [
        // 1. title contains
        ParityFixture(
            name: "title contains 'design'",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .title, op: .contains, value: .string("design")))
            ]),
            seeds: [
                SeedTask(id: id1, title: "Design review"),
                SeedTask(id: id2, title: "Write spec")
            ],
            expected: [id1]
        ),
        // 2. title contains is case-insensitive
        ParityFixture(
            name: "title contains 'DESIGN' case-insensitive",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .title, op: .contains, value: .string("DESIGN")))
            ]),
            seeds: [
                SeedTask(id: id1, title: "design review"),
                SeedTask(id: id2, title: "spec")
            ],
            expected: [id1]
        ),
        // 3. title startsWith
        ParityFixture(
            name: "title startsWith 'Re'",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .title, op: .startsWith, value: .string("Re")))
            ]),
            seeds: [
                SeedTask(id: id1, title: "Refactor module"),
                SeedTask(id: id2, title: "Read mail"),
                SeedTask(id: id3, title: "Cleanup")
            ],
            expected: [id1, id2]
        ),
        // 4. notes contains
        ParityFixture(
            name: "notes contains 'sketch'",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .notes, op: .contains, value: .string("sketch")))
            ]),
            seeds: [
                SeedTask(id: id1, notes: "rough sketch attached"),
                SeedTask(id: id2, notes: "no doodles")
            ],
            expected: [id1]
        ),
        // 5. status is {todo, started}
        ParityFixture(
            name: "status is {todo, started}",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .status, op: .is, value: .statusSet([.todo, .started])))
            ]),
            seeds: [
                SeedTask(id: id1, status: .todo),
                SeedTask(id: id2, status: .started),
                SeedTask(id: id3, status: .blocked),
                SeedTask(id: id4, status: .closed)
            ],
            expected: [id1, id2]
        ),
        // 6. status isNot {closed}
        ParityFixture(
            name: "status isNot {closed}",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .status, op: .isNot, value: .statusSet([.closed])))
            ]),
            seeds: [
                SeedTask(id: id1, status: .todo),
                SeedTask(id: id2, status: .closed)
            ],
            expected: [id1]
        ),
        // 7. isPinned is true
        ParityFixture(
            name: "isPinned is true",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .isPinned, op: .is, value: .bool(true)))
            ]),
            seeds: [
                SeedTask(id: id1, isPinned: true),
                SeedTask(id: id2, isPinned: false)
            ],
            expected: [id1]
        ),
        // 8. deadline before today
        ParityFixture(
            name: "deadline before today",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .deadline, op: .before, value: .relativeDate(.today)))
            ]),
            seeds: [
                SeedTask(id: id1, deadline: days(-1)),
                SeedTask(id: id2, deadline: days(1))
            ],
            expected: [id1]
        ),
        // 9. deadline withinNextDays(7)
        ParityFixture(
            name: "deadline withinNextDays(7)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .deadline, op: .withinNextDays, value: .dayCount(7)))
            ]),
            seeds: [
                SeedTask(id: id1, deadline: days(3)),
                SeedTask(id: id2, deadline: days(10)),
                SeedTask(id: id3, deadline: nil)
            ],
            expected: [id1]
        ),
        // 10. start withinLastDays(3)
        ParityFixture(
            name: "start withinLastDays(3)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .start, op: .withinLastDays, value: .dayCount(3)))
            ]),
            seeds: [
                SeedTask(id: id1, start: days(-1)),
                SeedTask(id: id2, start: days(-5))
            ],
            expected: [id1]
        ),
        // 11. deadline isSet
        ParityFixture(
            name: "deadline isSet",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .deadline, op: .isSet, value: .bool(true)))
            ]),
            seeds: [
                SeedTask(id: id1, deadline: days(1)),
                SeedTask(id: id2, deadline: nil)
            ],
            expected: [id1]
        ),
        // 12. deadline isUnset
        ParityFixture(
            name: "deadline isUnset",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .deadline, op: .isUnset, value: .bool(true)))
            ]),
            seeds: [
                SeedTask(id: id1, deadline: days(1)),
                SeedTask(id: id2, deadline: nil)
            ],
            expected: [id2]
        ),
        // 13. createdAt equalsModifiedAt
        ParityFixture(
            name: "createdAt equalsModifiedAt (stale)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .createdAt, op: .equalsModifiedAt, value: .bool(true)))
            ]),
            seeds: [
                SeedTask(id: id1, createdAt: now, modifiedAt: now),
                SeedTask(id: id2, createdAt: now, modifiedAt: days(0, from: now).addingTimeInterval(60))
            ],
            expected: [id1]
        ),
        // 14. closedAt withinLastDays(7) (Recently Closed)
        ParityFixture(
            name: "closedAt withinLastDays(7)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .closedAt, op: .withinLastDays, value: .dayCount(7)))
            ]),
            seeds: [
                SeedTask(id: id1, status: .closed, closedAt: days(-2)),
                SeedTask(id: id2, status: .closed, closedAt: days(-20))
            ],
            expected: [id1]
        ),
        // 15. tag includesAny {work, home}
        ParityFixture(
            name: "tag includesAny {work, home}",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .tag, op: .includesAny, value: .uuidSet([tagWork, tagHome])))
            ]),
            seeds: [
                SeedTask(id: id1, tagIDs: [tagWork]),
                SeedTask(id: id2, tagIDs: [tagHome]),
                SeedTask(id: id3, tagIDs: [tagUrgent])
            ],
            expected: [id1, id2]
        ),
        // 16. tag includesAll {work, urgent}
        ParityFixture(
            name: "tag includesAll {work, urgent}",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .tag, op: .includesAll, value: .uuidSet([tagWork, tagUrgent])))
            ]),
            seeds: [
                SeedTask(id: id1, tagIDs: [tagWork, tagUrgent]),
                SeedTask(id: id2, tagIDs: [tagWork]),
                SeedTask(id: id3, tagIDs: [tagWork, tagHome, tagUrgent])
            ],
            expected: [id1, id3]
        ),
        // 17. tag excludesAll {work}
        ParityFixture(
            name: "tag excludesAll {work}",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .tag, op: .excludesAll, value: .uuidSet([tagWork])))
            ]),
            seeds: [
                SeedTask(id: id1, tagIDs: [tagHome]),
                SeedTask(id: id2, tagIDs: [tagWork]),
                SeedTask(id: id3, tagIDs: [])
            ],
            expected: [id1, id3]
        ),
        // 18. ancestor isDescendantOf {parentA}
        ParityFixture(
            name: "ancestor isDescendantOf {parentA}",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .ancestor, op: .isDescendantOf, value: .uuidSet([parentA])))
            ]),
            seeds: [
                SeedTask(id: parentA, title: "Parent"),
                SeedTask(id: id1, parentID: parentA),
                SeedTask(id: id2, parentID: nil)
            ],
            expected: [id1]
        ),
        // 19. journalText contains
        ParityFixture(
            name: "journalText contains 'blocker'",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .journalText, op: .contains, value: .string("blocker")))
            ]),
            seeds: [
                SeedTask(id: id1, journalNoteBodies: ["external blocker"]),
                SeedTask(id: id2, journalNoteBodies: ["all good"]),
                SeedTask(id: id3)
            ],
            expected: [id1]
        ),
        // 20. hasAttachments any
        ParityFixture(
            name: "hasAttachments is true (any kind)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .hasAttachments, op: .is,
                            value: .attachmentKind(.init(present: true))))
            ]),
            seeds: [
                SeedTask(id: id1, attachmentKinds: [.file]),
                SeedTask(id: id2, attachmentKinds: [])
            ],
            expected: [id1]
        ),
        // 21. hasAttachments ofKind=image
        ParityFixture(
            name: "hasAttachments image",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .hasAttachments, op: .is,
                            value: .attachmentKind(.init(present: true, kind: .image))))
            ]),
            seeds: [
                SeedTask(id: id1, attachmentKinds: [.image, .file]),
                SeedTask(id: id2, attachmentKinds: [.file])
            ],
            expected: [id1]
        ),
        // 22. hasChildren is true
        ParityFixture(
            name: "hasChildren is true",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .hasChildren, op: .is, value: .bool(true)))
            ]),
            seeds: [
                SeedTask(id: parentA, title: "Parent"),
                SeedTask(id: id1, parentID: parentA),
                SeedTask(id: id2, title: "Leaf")
            ],
            expected: [parentA]
        ),
        // 23. inTrash explicit true
        ParityFixture(
            name: "inTrash is true (explicit)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .inTrash, op: .is, value: .bool(true)))
            ]),
            seeds: [
                SeedTask(id: id1, deletedAt: nil),
                SeedTask(id: id2, deletedAt: now)
            ],
            expected: [id2]
        ),
        // 24. Implicit inTrash filter excludes deleted
        ParityFixture(
            name: "implicit inTrash filter excludes deleted",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .title, op: .contains, value: .string("a")))
            ]),
            seeds: [
                SeedTask(id: id1, title: "alpha", deletedAt: nil),
                SeedTask(id: id2, title: "apple", deletedAt: now)
            ],
            expected: [id1]
        ),
        // 25. Combinator .all
        ParityFixture(
            name: "all of: status=todo AND deadline isSet",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .status, op: .is, value: .statusSet([.todo]))),
                .leaf(.init(field: .deadline, op: .isSet, value: .bool(true)))
            ]),
            seeds: [
                SeedTask(id: id1, status: .todo, deadline: days(1)),
                SeedTask(id: id2, status: .todo, deadline: nil),
                SeedTask(id: id3, status: .closed, deadline: days(1))
            ],
            expected: [id1]
        ),
        // 26. Combinator .any
        ParityFixture(
            name: "any of: pinned OR deadline within next 3 days",
            group: .init(combinator: .any, predicates: [
                .leaf(.init(field: .isPinned, op: .is, value: .bool(true))),
                .leaf(.init(field: .deadline, op: .withinNextDays, value: .dayCount(3)))
            ]),
            seeds: [
                SeedTask(id: id1, deadline: days(1)),
                SeedTask(id: id2, isPinned: true),
                SeedTask(id: id3, isPinned: false, deadline: days(10))
            ],
            expected: [id1, id2]
        ),
        // 27. Nested group: status=started AND (tag=work OR tag=urgent)
        ParityFixture(
            name: "nested: started AND (work OR urgent)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .status, op: .is, value: .statusSet([.started]))),
                .group(.init(combinator: .any, predicates: [
                    .leaf(.init(field: .tag, op: .includesAny, value: .uuidSet([tagWork]))),
                    .leaf(.init(field: .tag, op: .includesAny, value: .uuidSet([tagUrgent])))
                ]))
            ]),
            seeds: [
                SeedTask(id: id1, status: .started, tagIDs: [tagWork]),
                SeedTask(id: id2, status: .todo, tagIDs: [tagWork]),
                SeedTask(id: id3, status: .started, tagIDs: [tagHome])
            ],
            expected: [id1]
        ),
        // 28. Empty predicate group matches everything non-trashed
        ParityFixture(
            name: "empty group matches all non-trashed",
            group: .init(combinator: .all, predicates: []),
            seeds: [
                SeedTask(id: id1),
                SeedTask(id: id2, deletedAt: now)
            ],
            expected: [id1]
        ),
        // 29. title contains diacritic-insensitive
        ParityFixture(
            name: "title contains 'cafe' matches 'café'",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .title, op: .contains, value: .string("cafe")))
            ]),
            seeds: [
                SeedTask(id: id1, title: "Visit café"),
                SeedTask(id: id2, title: "Visit park")
            ],
            expected: [id1]
        ),
        // 30. createdAt after a fixed absolute date
        ParityFixture(
            name: "createdAt after fixed absolute date",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .createdAt, op: .after, value: .absoluteDate(ParityFixtures.days(-2))))
            ]),
            seeds: [
                SeedTask(id: id1, createdAt: now),
                SeedTask(id: id2, createdAt: days(-5))
            ],
            expected: [id1]
        )
    ]
}
```

- [ ] **Step 2: Verify the file builds**

Run: `cd Packages/LillistCore && swift build`
Expected: build succeeds. No tests yet — the runner is Task 18.

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistCore/Tests/LillistCoreTests/Rules/ParityFixtures.swift
git commit -m "test: add 30-fixture parity set covering every field-operator combination"
```

---

## Task 18: Parity suite — run every fixture through both evaluation paths

**Files:**
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Rules/ParitySuiteTests.swift`

Each fixture is materialized into Core Data (so the `NSPredicateCompiler` path can fetch through `NSPredicate`) and also into in-memory `TaskSnapshot`s for the `SwiftEvaluator` path. The two result sets must equal each other AND equal the fixture's `expected` set. Any divergence fails loudly with the fixture name.

- [ ] **Step 1: Write the suite**

Write `Packages/LillistCore/Tests/LillistCoreTests/Rules/ParitySuiteTests.swift`:

```swift
import Testing
import Foundation
import CoreData
@testable import LillistCore

@Suite("Parity: NSPredicate vs SwiftEvaluator over the fixture set")
struct ParitySuiteTests {
    @Test("Every fixture matches expected set in both evaluators",
          arguments: ParityFixtures.all)
    func parity(_ fixture: ParityFixture) async throws {
        // --- NSPredicate path ---
        let controller = try await TestStore.make()
        let ctx = controller.container.viewContext
        try await ctx.perform {
            // First pass: seed every task (parents must exist for child wiring).
            var byID: [UUID: LillistTask] = [:]
            for seed in fixture.seeds {
                let t = LillistTask(context: ctx)
                t.id = seed.id
                t.title = seed.title
                t.notes = seed.notes
                t.status = seed.status
                t.start = seed.start
                t.deadline = seed.deadline
                t.createdAt = seed.createdAt
                t.modifiedAt = seed.modifiedAt
                t.closedAt = seed.closedAt
                t.deletedAt = seed.deletedAt
                t.isPinned = seed.isPinned
                byID[seed.id] = t
            }
            // Second pass: wire parent links.
            for seed in fixture.seeds {
                if let pid = seed.parentID, let p = byID[pid] {
                    byID[seed.id]?.parent = p
                }
            }
            // Tags
            var tagsByID: [UUID: Tag] = [:]
            for seed in fixture.seeds {
                for tid in seed.tagIDs {
                    if tagsByID[tid] == nil {
                        let tag = Tag(context: ctx)
                        tag.id = tid
                        tag.name = "tag-\(tid.uuidString.prefix(4))"
                        tag.tintColor = "#888888"
                        tagsByID[tid] = tag
                    }
                    if let t = byID[seed.id] {
                        t.addToTags(tagsByID[tid]!)
                    }
                }
            }
            // Journal note entries
            for seed in fixture.seeds {
                for body in seed.journalNoteBodies {
                    let j = JournalEntry(context: ctx)
                    j.id = UUID()
                    j.kind = .note
                    j.body = body
                    j.createdAt = Date()
                    j.task = byID[seed.id]
                }
            }
            // Attachments
            for seed in fixture.seeds {
                for kind in seed.attachmentKinds {
                    let a = Attachment(context: ctx)
                    a.id = UUID()
                    a.kind = kind
                    a.filename = "f"
                    a.uti = "public.data"
                    a.byteSize = 0
                    a.task = byID[seed.id]
                }
            }
            try ctx.save()
        }

        let nsResults: Set<UUID> = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicateCompiler.compile(
                fixture.group,
                now: ParityFixtures.now,
                calendar: ParityFixtures.calendar
            )
            let tasks = try ctx.fetch(req)
            return Set(tasks.compactMap { $0.id })
        }

        // --- SwiftEvaluator path ---
        let swiftResults: Set<UUID> = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            let all = try ctx.fetch(req)
            var out: Set<UUID> = []
            for m in all {
                let snap = SwiftEvaluator.TaskSnapshot.from(managedObject: m)
                if SwiftEvaluator.evaluate(
                    group: fixture.group,
                    against: snap,
                    now: ParityFixtures.now,
                    calendar: ParityFixtures.calendar
                ) {
                    if let id = m.id { out.insert(id) }
                }
            }
            return out
        }

        // --- Assertions ---
        #expect(nsResults == fixture.expected, "[\(fixture.name)] NSPredicate path mismatch: got \(nsResults), expected \(fixture.expected)")
        #expect(swiftResults == fixture.expected, "[\(fixture.name)] SwiftEvaluator path mismatch: got \(swiftResults), expected \(fixture.expected)")
        #expect(nsResults == swiftResults, "[\(fixture.name)] paths diverged: NSPredicate=\(nsResults), Swift=\(swiftResults)")
    }
}
```

- [ ] **Step 2: Run the parity suite**

Run: `cd Packages/LillistCore && swift test --filter ParitySuiteTests`
Expected: PASS, 30 parameterized cases. If any fail, the failure message names the fixture and which path diverged — fix and rerun before moving on.

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistCore/Tests/LillistCoreTests/Rules/ParitySuiteTests.swift
git commit -m "test: add parity suite running every fixture through both evaluation paths"
```

---

## Task 19: Property-based relative-date parity test

**Files:**
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Rules/RelativeDateParityTests.swift`

For any `N` in a representative range, "deadline withinNextDays N" against absolute-date seeds must produce the same matching ids under both evaluators. This is the closest the suite gets to property-based testing without pulling in a dependency.

- [ ] **Step 1: Write the test**

Write `Packages/LillistCore/Tests/LillistCoreTests/Rules/RelativeDateParityTests.swift`:

```swift
import Testing
import Foundation
import CoreData
@testable import LillistCore

@Suite("Relative-date parity property test")
struct RelativeDateParityTests {
    /// Sweep N from 0 to 21. For each N, seed tasks with deadlines at every
    /// integer day offset from -10 to +30 and confirm both evaluators agree
    /// on which match `withinNextDays N`.
    @Test("withinNextDays(N) agrees across paths for N in 0...21",
          arguments: 0...21)
    func sweep(_ n: Int) async throws {
        let controller = try await TestStore.make()
        let ctx = controller.container.viewContext

        let now = ParityFixtures.now
        let cal = ParityFixtures.calendar

        var idsByOffset: [Int: UUID] = [:]
        try await ctx.perform {
            for offset in -10...30 {
                let id = UUID()
                idsByOffset[offset] = id
                let t = LillistTask(context: ctx)
                t.id = id
                t.title = "off=\(offset)"
                t.notes = ""
                t.status = .todo
                t.deadline = cal.date(byAdding: .day, value: offset, to: now)!
                t.createdAt = now; t.modifiedAt = now
            }
            try ctx.save()
        }

        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .deadline, op: .withinNextDays, value: .dayCount(n)))
        ])

        let nsResults: Set<UUID> = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicateCompiler.compile(group, now: now, calendar: cal)
            return Set(try ctx.fetch(req).compactMap { $0.id })
        }

        let swiftResults: Set<UUID> = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            let all = try ctx.fetch(req)
            var out: Set<UUID> = []
            for m in all {
                let snap = SwiftEvaluator.TaskSnapshot.from(managedObject: m)
                if SwiftEvaluator.evaluate(group: group, against: snap, now: now, calendar: cal) {
                    if let id = m.id { out.insert(id) }
                }
            }
            return out
        }

        #expect(nsResults == swiftResults, "withinNextDays(\(n)) diverged: NS=\(nsResults.count), Swift=\(swiftResults.count)")
    }
}
```

- [ ] **Step 2: Run the test**

Run: `cd Packages/LillistCore && swift test --filter RelativeDateParityTests`
Expected: PASS, 22 parameterized cases.

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistCore/Tests/LillistCoreTests/Rules/RelativeDateParityTests.swift
git commit -m "test: add property-based relative-date parity test for withinNextDays sweep"
```

---

## Task 20: `SmartFilterStore` — create / fetch / list / update / delete

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Stores/SmartFilterStoreTests.swift`

`SmartFilterStore` follows the same shape as Plan 1's `TaskStore`: `@unchecked Sendable`, all mutations go through `context.perform`, value-type `SmartFilterRecord` DTO surfaced to callers. `predicateGroupJSON` is serialized with `JSONEncoder` / `JSONDecoder`.

- [ ] **Step 1: Write failing CRUD tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Stores/SmartFilterStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("SmartFilterStore — CRUD")
struct SmartFilterStoreCRUDTests {
    private func sampleGroup() -> PredicateGroup {
        .init(combinator: .all, predicates: [
            .leaf(.init(field: .status, op: .is, value: .statusSet([.todo])))
        ])
    }

    @Test("Create returns an id and the row is fetchable")
    func createAndFetch() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        let id = try await store.create(name: "Today", group: sampleGroup())
        let rec = try await store.fetch(id: id)
        #expect(rec.name == "Today")
        #expect(rec.group.combinator == .all)
        #expect(rec.group.predicates.count == 1)
    }

    @Test("Create rejects empty name")
    func emptyNameRejected() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        await #expect(throws: LillistError.self) {
            _ = try await store.create(name: "  ", group: PredicateGroup(combinator: .all, predicates: []))
        }
    }

    @Test("Fetch unknown id throws notFound")
    func fetchNotFound() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        await #expect(throws: LillistError.notFound) {
            _ = try await store.fetch(id: UUID())
        }
    }

    @Test("List returns rows in position order")
    func listOrder() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        let a = try await store.create(name: "A", group: sampleGroup())
        let b = try await store.create(name: "B", group: sampleGroup())
        let c = try await store.create(name: "C", group: sampleGroup())
        let list = try await store.list()
        #expect(list.map(\.id) == [a, b, c])
    }

    @Test("Update mutates fields")
    func update() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        let id = try await store.create(name: "Today", group: sampleGroup())
        try await store.update(id: id) { draft in
            draft.name = "Today (renamed)"
            draft.tintColor = "#ff8800"
            draft.sortField = .deadline
            draft.sortAscending = false
        }
        let r = try await store.fetch(id: id)
        #expect(r.name == "Today (renamed)")
        #expect(r.tintColor == "#ff8800")
        #expect(r.sortField == .deadline)
        #expect(r.sortAscending == false)
    }

    @Test("Update can replace the predicate group")
    func updateGroup() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        let id = try await store.create(name: "X", group: sampleGroup())
        let newGroup = PredicateGroup(combinator: .any, predicates: [
            .leaf(.init(field: .isPinned, op: .is, value: .bool(true)))
        ])
        try await store.update(id: id) { d in d.group = newGroup }
        let r = try await store.fetch(id: id)
        #expect(r.group.combinator == .any)
    }

    @Test("Delete removes the row")
    func delete() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        let id = try await store.create(name: "X", group: sampleGroup())
        try await store.delete(id: id)
        await #expect(throws: LillistError.notFound) {
            _ = try await store.fetch(id: id)
        }
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/LillistCore && swift test --filter SmartFilterStoreCRUDTests`
Expected: FAIL — `SmartFilterStore` undefined.

- [ ] **Step 3: Write the implementation**

Write `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift`:

```swift
import Foundation
import CoreData

/// Persistence layer for saved smart filters. Serializes `PredicateGroup`
/// to JSON, stores it at `predicateGroupJSON`. Required-ness of `name` is
/// enforced here, not in the schema (CloudKit-compatibility rule).
public final class SmartFilterStore: @unchecked Sendable {
    private let persistence: PersistenceController
    private var context: NSManagedObjectContext { persistence.container.viewContext }

    public init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    /// Value-type DTO surfaced to callers. Never an `NSManagedObject`.
    public struct SmartFilterRecord: Sendable, Equatable {
        public var id: UUID
        public var name: String
        public var group: PredicateGroup
        public var tintColor: String?
        public var sortField: SortField
        public var sortAscending: Bool
        public var isPinned: Bool
        public var position: Double
        public var createdAt: Date?
        public var modifiedAt: Date?
    }

    /// Mutable view passed to `update`'s closure.
    public struct SmartFilterDraft {
        public var name: String
        public var group: PredicateGroup
        public var tintColor: String?
        public var sortField: SortField
        public var sortAscending: Bool
    }

    // MARK: - Create

    @discardableResult
    public func create(
        name: String,
        group: PredicateGroup,
        tintColor: String? = nil,
        sortField: SortField = .deadline,
        sortAscending: Bool = true
    ) async throws -> UUID {
        try validateName(name)
        let json = try Self.encode(group)
        return try await context.perform { [self] in
            let m = SmartFilter(context: context)
            let id = UUID()
            m.id = id
            m.name = name
            m.predicateGroupJSON = json
            m.tintColor = tintColor
            m.sortField = sortField
            m.sortAscending = sortAscending
            m.isPinned = false
            m.position = try nextPosition()
            m.createdAt = Date()
            m.modifiedAt = m.createdAt
            try context.save()
            return id
        }
    }

    // MARK: - Read

    public func fetch(id: UUID) async throws -> SmartFilterRecord {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            return try record(from: m)
        }
    }

    public func list() async throws -> [SmartFilterRecord] {
        try await context.perform { [self] in
            let req = NSFetchRequest<SmartFilter>(entityName: "SmartFilter")
            req.sortDescriptors = [
                NSSortDescriptor(key: "position", ascending: true),
                NSSortDescriptor(key: "createdAt", ascending: true)
            ]
            return try context.fetch(req).map { try record(from: $0) }
        }
    }

    // MARK: - Update

    public func update(id: UUID, _ block: @escaping (inout SmartFilterDraft) -> Void) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            let current = try record(from: m)
            var draft = SmartFilterDraft(
                name: current.name,
                group: current.group,
                tintColor: current.tintColor,
                sortField: current.sortField,
                sortAscending: current.sortAscending
            )
            block(&draft)
            try validateName(draft.name)
            m.name = draft.name
            m.predicateGroupJSON = try Self.encode(draft.group)
            m.tintColor = draft.tintColor
            m.sortField = draft.sortField
            m.sortAscending = draft.sortAscending
            m.modifiedAt = Date()
            try context.save()
        }
    }

    // MARK: - Delete

    public func delete(id: UUID) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            context.delete(m)
            try context.save()
        }
    }

    // MARK: - Helpers

    func fetchManagedObject(id: UUID, in ctx: NSManagedObjectContext) throws -> SmartFilter {
        let req = NSFetchRequest<SmartFilter>(entityName: "SmartFilter")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        guard let m = try ctx.fetch(req).first else {
            throw LillistError.notFound
        }
        return m
    }

    func nextPosition() throws -> Double {
        let req = NSFetchRequest<SmartFilter>(entityName: "SmartFilter")
        req.sortDescriptors = [NSSortDescriptor(key: "position", ascending: false)]
        req.fetchLimit = 1
        let last = try context.fetch(req).first?.position
        return FractionalPosition.position(after: last, before: nil)
    }

    func validateName(_ name: String) throws {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LillistError.validationFailed([
                .init(field: "name", message: "must not be empty")
            ])
        }
    }

    func record(from m: SmartFilter) throws -> SmartFilterRecord {
        let group: PredicateGroup
        if let json = m.predicateGroupJSON {
            group = try Self.decode(json)
        } else {
            group = .init(combinator: .all, predicates: [])
        }
        return SmartFilterRecord(
            id: m.id ?? UUID(),
            name: m.name ?? "",
            group: group,
            tintColor: m.tintColor,
            sortField: m.sortField,
            sortAscending: m.sortAscending,
            isPinned: m.isPinned,
            position: m.position,
            createdAt: m.createdAt,
            modifiedAt: m.modifiedAt
        )
    }

    // MARK: - JSON codec

    static func encode(_ group: PredicateGroup) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(group)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func decode(_ json: String) throws -> PredicateGroup {
        guard let data = json.data(using: .utf8) else {
            throw LillistError.validationFailed([
                .init(field: "predicateGroupJSON", message: "not valid UTF-8")
            ])
        }
        return try JSONDecoder().decode(PredicateGroup.self, from: data)
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `cd Packages/LillistCore && swift test --filter SmartFilterStoreCRUDTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Stores/SmartFilterStoreTests.swift
git commit -m "feat: add SmartFilterStore with create/fetch/list/update/delete"
```

---

## Task 21: `SmartFilterStore` — `setPinned` and `reorder`

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift`
- Modify: `Packages/LillistCore/Tests/LillistCoreTests/Stores/SmartFilterStoreTests.swift`

- [ ] **Step 1: Append failing tests**

Append to `Packages/LillistCore/Tests/LillistCoreTests/Stores/SmartFilterStoreTests.swift`:

```swift
@Suite("SmartFilterStore — pinning and reorder")
struct SmartFilterStorePinReorderTests {
    private func sample() -> PredicateGroup {
        .init(combinator: .all, predicates: [])
    }

    @Test("setPinned toggles isPinned")
    func setPinned() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        let id = try await store.create(name: "X", group: sample())
        try await store.setPinned(id: id, pinned: true)
        #expect(try await store.fetch(id: id).isPinned == true)
        try await store.setPinned(id: id, pinned: false)
        #expect(try await store.fetch(id: id).isPinned == false)
    }

    @Test("reorder moves a row between two siblings")
    func reorder() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        let a = try await store.create(name: "A", group: sample())
        let b = try await store.create(name: "B", group: sample())
        let c = try await store.create(name: "C", group: sample())
        // Move C between A and B → expected order A, C, B
        try await store.reorder(id: c, after: a, before: b)
        let list = try await store.list()
        #expect(list.map(\.id) == [a, c, b])
    }

    @Test("reorder to head and tail")
    func reorderEdges() async throws {
        let controller = try await TestStore.make()
        let store = SmartFilterStore(persistence: controller)
        let a = try await store.create(name: "A", group: sample())
        let b = try await store.create(name: "B", group: sample())
        let c = try await store.create(name: "C", group: sample())
        try await store.reorder(id: c, after: nil, before: a)
        #expect(try await store.list().map(\.id) == [c, a, b])
        try await store.reorder(id: c, after: b, before: nil)
        #expect(try await store.list().map(\.id) == [a, b, c])
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/LillistCore && swift test --filter SmartFilterStorePinReorderTests`
Expected: FAIL — methods undefined.

- [ ] **Step 3: Extend the store**

Append to `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift`:

```swift
extension SmartFilterStore {
    public func setPinned(id: UUID, pinned: Bool) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            m.isPinned = pinned
            m.modifiedAt = Date()
            try context.save()
        }
    }

    /// Place `id` immediately between `after` and `before` (either may be nil).
    /// Uses `FractionalPosition` for gap-based insertion.
    public func reorder(id: UUID, after: UUID?, before: UUID?) async throws {
        try await context.perform { [self] in
            let target = try fetchManagedObject(id: id, in: context)
            let afterPos: Double? = try after.map { try fetchManagedObject(id: $0, in: context).position }
            let beforePos: Double? = try before.map { try fetchManagedObject(id: $0, in: context).position }
            if let a = afterPos, let b = beforePos, a >= b {
                throw LillistError.validationFailed([
                    .init(field: "reorder", message: "anchors out of order: after=\(a) before=\(b)")
                ])
            }
            target.position = FractionalPosition.position(after: afterPos, before: beforePos)
            target.modifiedAt = Date()
            try context.save()
        }
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `cd Packages/LillistCore && swift test --filter SmartFilterStorePinReorderTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Stores/SmartFilterStoreTests.swift
git commit -m "feat: add SmartFilterStore.setPinned and reorder"
```

---

## Task 22: `SmartFilter.evaluate(persistence:)` and `.count(persistence:)`

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift`
- Modify: `Packages/LillistCore/Tests/LillistCoreTests/Stores/SmartFilterStoreTests.swift`

The convenience entry points used by the UI (badge counts on pinned filters) and the CLI (`lillist filter --saved`).

- [ ] **Step 1: Append failing tests**

Append to `Packages/LillistCore/Tests/LillistCoreTests/Stores/SmartFilterStoreTests.swift`:

```swift
@Suite("SmartFilterStore — evaluate and count")
struct SmartFilterStoreEvaluateTests {
    @Test("evaluate returns TaskRecord ids matching the filter")
    func evaluate() async throws {
        let controller = try await TestStore.make()
        let smartStore = SmartFilterStore(persistence: controller)
        let taskStore = TaskStore(persistence: controller)
        let t1 = try await taskStore.create(title: "Design review")
        let t2 = try await taskStore.create(title: "Write spec")
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .title, op: .contains, value: .string("design")))
        ])
        let fid = try await smartStore.create(name: "Design", group: group)
        let results = try await smartStore.evaluate(id: fid)
        let ids = Set(results.map(\.id))
        #expect(ids.contains(t1))
        #expect(!ids.contains(t2))
    }

    @Test("count returns number of matches")
    func count() async throws {
        let controller = try await TestStore.make()
        let smartStore = SmartFilterStore(persistence: controller)
        let taskStore = TaskStore(persistence: controller)
        _ = try await taskStore.create(title: "Design 1")
        _ = try await taskStore.create(title: "Design 2")
        _ = try await taskStore.create(title: "Other")
        let fid = try await smartStore.create(
            name: "Design",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .title, op: .contains, value: .string("Design")))
            ])
        )
        #expect(try await smartStore.count(id: fid) == 2)
    }

    @Test("evaluate respects sort field and direction")
    func evaluateSort() async throws {
        let controller = try await TestStore.make()
        let smartStore = SmartFilterStore(persistence: controller)
        let taskStore = TaskStore(persistence: controller)
        let cal = Calendar.current
        let now = Date()
        let t1 = try await taskStore.create(title: "B")
        let t2 = try await taskStore.create(title: "A")
        try await taskStore.update(id: t1) { d in d.deadline = cal.date(byAdding: .day, value: 1, to: now) }
        try await taskStore.update(id: t2) { d in d.deadline = cal.date(byAdding: .day, value: 2, to: now) }
        let fid = try await smartStore.create(
            name: "Deadline asc",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .deadline, op: .isSet, value: .bool(true)))
            ]),
            sortField: .deadline,
            sortAscending: true
        )
        let results = try await smartStore.evaluate(id: fid)
        #expect(results.map(\.id) == [t1, t2])
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/LillistCore && swift test --filter SmartFilterStoreEvaluateTests`
Expected: FAIL — methods undefined.

- [ ] **Step 3: Extend the store**

Append to `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift`:

```swift
extension SmartFilterStore {
    /// Evaluate a saved filter and return matching `TaskStore.TaskRecord`s,
    /// sorted by the filter's `sortField` / `sortAscending`. Trash exclusion
    /// is applied implicitly by the compiler unless the predicate explicitly
    /// references `inTrash`.
    public func evaluate(
        id: UUID,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async throws -> [TaskStore.TaskRecord] {
        let rec = try await fetch(id: id)
        return try await context.perform { [self] in
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicateCompiler.compile(rec.group, now: now, calendar: calendar)
            req.sortDescriptors = Self.sortDescriptors(field: rec.sortField, ascending: rec.sortAscending)
            let tasks = try context.fetch(req)
            return tasks.map { Self.record(from: $0) }
        }
    }

    /// Count matching tasks without materializing records — for badge counts.
    public func count(
        id: UUID,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async throws -> Int {
        let rec = try await fetch(id: id)
        return try await context.perform { [self] in
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicateCompiler.compile(rec.group, now: now, calendar: calendar)
            return try context.count(for: req)
        }
    }

    static func sortDescriptors(field: SortField, ascending: Bool) -> [NSSortDescriptor] {
        let primaryKey: String
        switch field {
        case .manualPosition, .deadline: primaryKey = "deadline"
        case .start: primaryKey = "start"
        case .title: primaryKey = "title"
        case .createdAt: primaryKey = "createdAt"
        case .modifiedAt: primaryKey = "modifiedAt"
        case .closedAt: primaryKey = "closedAt"
        case .status: primaryKey = "statusRaw"
        }
        return [
            NSSortDescriptor(key: primaryKey, ascending: ascending),
            NSSortDescriptor(key: "createdAt", ascending: true),
            NSSortDescriptor(key: "id", ascending: true)
        ]
    }

    static func record(from m: LillistTask) -> TaskStore.TaskRecord {
        TaskStore.TaskRecord(
            id: m.id ?? UUID(),
            title: m.title ?? "",
            notes: m.notes ?? "",
            status: m.status,
            start: m.start,
            startHasTime: m.startHasTime,
            deadline: m.deadline,
            deadlineHasTime: m.deadlineHasTime,
            position: m.position,
            isPinned: m.isPinned,
            parentID: m.parent?.id,
            createdAt: m.createdAt,
            modifiedAt: m.modifiedAt,
            closedAt: m.closedAt,
            deletedAt: m.deletedAt
        )
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `cd Packages/LillistCore && swift test --filter SmartFilterStoreEvaluateTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Stores/SmartFilterStoreTests.swift
git commit -m "feat: add SmartFilterStore.evaluate and count using NSPredicateCompiler"
```

---

## Task 23: Final integration sweep

**Files:**
- (no new files)

- [ ] **Step 1: Run the entire test suite**

Run: `cd Packages/LillistCore && swift test 2>&1 | tee /tmp/lillist-rules-test.log`
Expected: every test passes — Plan 1 suite plus all new Plan 3 suites. Count should grow by roughly 80+ test invocations (including the parameterized 30 parity cases and 22 relative-date-sweep cases).

- [ ] **Step 2: Run with strict concurrency checking surfaced**

Run: `cd Packages/LillistCore && swift build -Xswiftc -warnings-as-errors`
Expected: build succeeds with no warnings escalated to errors. If a `Sendable` warning appears in the new Rules code, fix it before continuing.

- [ ] **Step 3: Verify both evaluation paths cover every field that Plan 3 owns**

This is the static lint described in design Section 9: a quick eyeball that every case in `Field` is reachable in both `NSPredicateCompiler.compileLeaf` and `SwiftEvaluator.evaluateLeaf`. The forward-deferred cases (`hasNudges`, `recurrence`) intentionally return `false` until Plans 4 and 5 land — confirm both paths return `false` consistently for these. The parity suite would catch divergence anyway, but a manual cross-check before tagging is cheap insurance.

- [ ] **Step 4: Tag the release**

```bash
git tag -a plan-3-rules-engine -m "Lillist Plan 3: Rules engine and smart filters complete"
```

- [ ] **Step 5: Final verification**

Run: `cd Packages/LillistCore && swift test`
Expected: full suite green.

Plan 3 is complete. Proceed to Plan 4 (Notifications) when ready.

---

## Self-Review Checklist (run by the implementer before merging)

- [ ] All test files exercise observable behaviors (matching tasks, JSON output, etc.), not implementation details.
- [ ] Every `Field` case is reachable in both `NSPredicateCompiler.compileLeaf` and `SwiftEvaluator.evaluateLeaf` — including the deferred `hasNudges` and `recurrence` cases which return `false` in both paths until Plans 4 and 5.
- [ ] The parity fixture suite covers every field × operator combination from design Section 5's table.
- [ ] Every parity fixture asserts three equalities: NSPredicate path == expected, Swift path == expected, NSPredicate path == Swift path.
- [ ] The implicit `inTrash` rule is verified at both ends — explicit `inTrash` leaf suppresses the implicit filter; absence appends it.
- [ ] `Predicate` Codable round-trips a nested-group fixture and uses a stable `type` discriminator key in JSON.
- [ ] `Value` Codable round-trips every case including `uuidSet` (set equality, not order-sensitive) and uses a stable `kind` discriminator.
- [ ] `RelativeDate.parse` accepts every keyword form and offset form listed in design Section 5; the property-based sweep covers `withinNextDays N` for N in 0...21.
- [ ] `SmartFilter` schema is CloudKit-compatible: every attribute is optional in the model; no `Deny` deletion rules; no required relationships.
- [ ] `SmartFilterStore.evaluate` respects the saved sort field and direction with stable tiebreaks (`createdAt`, `id`).
- [ ] No `try!`, no `fatalError`, no `NSManagedObject` escapes the package.
- [ ] **Test Engineer subagent has reviewed test quality** per design Section 9 — particularly: did the parity fixture set actually cover the hard cases (subquery shapes, nested groups, implicit-trash interaction), and would mutation-style breakage in either evaluator be caught?
