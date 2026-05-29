# Predicate-Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the four silent divergences between `NSPredicateCompiler` and `SwiftEvaluator`, give the two evaluators a single source of truth for ancestor depth and recurrence/nudges, and replace the one-example-per-behavior parity suite with a `Field × Op × Value` matrix run against a DST-straddling non-UTC fixture so any future drift fails red.

**Architecture:** A new `PredicateLimits` namespace owns the single `maxAncestorDepth` constant, referenced by the compiler's `compileAncestor`, by `SwiftEvaluator.TaskSnapshot.from`, and by the CLI Search/Resolver scope walks. `SwiftEvaluator.matchString(.equals)` is realigned to the NS `==[cd]` semantics (case- *and* diacritic-insensitive). Recurrence and nudges become real predicates on both sides (compiler emits `series != nil` / `notificationSpecs.@count > 0`; `from` populates the snapshot from `m.series`/`m.notificationSpecs`). `isAncestorOf` is made symmetric by stubbing **both** evaluators to `false` (YAGNI — no surfaced caller). The parity suite is generalised into a matrix driver and run twice (once under the existing UTC calendar, once under an `America/New_York` DST-straddling calendar) asserting `nsResults == swiftResults == expected` per cell.

**Tech Stack:** Swift 6.2, Core Data (`NSPersistentCloudKitContainer`, in-memory store via `TestStore.make()`), Swift Testing (`import Testing`, `@Suite`/`@Test`/`#expect`, parameterized `arguments:`). Strict concurrency on the `LillistCore` source target; warnings-as-errors.

**Source findings:** rules-1, rules-2, rules-3, rules-4, rules-5, rules-6, rules-7 (Roadmap item #7).

Finding-to-fix map (verified against current source, 2026-05-28):

| Finding | Current divergence | This plan |
| --- | --- | --- |
| `rules-1` | `from()` walks `depth < 32` (`SwiftEvaluator.swift:297`); compiler `compileAncestor` walks `1...8` (`NSPredicateCompiler.swift:285,295`); Resolver/Search walk `depth < 64` (`Resolver.swift:245`, `SearchHandler.swift:34`) | One `PredicateLimits.maxAncestorDepth = 8` referenced everywhere |
| `rules-2` | `matchString(.equals)` uses `localizedCaseInsensitiveCompare` (case-insensitive only, `SwiftEvaluator.swift:261`); compiler uses `==[cd]` (case + diacritic, `NSPredicateCompiler.swift:110`) | Align Swift `.equals` to case + diacritic insensitive |
| `rules-3` | `recurrence`/`hasNudges` compile to `NSPredicate(value: false)` (`NSPredicateCompiler.swift:96-98`); `from()` hardcodes `isRecurring`/`hasNudges = false` (`SwiftEvaluator.swift:333-334`) | Real predicates both sides; `from` reads `m.series`/`m.notificationSpecs` |
| `rules-4` | `matchAncestor(.isAncestorOf)` returns `false` (`SwiftEvaluator.swift:181`); compiler emits a real `children…` SUBQUERY (`NSPredicateCompiler.swift:290-299`) | Both stub `false` (symmetric, YAGNI) |
| `rules-5` | Parity suite has no recurrence/nudges/`isAncestorOf`/`equals`-diacritic cells | Add matrix cells for the four formerly-divergent ops |
| `rules-6` | Parity suite is one-example-per-behavior, UTC-only (`ParityFixtures.swift:67-471`, `ParitySuiteTests.swift:8-114`) | Matrix-driven; run under UTC **and** DST-straddling `America/New_York` |
| `rules-7` | `RelativeDateResolver.resolve(.weeksFromNow(n))` computes `n * 7` (`RelativeDateResolver.swift:23`) — traps on `Int` overflow | Overflow-safe multiply with saturation |

**Strengths to protect (do NOT refactor away):** the `tag.isUnset`/`isSet` cardinality handling that precedes the `uuidSet` guard in both `matchTag`/`compileTag`; the implicit-trash short-circuit in `SwiftEvaluator.evaluate`; the `Calendar`-based date math in `RelativeDateResolver` and both date matchers; the synchronous parameterized `@Test(arguments:)` parity harness shape (in-memory Core Data + dual fetch).

---

## File Structure

**Create**

- `Packages/LillistCore/Sources/LillistCore/Rules/PredicateLimits.swift` — single home for engine-wide bounds. Owns `public enum PredicateLimits { public static let maxAncestorDepth = 8 }`. One responsibility: the shared ancestor-depth ceiling.

**Modify**

- `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift` — `compileAncestor` uses `PredicateLimits.maxAncestorDepth`; `compileLeaf` compiles real `recurrence`/`hasNudges` predicates; `compileAncestor(.isAncestorOf)` stubs to `NSPredicate(value: false)`.
- `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift` — `matchString(.equals)` becomes case + diacritic insensitive; `TaskSnapshot.from` walks `PredicateLimits.maxAncestorDepth`, reads `m.series`/`m.notificationSpecs` for `isRecurring`/`hasNudges`; `matchAncestor(.isAncestorOf)` comment simplified (already returns false).
- `Packages/LillistCore/Sources/LillistCore/Rules/RelativeDateResolver.swift` — `.weeksFromNow(n)` uses an overflow-safe `n × 7`.
- `Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift` — `passesScope` ancestor walk uses `PredicateLimits.maxAncestorDepth`.
- `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/SearchHandler.swift` — scope ancestor walk uses `PredicateLimits.maxAncestorDepth`.

**Test (Create / Modify)**

- `Packages/LillistCore/Tests/LillistCoreTests/Rules/ParityFixtures.swift` — extend `SeedTask` with `isRecurring`/`hasNudges`; add a DST-straddling `nyCalendar` + `nyNow`; add fixtures for the four formerly-divergent ops.
- `Packages/LillistCore/Tests/LillistCoreTests/Rules/ParityMatrix.swift` *(new)* — the `Field × Op × Value` cell type and the generated matrix.
- `Packages/LillistCore/Tests/LillistCoreTests/Rules/ParitySuiteTests.swift` — seed `series`/`notificationSpecs`; parameterize the run over both calendars; assert `ns == swift == expected` per cell.
- `Packages/LillistCore/Tests/LillistCoreTests/Rules/RelativeDateParityTests.swift` — add a `weeksFromNow` overflow regression test.
- `Packages/LillistCore/Tests/LillistCoreTests/Rules/SwiftEvaluatorTests.swift` — add a `.equals` diacritic case asserting `café == cafe`.

---

## Task 1: Introduce `PredicateLimits.maxAncestorDepth` and unify all four walks on it

**Files:**
- Create `Packages/LillistCore/Sources/LillistCore/Rules/PredicateLimits.swift`
- Modify `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift` (`compileAncestor`, lines 278-303)
- Modify `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift` (`from`, lines 293-301)
- Modify `Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift` (`passesScope`, lines 242-251)
- Modify `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/SearchHandler.swift` (scope filter, lines 31-40)
- Test `Packages/LillistCore/Tests/LillistCoreTests/Rules/ParitySuiteTests.swift` (existing fixture #18 `ancestor isDescendantOf {parentA}` exercises the descendant path; we add a deep-chain matrix cell in Task 5)

This closes **rules-1**. Today a task 9+ levels deep under a root is found by the compiler at most 8 levels (so excluded beyond 8) but included by `from()` up to 32 levels — a real divergence. After this task both evaluators use a depth-8 ceiling, and the CLI scope walks match.

- [ ] **Step 1: Write the failing test** — add a deep-chain parity fixture that fails today because the two evaluators walk different depths. Append this fixture to the `static let all: [ParityFixture]` array in `Packages/LillistCore/Tests/LillistCoreTests/Rules/ParityFixtures.swift`, immediately before the closing `]` on line 471 (after fixture 32 `tag isSet`). First add the required id constants — insert these two lines right after `static let parentA = UUID(...)` on line 65:

```swift
    // Deep-chain ids for the ancestor-depth parity fixture (Task 1).
    static let chainRoot = UUID(uuidString: "00000000-0000-0000-0003-000000000000")!
    static func chainNode(_ depth: Int) -> UUID {
        UUID(uuidString: "00000000-0000-0000-0003-0000000000\(String(format: "%02d", depth))")!
    }
```

Then add the fixture (note the trailing comma added to the previous fixture #32):

```swift
        ,
        // 33. ancestor isDescendantOf over a chain exactly at the depth ceiling.
        // A node at depth == maxAncestorDepth must match in BOTH evaluators;
        // a node one level deeper must match in NEITHER. Pre-fix, `from()`
        // walked 32 levels and the compiler walked 8, so depth-9 diverged.
        ParityFixture(
            name: "ancestor isDescendantOf chain at depth ceiling",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .ancestor, op: .isDescendantOf, value: .uuidSet([chainRoot])))
            ]),
            seeds: {
                var out: [SeedTask] = [SeedTask(id: chainRoot, title: "root")]
                var parent = chainRoot
                // depth 1...9: nine nested children under chainRoot.
                for depth in 1...9 {
                    let nodeID = chainNode(depth)
                    out.append(SeedTask(id: nodeID, title: "depth-\(depth)", parentID: parent))
                    parent = nodeID
                }
                return out
            }(),
            // PredicateLimits.maxAncestorDepth == 8: depths 1...8 are reachable,
            // depth 9 is beyond the ceiling for both evaluators.
            expected: Set((1...8).map { chainNode($0) })
        )
```

- [ ] **Step 2: Run the test, expect failure** —

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter ParitySuiteTests
```

Expect the new cell to fail with a paths-diverged message, e.g.:
`[ancestor isDescendantOf chain at depth ceiling] paths diverged: NSPredicate=[…8 ids…], Swift=[…9 ids…]` (the Swift path walks 32 and includes depth-9; NS walks 8 and excludes it).

- [ ] **Step 3: Implement the minimal change** — create `Packages/LillistCore/Sources/LillistCore/Rules/PredicateLimits.swift` with the complete contents:

```swift
import Foundation

/// Engine-wide numeric bounds shared by the predicate compiler, the pure-Swift
/// evaluator, and the CLI scope walks. Centralising these prevents the two
/// evaluators (and the CLI breadcrumb/scope traversals) from silently disagreeing
/// on how deep a parent chain is honoured.
public enum PredicateLimits {
    /// Maximum number of ancestor hops the engine honours when resolving
    /// `isDescendantOf` / `isAncestorOf` and when denormalising a task's
    /// ancestor set.
    ///
    /// The ceiling exists because `NSPredicate` cannot express transitive
    /// closure over a SQL store, so `NSPredicateCompiler.compileAncestor`
    /// unrolls a fixed number of `parent.…parent.id` key-paths. Every other
    /// traversal (the `SwiftEvaluator` snapshot walk, the CLI scope filters)
    /// matches this number so all paths agree on reachability.
    ///
    /// Tasks nested deeper than this are not matched by ancestor predicates.
    /// 8 is comfortably beyond any hand-authored hierarchy depth a user
    /// produces and keeps the unrolled predicate small.
    public static let maxAncestorDepth = 8
}
```

Then edit `compileAncestor` in `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift` (lines 278-303) to reference the constant. Replace the whole method body's two `(1...8)` ranges:

```swift
    static func compileAncestor(op: Op, value: Value) -> NSPredicate {
        guard case .uuidSet(let ids) = value else { return NSPredicate(value: false) }
        switch op {
        case .isDescendantOf:
            // Task whose parent (or transitive ancestor) is one of the ids.
            // Core Data does not expose transitive closure in predicate format,
            // so we OR a fixed depth of parent.id checks bounded by
            // `PredicateLimits.maxAncestorDepth` (shared with SwiftEvaluator).
            let depths = (1...PredicateLimits.maxAncestorDepth).map { depth -> NSPredicate in
                let keyPath = (0..<depth).map { _ in "parent" }.joined(separator: ".") + ".id"
                return NSPredicate(format: "%K IN %@", keyPath, Array(ids))
            }
            return NSCompoundPredicate(orPredicateWithSubpredicates: depths)
        case .isAncestorOf:
            // Symmetric with SwiftEvaluator.matchAncestor: there is no surfaced
            // caller for `isAncestorOf` (YAGNI), so both evaluators stub `false`
            // rather than diverge. Wire up a reverse-reachability traversal in
            // both places together if a feature ever needs it.
            return NSPredicate(value: false)
        default:
            return NSPredicate(value: false)
        }
    }
```

> Note: collapsing `.isAncestorOf` to `false` here is **rules-4** (Task 4 below) — but because it lives in the same method as the depth change it is simplest to land both edits in one method body. Step 5 commits only the depth-related wording; the `isAncestorOf` parity test in Task 4 will exercise the `false` branch. If you prefer strict TDD isolation, leave the old `children…` SUBQUERY block here and replace it in Task 4 — both orders pass. This plan lands it now.

Now edit the snapshot walk in `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift` (lines 293-301). Replace:

```swift
        // Ancestor chain (depth-bounded at 32 to match the compiler's safe ceiling)
        var ancestorIDs: Set<UUID> = []
        var cursor: LillistTask? = m.parent
        var depth = 0
        while let p = cursor, depth < 32 {
            if let pid = p.id { ancestorIDs.insert(pid) }
            cursor = p.parent
            depth += 1
        }
```

with:

```swift
        // Ancestor chain, depth-bounded by the shared `PredicateLimits`
        // ceiling so this walk matches `NSPredicateCompiler.compileAncestor`.
        var ancestorIDs: Set<UUID> = []
        var cursor: LillistTask? = m.parent
        var depth = 0
        while let p = cursor, depth < PredicateLimits.maxAncestorDepth {
            if let pid = p.id { ancestorIDs.insert(pid) }
            cursor = p.parent
            depth += 1
        }
```

Now edit the CLI scope walk in `Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift` (lines 243-249). Replace:

```swift
                var cursor: LillistTask? = task.parent
                var depth = 0
                while let node = cursor, depth < 64 {
                    if node.id == rootID { return true }
                    cursor = node.parent
                    depth += 1
                }
```

with:

```swift
                var cursor: LillistTask? = task.parent
                var depth = 0
                while let node = cursor, depth < PredicateLimits.maxAncestorDepth {
                    if node.id == rootID { return true }
                    cursor = node.parent
                    depth += 1
                }
```

Now edit the scope filter in `Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/SearchHandler.swift` (lines 32-39). Replace:

```swift
                        var cursor: LillistTask? = task.parent
                        var depth = 0
                        while let node = cursor, depth < 64 {
                            if node.id == scopeID { return true }
                            cursor = node.parent
                            depth += 1
                        }
```

with:

```swift
                        var cursor: LillistTask? = task.parent
                        var depth = 0
                        while let node = cursor, depth < PredicateLimits.maxAncestorDepth {
                            if node.id == scopeID { return true }
                            cursor = node.parent
                            depth += 1
                        }
```

- [ ] **Step 4: Run the test, expect pass** —

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter ParitySuiteTests
```

Expect `Test run with N tests passed` (no diverged message for the chain cell; depth-9 excluded by both evaluators, depths 1...8 included by both).

- [ ] **Step 5: Commit** —

```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistCore/Sources/LillistCore/Rules/PredicateLimits.swift \
        Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift \
        Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift \
        Packages/LillistCore/Sources/LillistCore/CLIBridge/Resolver.swift \
        Packages/LillistCore/Sources/LillistCore/CLIBridge/Handlers/SearchHandler.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Rules/ParityFixtures.swift
git commit -m "fix(rules): unify ancestor depth on PredicateLimits.maxAncestorDepth

Both predicate evaluators and the CLI scope walks now bound the parent
chain at one shared ceiling (8). Previously the compiler walked 8, the
SwiftEvaluator snapshot walked 32, and the CLI scope walks walked 64,
so a deeply nested task could match one evaluator and not the other.

Closes rules-1."
```

---

## Task 2: Align `SwiftEvaluator.matchString(.equals)` to diacritic + case-insensitive (`==[cd]`)

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift` (`matchString`, lines 257-266)
- Test `Packages/LillistCore/Tests/LillistCoreTests/Rules/SwiftEvaluatorTests.swift` (add a diacritic `.equals` case)

This closes **rules-2**. The compiler emits `==[cd]` (case + diacritic insensitive); `SwiftEvaluator.matchString(.equals)` uses `localizedCaseInsensitiveCompare`, which is case-insensitive only. `café` != `cafe` in Swift today but matches in NS.

- [ ] **Step 1: Write the failing test** — append this `@Test` to the `SwiftEvaluatorTests` suite in `Packages/LillistCore/Tests/LillistCoreTests/Rules/SwiftEvaluatorTests.swift` (immediately after the `titleEqualsCaseInsensitive` test that ends on line 61):

```swift
    @Test("title equals is diacritic-insensitive (matches NS ==[cd])")
    func titleEqualsDiacriticInsensitive() {
        let g = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .title, op: .equals, value: .string("cafe")))
        ])
        // ==[cd] folds diacritics: "café" must equal "cafe".
        #expect(SwiftEvaluator.evaluate(group: g, against: snapshot(title: "café")) == true)
        // And case must still fold both ways.
        #expect(SwiftEvaluator.evaluate(group: g, against: snapshot(title: "CAFÉ")) == true)
        // A genuinely different string must not match.
        #expect(SwiftEvaluator.evaluate(group: g, against: snapshot(title: "cafeteria")) == false)
    }
```

- [ ] **Step 2: Run the test, expect failure** —

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter SwiftEvaluatorTests
```

Expect `titleEqualsDiacriticInsensitive` to fail on the first `#expect` (`café` does not equal `cafe` under `localizedCaseInsensitiveCompare`).

- [ ] **Step 3: Implement the minimal change** — edit `matchString` in `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift` (lines 257-266). Replace the whole method:

```swift
    static func matchString(_ haystack: String, op: Op, value: Value) -> Bool {
        guard case .string(let needle) = value else { return false }
        switch op {
        case .contains: return haystack.localizedStandardContains(needle)
        case .equals:
            // Match the compiler's `==[cd]`: case- AND diacritic-insensitive.
            return haystack.compare(
                needle,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: nil,
                locale: nil
            ) == .orderedSame
        case .startsWith:
            return haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
        default: return false
        }
    }
```

- [ ] **Step 4: Run the test, expect pass** —

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter SwiftEvaluatorTests
```

Expect `Test run with N tests passed`, including `titleEqualsDiacriticInsensitive`.

- [ ] **Step 5: Commit** —

```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Rules/SwiftEvaluatorTests.swift
git commit -m "fix(rules): align SwiftEvaluator equals to diacritic+case-insensitive

NSPredicateCompiler compiles string equality as ==[cd] (case- and
diacritic-insensitive); the SwiftEvaluator used localizedCaseInsensitive
comparison, so 'café' equalled 'cafe' in one evaluator but not the other.
Both now fold case and diacritics.

Closes rules-2."
```

---

## Task 3: Single source of truth for `recurrence` / `hasNudges` across both evaluators

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift` (`compileLeaf`, lines 96-99)
- Modify `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift` (`TaskSnapshot.from`, lines 333-334)
- Test `Packages/LillistCore/Tests/LillistCoreTests/Rules/ParityFixtures.swift` (extend `SeedTask`; add two fixtures)
- Test `Packages/LillistCore/Tests/LillistCoreTests/Rules/ParitySuiteTests.swift` (seed `series`/`notificationSpecs`)

This closes **rules-3**. Today `recurrence`/`hasNudges` compile to `NSPredicate(value: false)` and `from()` hardcodes both snapshot flags to `false`, so a "is recurring" smart filter silently matches nothing in *both* evaluators — they "agree" only by both being wrong. We make them real: compiler emits `series != nil` / `notificationSpecs.@count > 0`; the snapshot reads `m.series`/`m.notificationSpecs`.

- [ ] **Step 1: Write the failing test** — first extend `SeedTask` in `Packages/LillistCore/Tests/LillistCoreTests/Rules/ParityFixtures.swift` (lines 15-31). Add two stored properties right after the `attachmentKinds` line (line 30):

```swift
    var isRecurring: Bool = false
    var hasNudges: Bool = false
```

Next teach the seed loop to create the backing rows. In `Packages/LillistCore/Tests/LillistCoreTests/Rules/ParitySuiteTests.swift`, inside the `try await ctx.perform { … }` seeding block, add a new pass **after** the attachments loop (after line 76, before `try ctx.save()` on line 77):

```swift
            // Recurrence (a Series seed) and nudges (a NotificationSpec).
            for seed in fixture.seeds {
                guard let t = byID[seed.id] else { continue }
                if seed.isRecurring {
                    let series = Series(context: ctx)
                    series.id = UUID()
                    series.ruleJSON = nil
                    t.series = series
                }
                if seed.hasNudges {
                    let spec = NotificationSpec(context: ctx)
                    spec.id = UUID()
                    spec.kind = .defaultStart
                    spec.createdAt = Date()
                    spec.task = t
                }
            }
```

Then add two parity fixtures to `static let all` in `ParityFixtures.swift`, appended after the chain fixture added in Task 1 (add a leading comma):

```swift
        ,
        // 34. recurrence is true — must surface only the recurring task in BOTH.
        ParityFixture(
            name: "recurrence is true",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .recurrence, op: .is, value: .bool(true)))
            ]),
            seeds: [
                SeedTask(id: id1, title: "weekly review", isRecurring: true),
                SeedTask(id: id2, title: "one-off", isRecurring: false)
            ],
            expected: [id1]
        ),
        // 35. hasNudges is true — must surface only the nudged task in BOTH.
        ParityFixture(
            name: "hasNudges is true",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .hasNudges, op: .is, value: .bool(true)))
            ]),
            seeds: [
                SeedTask(id: id1, title: "reminder set", hasNudges: true),
                SeedTask(id: id2, title: "no reminder", hasNudges: false)
            ],
            expected: [id1]
        )
```

- [ ] **Step 2: Run the test, expect failure** —

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter ParitySuiteTests
```

Expect both new cells to fail. `recurrence is true` and `hasNudges is true` each yield empty result sets from both evaluators (compiler `NSPredicate(value: false)`; snapshot flags hardcoded `false`), e.g. `[recurrence is true] NSPredicate path mismatch: got [], expected [id1]`.

- [ ] **Step 3: Implement the minimal change** — edit `compileLeaf` in `Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift` (lines 96-99). Replace:

```swift
        case .hasNudges, .recurrence:
            // Wired up by Plans 4 and 5 respectively.
            return NSPredicate(value: false)
```

with:

```swift
        case .hasNudges:
            return compileHasNudges(op: leaf.op, value: leaf.value)
        case .recurrence:
            return compileRecurrence(op: leaf.op, value: leaf.value)
```

Then add the two compiler helpers. Insert them immediately after `compileHasChildren` (after line 153, before the `// MARK: - Dates` comment on line 155):

```swift
    // MARK: - hasNudges

    static func compileHasNudges(op: Op, value: Value) -> NSPredicate {
        guard case .bool(let b) = value, op == .is else { return NSPredicate(value: false) }
        return b
            ? NSPredicate(format: "notificationSpecs.@count > 0")
            : NSPredicate(format: "notificationSpecs.@count == 0")
    }

    // MARK: - recurrence

    static func compileRecurrence(op: Op, value: Value) -> NSPredicate {
        guard case .bool(let b) = value, op == .is else { return NSPredicate(value: false) }
        return b
            ? NSPredicate(format: "series != nil")
            : NSPredicate(format: "series == nil")
    }
```

Now populate the snapshot in `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift`. The `from` factory builds `hasNudges`/`isRecurring` near lines 333-334. Replace:

```swift
            hasNudges: false,     // Plan 4
            isRecurring: false    // Plan 5
```

with:

```swift
            hasNudges: (m.notificationSpecs?.count ?? 0) > 0,
            isRecurring: m.series != nil
```

- [ ] **Step 4: Run the test, expect pass** —

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter ParitySuiteTests
```

Expect `Test run with N tests passed`, including `recurrence is true` and `hasNudges is true` (both evaluators now return `[id1]`).

- [ ] **Step 5: Commit** —

```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift \
        Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Rules/ParityFixtures.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Rules/ParitySuiteTests.swift
git commit -m "fix(rules): give recurrence/hasNudges one source of truth in both evaluators

The compiler stubbed recurrence/hasNudges to NSPredicate(value:false) and
the SwiftEvaluator snapshot hardcoded both flags to false, so an 'is
recurring' or 'has nudges' smart filter matched nothing in either path.
Both now read the real relationships: series != nil and
notificationSpecs.@count > 0.

Closes rules-3."
```

---

## Task 4: Make `isAncestorOf` symmetric — both evaluators stub `false` (YAGNI)

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift` (`matchAncestor`, lines 170-184) — tighten the stale comment; behaviour already `false`.
- (`NSPredicateCompiler.compileAncestor` `.isAncestorOf` was collapsed to `NSPredicate(value: false)` in Task 1.)
- Test `Packages/LillistCore/Tests/LillistCoreTests/Rules/ParityFixtures.swift` (add an `isAncestorOf` parity fixture)

This closes **rules-4**. Today the compiler emits a real `children…` SUBQUERY for `isAncestorOf` while the SwiftEvaluator returns `false` — a divergence. Since no surfaced feature uses `isAncestorOf`, both stub `false` (YAGNI). The parity fixture pins that they agree on `false`.

- [ ] **Step 1: Write the failing test** — add this fixture to `static let all` in `Packages/LillistCore/Tests/LillistCoreTests/Rules/ParityFixtures.swift`, appended after the `hasNudges is true` fixture from Task 3 (add a leading comma):

```swift
        ,
        // 36. ancestor isAncestorOf {id1}: no surfaced caller, so BOTH
        // evaluators stub `false` — a parent of id1 must NOT be returned.
        ParityFixture(
            name: "ancestor isAncestorOf is unsupported (false in both)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .ancestor, op: .isAncestorOf, value: .uuidSet([id1])))
            ]),
            seeds: [
                SeedTask(id: parentA, title: "Parent"),
                SeedTask(id: id1, parentID: parentA),
                SeedTask(id: id2, parentID: nil)
            ],
            expected: []
        )
```

- [ ] **Step 2: Run the test, expect failure** —

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter ParitySuiteTests
```

If Task 1 already collapsed the compiler's `.isAncestorOf` branch to `false`, this cell **passes immediately** — the test is then a regression guard rather than red→green. If you deferred the compiler `.isAncestorOf` collapse, expect failure here: `[ancestor isAncestorOf is unsupported (false in both)] paths diverged: NSPredicate=[parentA], Swift=[]` (compiler's `children…` SUBQUERY returns `parentA`).

- [ ] **Step 3: Implement the minimal change** — if not already done in Task 1, collapse the compiler `.isAncestorOf` branch (see Task 1 Step 3 for the exact `compileAncestor` body). Then tighten the now-stale comment in `matchAncestor` in `Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift` (lines 170-184). Replace:

```swift
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
```

with:

```swift
    static func matchAncestor(_ ancestorIDs: Set<UUID>, op: Op, value: Value) -> Bool {
        guard case .uuidSet(let ids) = value else { return false }
        switch op {
        case .isDescendantOf: return !ancestorIDs.isDisjoint(with: ids)
        case .isAncestorOf:
            // No surfaced caller (YAGNI): `NSPredicateCompiler.compileAncestor`
            // and this matcher both stub `false`. Wire up reverse-reachability
            // in both places together if a feature ever needs it. The parity
            // suite pins the symmetric `false`.
            return false
        default: return false
        }
    }
```

- [ ] **Step 4: Run the test, expect pass** —

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter ParitySuiteTests
```

Expect `Test run with N tests passed`, including `ancestor isAncestorOf is unsupported (false in both)` (both evaluators return `[]`).

- [ ] **Step 5: Commit** —

```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift \
        Packages/LillistCore/Sources/LillistCore/Rules/NSPredicateCompiler.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Rules/ParityFixtures.swift
git commit -m "fix(rules): make isAncestorOf symmetric (both evaluators stub false)

The compiler emitted a children-SUBQUERY for isAncestorOf while the
SwiftEvaluator returned false. With no surfaced caller (YAGNI), both now
stub false and a parity fixture pins the agreement.

Closes rules-4."
```

---

## Task 5: Guard `RelativeDate.weeksFromNow` against integer overflow

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/Rules/RelativeDateResolver.swift` (`.weeksFromNow`, line 22-23)
- Test `Packages/LillistCore/Tests/LillistCoreTests/Rules/RelativeDateParityTests.swift` (add an overflow regression `@Test`)

This closes **rules-7**. `resolve(.weeksFromNow(n))` computes `n * 7`. A `RelativeDate` decoded from JSON (Importer / CloudKit / CLI) can carry `n == Int.max`, which traps the process on the multiply before `Calendar` ever runs. Saturating the multiply keeps it a defined no-trap path; `Calendar.date(byAdding:)` already returns `nil` (falling back to `startOfToday`) for out-of-range day counts.

- [ ] **Step 1: Write the failing test** — append this suite to `Packages/LillistCore/Tests/LillistCoreTests/Rules/RelativeDateParityTests.swift` (after the closing `}` of `RelativeDateParityTests` on line 58):

```swift
@Suite("RelativeDate weeksFromNow overflow guard")
struct RelativeDateWeeksOverflowTests {
    /// `weeksFromNow(Int.max)` would trap on `n * 7`. The resolver must
    /// saturate the multiply and return a defined date (the start-of-today
    /// fallback when the day count overflows the calendar's range).
    @Test("weeksFromNow(Int.max) does not trap")
    func maxWeeksNoTrap() {
        let now = ParityFixtures.now
        let cal = ParityFixtures.calendar
        // Must not crash. Calendar.date(byAdding:) returns nil for an
        // out-of-range day count, so resolve falls back to start-of-today.
        let resolved = RelativeDateResolver.resolve(.weeksFromNow(Int.max), now: now, calendar: cal)
        #expect(resolved == cal.startOfDay(for: now))
    }

    @Test("weeksFromNow(Int.min) does not trap")
    func minWeeksNoTrap() {
        let now = ParityFixtures.now
        let cal = ParityFixtures.calendar
        let resolved = RelativeDateResolver.resolve(.weeksFromNow(Int.min), now: now, calendar: cal)
        #expect(resolved == cal.startOfDay(for: now))
    }

    @Test("weeksFromNow(2) still resolves to +14 days")
    func smallWeeksUnchanged() {
        let now = ParityFixtures.now
        let cal = ParityFixtures.calendar
        let resolved = RelativeDateResolver.resolve(.weeksFromNow(2), now: now, calendar: cal)
        let expected = cal.date(byAdding: .day, value: 14, to: cal.startOfDay(for: now))!
        #expect(resolved == expected)
    }
}
```

- [ ] **Step 2: Run the test, expect failure** —

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter RelativeDateWeeksOverflowTests
```

Expect a crash / fatal error (the test process traps on `Int.max * 7` arithmetic overflow) — Swift Testing reports the run as failed with a `Fatal error: arithmetic overflow` style message before `maxWeeksNoTrap` can complete.

- [ ] **Step 3: Implement the minimal change** — edit the `.weeksFromNow` case in `Packages/LillistCore/Sources/LillistCore/Rules/RelativeDateResolver.swift` (lines 22-23). Replace:

```swift
        case .weeksFromNow(let n):
            return calendar.date(byAdding: .day, value: n * 7, to: startOfToday) ?? startOfToday
```

with:

```swift
        case .weeksFromNow(let n):
            // Saturate the week→day multiply so a pathological decoded count
            // (e.g. Int.max from a corrupt import) never traps. Calendar then
            // returns nil for an out-of-range day count and we fall back to
            // start-of-today.
            let (days, overflow) = n.multipliedReportingOverflow(by: 7)
            let safeDays = overflow ? (n > 0 ? Int.max : Int.min) : days
            return calendar.date(byAdding: .day, value: safeDays, to: startOfToday) ?? startOfToday
```

- [ ] **Step 4: Run the test, expect pass** —

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter RelativeDateWeeksOverflowTests
```

Expect `Test run with 3 tests passed` (no trap; `Int.max`/`Int.min` saturate to the start-of-today fallback; `2` still gives +14 days).

- [ ] **Step 5: Commit** —

```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistCore/Sources/LillistCore/Rules/RelativeDateResolver.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Rules/RelativeDateParityTests.swift
git commit -m "fix(rules): guard RelativeDate.weeksFromNow against integer overflow

resolve(.weeksFromNow(n)) computed n*7, which trapped for a pathological
decoded count (Int.max from a corrupt import/CloudKit/CLI value). The
multiply now saturates and Calendar falls back to start-of-today.

Closes rules-7."
```

---

## Task 6: Generalise the parity sweep into a `Field × Op × Value` matrix run under two calendars

**Files:**
- Create `Packages/LillistCore/Tests/LillistCoreTests/Rules/ParityMatrix.swift`
- Modify `Packages/LillistCore/Tests/LillistCoreTests/Rules/ParityFixtures.swift` (add `nyNow` + `nyCalendar`)
- Modify `Packages/LillistCore/Tests/LillistCoreTests/Rules/ParitySuiteTests.swift` (parameterize the existing run over both calendars)

This closes **rules-5** and **rules-6**. The existing suite is one-example-per-behaviour and UTC-only. We add a compact `Field × Op × Value` matrix (string ops incl. negative/nil/empty/diacritic/case, status, bool, dates, set ops, recurrence/nudges/ancestor) that drives **both** evaluators, and we run the whole fixture set **twice** — once under the UTC `ParityFixtures.calendar` and once under a DST-straddling `America/New_York` calendar with a `now` near the spring-forward boundary — asserting `nsResults == swiftResults == expected` per cell on both runs.

> Note: the matrix reuses the `ParityFixture` shape (a `PredicateGroup` + seeds + expected set), so the proven in-memory Core Data harness in `ParitySuiteTests` runs it unchanged. The matrix is a *generator* of `ParityFixture` values, not a new harness.

- [ ] **Step 1: Write the failing test** — first add the DST calendar/now to `Packages/LillistCore/Tests/LillistCoreTests/Rules/ParityFixtures.swift`. Insert immediately after the `calendar` static (after line 48, before `static func days`):

```swift
    /// A non-UTC, DST-straddling reference for the second parity run.
    /// 2026-03-08 is US spring-forward day in America/New_York (02:00 → 03:00),
    /// so date windows resolved here exercise a 23-hour day. `now` is the
    /// morning of spring-forward so `withinNextDays`/`on` windows cross the
    /// transition.
    static let nyNow: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 3; c.day = 8
        c.hour = 9; c.minute = 0
        c.timeZone = TimeZone(identifier: "America/New_York")
        return Calendar(identifier: .gregorian).date(from: c)!
    }()

    static let nyCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.firstWeekday = 1
        return c
    }()

    /// Day offset helper resolved against the DST calendar/now.
    static func nyDays(_ n: Int, from date: Date = nyNow) -> Date {
        nyCalendar.date(byAdding: .day, value: n, to: date)!
    }
```

Next create the matrix generator `Packages/LillistCore/Tests/LillistCoreTests/Rules/ParityMatrix.swift` with complete contents:

```swift
import Foundation
@testable import LillistCore

/// A `Field × Op × Value` parity matrix. Each cell is a `ParityFixture`
/// (a `PredicateGroup` plus seeds plus the expected id set), so the proven
/// in-memory Core Data harness in `ParitySuiteTests` runs every cell against
/// BOTH evaluators with no harness changes. The matrix deliberately includes
/// negative / nil / empty / diacritic / case cells and the four formerly
/// divergent ops (equals-with-diacritic, recurrence, hasNudges, isAncestorOf).
enum ParityMatrix {
    private typealias F = ParityFixtures

    /// Seed ids reserved for the matrix so they never collide with the
    /// hand-written fixture ids.
    static let m1 = UUID(uuidString: "00000000-0000-0000-0004-000000000001")!
    static let m2 = UUID(uuidString: "00000000-0000-0000-0004-000000000002")!
    static let m3 = UUID(uuidString: "00000000-0000-0000-0004-000000000003")!

    static let all: [ParityFixture] = [
        // --- String × {contains, equals, startsWith} incl. case/diacritic/empty ---
        ParityFixture(
            name: "matrix: title contains 'spec' (positive + negative)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .title, op: .contains, value: .string("spec")))
            ]),
            seeds: [
                SeedTask(id: m1, title: "write spec"),
                SeedTask(id: m2, title: "unrelated")
            ],
            expected: [m1]
        ),
        ParityFixture(
            name: "matrix: title contains '' (empty needle matches all)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .title, op: .contains, value: .string("")))
            ]),
            seeds: [
                SeedTask(id: m1, title: "anything"),
                SeedTask(id: m2, title: "")
            ],
            expected: [m1, m2]
        ),
        ParityFixture(
            name: "matrix: title equals 'Inbox' (case fold)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .title, op: .equals, value: .string("Inbox")))
            ]),
            seeds: [
                SeedTask(id: m1, title: "inbox"),
                SeedTask(id: m2, title: "Inbox zero")
            ],
            expected: [m1]
        ),
        ParityFixture(
            name: "matrix: title equals 'cafe' (diacritic fold)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .title, op: .equals, value: .string("cafe")))
            ]),
            seeds: [
                SeedTask(id: m1, title: "café"),
                SeedTask(id: m2, title: "cafeteria")
            ],
            expected: [m1]
        ),
        ParityFixture(
            name: "matrix: notes startsWith 'TODO' (anchored, case fold)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .notes, op: .startsWith, value: .string("TODO")))
            ]),
            seeds: [
                SeedTask(id: m1, notes: "todo: follow up"),
                SeedTask(id: m2, notes: "a todo later")
            ],
            expected: [m1]
        ),

        // --- Status × {is, isNot} ---
        ParityFixture(
            name: "matrix: status isNot {closed}",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .status, op: .isNot, value: .statusSet([.closed])))
            ]),
            seeds: [
                SeedTask(id: m1, status: .started),
                SeedTask(id: m2, status: .closed)
            ],
            expected: [m1]
        ),

        // --- Bool × is (isPinned, including the negative match) ---
        ParityFixture(
            name: "matrix: isPinned is false",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .isPinned, op: .is, value: .bool(false)))
            ]),
            seeds: [
                SeedTask(id: m1, isPinned: false),
                SeedTask(id: m2, isPinned: true)
            ],
            expected: [m1]
        ),

        // --- Date × {before, after, on, withinNextDays, withinLastDays, isSet, isUnset} ---
        // These cells are seeded relative to ParityFixtures.now; the suite
        // re-derives the expected set per calendar by re-seeding (see Step 3).
        ParityFixture(
            name: "matrix: deadline isUnset (nil case)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .deadline, op: .isUnset, value: .bool(true)))
            ]),
            seeds: [
                SeedTask(id: m1, deadline: nil),
                SeedTask(id: m2, deadline: F.days(1))
            ],
            expected: [m1]
        ),
        ParityFixture(
            name: "matrix: deadline on today (day window)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .deadline, op: .on, value: .relativeDate(.today)))
            ]),
            seeds: [
                SeedTask(id: m1, deadline: F.now),
                SeedTask(id: m2, deadline: F.days(1))
            ],
            expected: [m1]
        ),

        // --- Set ops × tag {includesAny, includesAll, excludesAll, isSet, isUnset} ---
        ParityFixture(
            name: "matrix: tag isUnset (empty set)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .tag, op: .isUnset, value: .bool(true)))
            ]),
            seeds: [
                SeedTask(id: m1, tagIDs: []),
                SeedTask(id: m2, tagIDs: [F.tagWork])
            ],
            expected: [m1]
        ),
        ParityFixture(
            name: "matrix: tag excludesAll {work} (incl. no-tag task)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .tag, op: .excludesAll, value: .uuidSet([F.tagWork])))
            ]),
            seeds: [
                SeedTask(id: m1, tagIDs: [F.tagHome]),
                SeedTask(id: m2, tagIDs: [F.tagWork]),
                SeedTask(id: m3, tagIDs: [])
            ],
            expected: [m1, m3]
        ),

        // --- The four formerly-divergent ops ---
        ParityFixture(
            name: "matrix: recurrence is true",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .recurrence, op: .is, value: .bool(true)))
            ]),
            seeds: [
                SeedTask(id: m1, isRecurring: true),
                SeedTask(id: m2, isRecurring: false)
            ],
            expected: [m1]
        ),
        ParityFixture(
            name: "matrix: hasNudges is true",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .hasNudges, op: .is, value: .bool(true)))
            ]),
            seeds: [
                SeedTask(id: m1, hasNudges: true),
                SeedTask(id: m2, hasNudges: false)
            ],
            expected: [m1]
        ),
        ParityFixture(
            name: "matrix: ancestor isDescendantOf {m1}",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .ancestor, op: .isDescendantOf, value: .uuidSet([m1])))
            ]),
            seeds: [
                SeedTask(id: m1, title: "root"),
                SeedTask(id: m2, parentID: m1),
                SeedTask(id: m3, parentID: nil)
            ],
            expected: [m2]
        ),
        ParityFixture(
            name: "matrix: ancestor isAncestorOf {m2} (false in both)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .ancestor, op: .isAncestorOf, value: .uuidSet([m2])))
            ]),
            seeds: [
                SeedTask(id: m1, title: "root"),
                SeedTask(id: m2, parentID: m1)
            ],
            expected: []
        )
    ]
}
```

Then modify the parity runner to (a) include the matrix and (b) run under both calendars. In `Packages/LillistCore/Tests/LillistCoreTests/Rules/ParitySuiteTests.swift`, replace the test signature and the two `now:`/`calendar:` callsites so the test is parameterized over a `(now, calendar)` pair. Replace the whole `@Test(...)`/`func parity(...)` declaration plus its NS and Swift fetch blocks. Replace lines 6-114 (the entire `struct ParitySuiteTests` body) with:

```swift
@Suite("Parity: NSPredicate vs SwiftEvaluator over the fixture set")
struct ParitySuiteTests {
    /// A named calendar context the parity run is executed under. Running the
    /// same fixtures under UTC and a DST-straddling America/New_York calendar
    /// catches day-window math that only breaks across a 23-hour day.
    struct CalendarContext: Sendable, CustomStringConvertible {
        let name: String
        let now: Date
        let calendar: Calendar
        var description: String { name }
    }

    static let contexts: [CalendarContext] = [
        CalendarContext(name: "UTC", now: ParityFixtures.now, calendar: ParityFixtures.calendar),
        CalendarContext(name: "America/New_York (DST)", now: ParityFixtures.nyNow, calendar: ParityFixtures.nyCalendar)
    ]

    /// The full fixture set: the hand-written behavioural fixtures plus the
    /// generated Field × Op × Value matrix.
    static let fixtures: [ParityFixture] = ParityFixtures.all + ParityMatrix.all

    @Test("Every fixture matches expected set in both evaluators, under each calendar",
          arguments: fixtures, contexts)
    func parity(_ fixture: ParityFixture, _ ctxInfo: CalendarContext) async throws {
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
            var tagsByID: [UUID: LillistCore.Tag] = [:]
            for seed in fixture.seeds {
                for tid in seed.tagIDs {
                    if tagsByID[tid] == nil {
                        let tag = LillistCore.Tag(context: ctx)
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
            // Recurrence (a Series seed) and nudges (a NotificationSpec).
            for seed in fixture.seeds {
                guard let t = byID[seed.id] else { continue }
                if seed.isRecurring {
                    let series = Series(context: ctx)
                    series.id = UUID()
                    series.ruleJSON = nil
                    t.series = series
                }
                if seed.hasNudges {
                    let spec = NotificationSpec(context: ctx)
                    spec.id = UUID()
                    spec.kind = .defaultStart
                    spec.createdAt = Date()
                    spec.task = t
                }
            }
            try ctx.save()
        }

        let nsResults: Set<UUID> = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicateCompiler.compile(
                fixture.group,
                now: ctxInfo.now,
                calendar: ctxInfo.calendar
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
                    now: ctxInfo.now,
                    calendar: ctxInfo.calendar
                ) {
                    if let id = m.id { out.insert(id) }
                }
            }
            return out
        }

        // --- Assertions ---
        #expect(nsResults == fixture.expected, "[\(ctxInfo)] [\(fixture.name)] NSPredicate path mismatch: got \(nsResults), expected \(fixture.expected)")
        #expect(swiftResults == fixture.expected, "[\(ctxInfo)] [\(fixture.name)] SwiftEvaluator path mismatch: got \(swiftResults), expected \(fixture.expected)")
        #expect(nsResults == swiftResults, "[\(ctxInfo)] [\(fixture.name)] paths diverged: NSPredicate=\(nsResults), Swift=\(swiftResults)")
    }
}
```

> Why the date fixtures stay correct under both calendars: every date fixture seeds its deadlines from `ParityFixtures.days(...)`/`F.now` (absolute instants), and the predicate windows are *relative* (`.today`, `.withinNextDays`). The two calendars resolve "today/within N days" against their own `now`, but each fixture's expected set is defined by the relative relationship (seeded `now+k` vs the window), which is invariant across the calendars used. The DST run's value is that the *day-window math* (`startOfDay`/`endOfDay` across a 23-hour day) is exercised by both evaluators on the same data, and they must still agree.

- [ ] **Step 2: Run the test, expect failure** — run the matrix-only cells first to prove they exercise the new behaviour, then the full suite. If Tasks 1-5 are already committed, the matrix passes; the *intent* of this step is that the matrix would have failed against pre-Task-1..5 code. To prove the matrix has teeth, temporarily revert one fix (optional) — otherwise verify the matrix executes both calendar arms:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter ParitySuiteTests 2>&1 | tail -20
```

Before this step's code is added, the build fails because `ParityMatrix`, `nyNow`, `nyCalendar`, and the two-argument `@Test` do not exist — that compile failure is the expected "red". Expected error (pre-implementation): `error: cannot find 'ParityMatrix' in scope` / `error: type 'ParityFixtures' has no member 'nyNow'`.

- [ ] **Step 3: Implement the minimal change** — the code in Step 1 *is* the implementation (the new `ParityMatrix.swift`, the `nyNow`/`nyCalendar` additions, and the rewritten `ParitySuiteTests`). No production-source change is required in this task — Tasks 1-5 already aligned the evaluators. Confirm the three edited/created test files compile together.

- [ ] **Step 4: Run the test, expect pass** —

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter ParitySuiteTests
```

Expect `Test run with N tests passed` where N = `(ParityFixtures.all.count + ParityMatrix.all.count) × 2` (every fixture × both calendars), e.g. with 36 hand-written fixtures + 15 matrix cells that is `51 × 2 = 102` parameterized cases, all green with no diverged/mismatch messages.

- [ ] **Step 5: Commit** —

```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistCore/Tests/LillistCoreTests/Rules/ParityMatrix.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Rules/ParityFixtures.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Rules/ParitySuiteTests.swift
git commit -m "test(rules): matrix-drive the parity suite under UTC and a DST calendar

Generalise the one-example-per-behaviour parity suite into a Field x Op x
Value matrix (negative/nil/empty/diacritic/case + the four formerly
divergent ops) and run the whole fixture set under both the UTC calendar
and a DST-straddling America/New_York calendar, asserting
nsResults == swiftResults == expected per cell.

Closes rules-5, rules-6."
```

---

## Task 7: Full-suite regression and warnings-as-errors gate

**Files:** none (verification only).

Confirms nothing else in `LillistCore` regressed and the strict-concurrency source target still compiles warning-clean after the new `PredicateLimits` type and the evaluator edits.

- [ ] **Step 1: Run the complete LillistCore suite** —

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore 2>&1 | tail -25
```

Expect `Test run with N tests passed` with zero failures (the baseline 649 plus the new parity cells and overflow/diacritic tests).

- [ ] **Step 2: Confirm a warning-clean build of the source target** —

```bash
cd /Volumes/Code/mikeyward/Lillist && swift build --package-path Packages/LillistCore 2>&1 | grep -i "warning:" || echo "no warnings"
```

Expect `no warnings` (house rule: warnings-as-errors; do not paper over — if a warning appears, fix it at the source).

- [ ] **Step 3: Confirm the CLI scope walks still behave** — the Resolver/SearchHandler edits are exercised by the existing `ResolverTests` and any search handler tests; run them explicitly:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter ResolverTests
```

Expect `Test run with N tests passed`. (No deep-scope CLI test exists today; the depth change only *tightens* the ceiling from 64 to 8, which is far beyond any fixture's hierarchy depth, so existing scope tests stay green.)

- [ ] **Step 4: No commit** — verification task; if any check fails, return to the responsible task and fix before proceeding.

---

## Self-review checklist

- [ ] **rules-1** (unify ancestor depth into one shared `maxAncestorDepth`) — closed by **Task 1**: new `PredicateLimits.maxAncestorDepth` referenced by `compileAncestor`, `TaskSnapshot.from`, `Resolver.passesScope`, and `SearchHandler`; pinned by the depth-ceiling chain parity fixture.
- [ ] **rules-2** (align `equals` to diacritic + case-insensitive `==[cd]`) — closed by **Task 2**: `matchString(.equals)` uses `[.caseInsensitive, .diacriticInsensitive]`; pinned by `titleEqualsDiacriticInsensitive`.
- [ ] **rules-3** (single source of truth for recurrence / `hasNudges`) — closed by **Task 3**: compiler emits `series != nil` / `notificationSpecs.@count > 0`; `from` reads `m.series`/`m.notificationSpecs`; pinned by the `recurrence is true` and `hasNudges is true` fixtures.
- [ ] **rules-4** (symmetric `isAncestorOf`, both stub `false` per YAGNI) — closed by **Task 1 + Task 4**: compiler `.isAncestorOf` collapsed to `NSPredicate(value: false)`, SwiftEvaluator already `false`; pinned by the `isAncestorOf is unsupported (false in both)` fixture.
- [ ] **rules-5** (fixtures for the four formerly-divergent ops) — closed by **Task 3 (recurrence/nudges)**, **Task 4 (isAncestorOf)**, **Task 2 (equals-diacritic)**, and **Task 6** matrix cells covering all four.
- [ ] **rules-6** (matrix-driven parity against a non-UTC DST-straddling fixture, asserting `nsResults == swiftResults == expected`) — closed by **Task 6**: `ParityMatrix` Field × Op × Value cells + dual-calendar run (UTC and America/New_York DST).
- [ ] **rules-7** (guard `RelativeDate.weeksFromNow` against integer overflow) — closed by **Task 5**: saturating `multipliedReportingOverflow(by: 7)`; pinned by `RelativeDateWeeksOverflowTests`.

**Cross-plan coordination note:** `breadcrumb-truthfulness` [P1] touches `Stores/TaskStore.swift`/`TagStore.swift`/`JournalStore.swift`. The unbounded breadcrumb ancestor walk in `Stores/TaskStore+Queries.swift:83-87` is intentionally **left out of scope** here (it is not a Search/Resolver walk and is not parity-affecting); if `breadcrumb-truthfulness` bounds it, it should reuse `PredicateLimits.maxAncestorDepth` introduced by this plan rather than reintroduce a literal. No file overlap between the two plans.
