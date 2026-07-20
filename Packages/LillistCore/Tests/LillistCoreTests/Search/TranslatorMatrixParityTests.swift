import Testing
import Foundation
@testable import LillistCore

/// Drift guard: confirms `IntermediateFilterMapper` can never mark a
/// (field, op) pair legal that the rule engine (`NSPredicateCompiler` /
/// `SwiftEvaluator`) doesn't have deliberate, parity-tested behavior for.
/// Rather than hand-duplicating the mapper's internal matrix (which could
/// silently drift from its real behavior), this test *discovers* the
/// mapper's legal set by actually invoking it, and *discovers* the engine's
/// covered set from the very fixtures `ParitySuiteTests` already runs
/// against both evaluators — so a future mapper change that legalizes a
/// pair the engine doesn't meaningfully support fails here, not in
/// production as a silently-empty smart filter.
@Suite("Mapper legal-triple table is a subset of what the engines actually accept")
struct TranslatorMatrixParityTests {
    private struct FieldOpPair: Hashable, CustomStringConvertible {
        let field: Field
        let op: Op
        var description: String { "\(field.rawValue) \(op.rawValue)" }
    }

    /// A coverage bucket after canonicalizing field-agnostic implementation
    /// classes (see `canonicalize(_:)`). `field == nil` means "any field in
    /// that shared-implementation class".
    private struct CoverageKey: Hashable, CustomStringConvertible {
        let field: Field?
        let op: Op
        var description: String { "\(field?.rawValue ?? "<any field in the class>") \(op.rawValue)" }
    }

    /// `NSPredicateCompiler.compileDate` / `SwiftEvaluator.matchDate`
    /// implement `before`/`after`/`on`/`withinLastDays`/`withinNextDays`/
    /// `isSet`/`isUnset` identically across all five date fields — verified
    /// directly in source: both dispatch purely on the resolved key path /
    /// passed-in `Date?`, never branching on which field it came from
    /// (`equalsModifiedAt` is the one genuinely field-specific case,
    /// `createdAt`-only, and is intentionally excluded from this bucket).
    private static let dateFieldClass: Set<Field> = [.start, .deadline, .createdAt, .modifiedAt, .closedAt]

    /// `NSPredicateCompiler.compileString` / `SwiftEvaluator.matchString`
    /// implement `contains`/`equals`/`startsWith` identically for `title`
    /// and `notes` (both dispatch on a generic key path / haystack string).
    /// `journalText` is deliberately excluded — it has its own
    /// `compileJournalText`/`matchJournalText` implementation restricted to
    /// `contains` only, already exercised directly.
    private static let stringFieldClass: Set<Field> = [.title, .notes]

    /// Collapses a (field, op) pair into its shared-implementation coverage
    /// bucket, so fixture coverage of any ONE field in a class stands in
    /// for the whole class — reflecting the engine's real, verified
    /// architecture rather than requiring the fixture set to redundantly
    /// cross-product every op against every field that already shares one
    /// code path.
    private static func canonicalize(_ pair: FieldOpPair) -> CoverageKey {
        if dateFieldClass.contains(pair.field), pair.op != .equalsModifiedAt {
            return CoverageKey(field: nil, op: pair.op)
        }
        if stringFieldClass.contains(pair.field) {
            return CoverageKey(field: nil, op: pair.op)
        }
        return CoverageKey(field: pair.field, op: pair.op)
    }

    /// Every `IntermediateValue` shape, tried against every (field, op) pair
    /// so no legal combination is missed just because this test guessed the
    /// wrong value case.
    private static let representativeValues: [IntermediateValue] = [
        .text("x"),
        .tagNames(["Work"]),
        .statuses([.closed]),
        .boolean(true),
        .absoluteDateISO8601("2026-01-01"),
        .relativeDate(.today),
        .dayCount(1),
        .attachmentKind(AttachmentKindMatch(present: true, kind: nil)),
        .none
    ]

    /// The (field, op) pairs `IntermediateFilterMapper` will produce a
    /// `Leaf` for, discovered by exhaustively invoking it — not copied from
    /// its source, so this can't rot out of sync with real behavior.
    private static func mapperLegalPairs() -> Set<FieldOpPair> {
        let context = TranslationContext(knownTags: [TagRef(id: UUID(), name: "Work")])
        var legal: Set<FieldOpPair> = []
        for field in Field.allCases {
            for op in Op.allCases {
                let acceptsSomeValue = representativeValues.contains { value in
                    let clause = IntermediateClause(field: field, op: op, value: value)
                    let filter = IntermediateFilter(combinator: .all, clauses: [clause])
                    return !IntermediateFilterMapper.map(filter, context: context).group.predicates.isEmpty
                }
                if acceptsSomeValue {
                    legal.insert(FieldOpPair(field: field, op: op))
                }
            }
        }
        return legal
    }

    /// Every (field, op) pair the parity fixture set (hand-written +
    /// generated matrix — the same set `ParitySuiteTests` runs against both
    /// `NSPredicateCompiler` and `SwiftEvaluator`) deliberately exercises.
    private static func engineCoveredPairs() -> Set<FieldOpPair> {
        var covered: Set<FieldOpPair> = []
        for fixture in ParityFixtures.all + ParityMatrix.all {
            collect(fixture.group, into: &covered)
        }
        return covered
    }

    private static func collect(_ group: PredicateGroup, into set: inout Set<FieldOpPair>) {
        for predicate in group.predicates {
            switch predicate {
            case .leaf(let leaf): set.insert(FieldOpPair(field: leaf.field, op: leaf.op))
            case .group(let g): collect(g, into: &set)
            }
        }
    }

    @Test("every mapper-legal (field, op) pair is engine-covered")
    func mapperLegalIsSubsetOfEngineCovered() {
        let legal = Set(Self.mapperLegalPairs().map(Self.canonicalize))
        let covered = Set(Self.engineCoveredPairs().map(Self.canonicalize))
        let uncovered = legal.subtracting(covered)
        #expect(uncovered.isEmpty, "mapper accepts (field, op) pairs the parity fixtures never exercise: \(uncovered.map(\.description).sorted())")
    }

    @Test("the mapper's legal set is non-trivial — this guard isn't vacuously passing")
    func legalSetIsNonEmpty() {
        #expect(Self.mapperLegalPairs().count > 20)
    }
}
