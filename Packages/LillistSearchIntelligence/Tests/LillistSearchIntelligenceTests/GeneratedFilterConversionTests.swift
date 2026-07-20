import Testing
import Foundation
import LillistCore
@testable import LillistSearchIntelligence
#if canImport(FoundationModels)

/// Purely structural tests of `GeneratedFilter`/`GeneratedClause` →
/// `IntermediateFilter`/`IntermediateClause` conversion — no live model, no
/// `LanguageModelSession`, deterministic and CI-runnable. This is the
/// boundary between "whatever a real model happens to emit" and the
/// deterministic `IntermediateFilterMapper` in `LillistCore`, so it's
/// exercised exhaustively even though live inference can't be.
///
/// Every test body opens with `guard #available(iOS 26, macOS 26, *) else
/// { return }` rather than annotating the `@Test` function itself — Swift
/// Testing's `@Test` macro rejects `@available`-restricted functions
/// outright ("Attribute 'Test' cannot be applied to this function because
/// it has been marked '@available'"), so the guard is the documented
/// workaround. It's a no-op skip on this Mac (host is already macOS 26+);
/// it exists to satisfy the *compile-time* deployment-target check, since
/// the package's own platform floor (macOS 15) is below `GeneratedFilter`'s.
@Suite("GeneratedFilter/GeneratedClause conversion")
struct GeneratedFilterConversionTests {
    @Test("combinator string maps to the right PredicateGroup.Combinator, defaulting to all")
    func combinatorMapping() {
        guard #available(iOS 26, macOS 26, *) else { return }
        #expect(GeneratedFilter(combinator: "any", clauses: []).toIntermediateFilter().combinator == .any)
        #expect(GeneratedFilter(combinator: "ANY", clauses: []).toIntermediateFilter().combinator == .any)
        #expect(GeneratedFilter(combinator: "all", clauses: []).toIntermediateFilter().combinator == .all)
        #expect(GeneratedFilter(combinator: "gibberish", clauses: []).toIntermediateFilter().combinator == .all)
    }

    @Test("a clause with an unrecognized field or comparator is dropped, not crashed on")
    func unrecognizedFieldOrComparatorDropped() {
        guard #available(iOS 26, macOS 26, *) else { return }
        let filter = GeneratedFilter(combinator: "all", clauses: [
            GeneratedClause(field: "not-a-real-field", comparator: "contains", text: "x"),
            GeneratedClause(field: "title", comparator: "not-a-real-op", text: "x")
        ])
        #expect(filter.toIntermediateFilter().clauses.isEmpty)
    }

    @Test("text carrier feeds contains/equals/startsWith")
    func textCarrier() {
        guard #available(iOS 26, macOS 26, *) else { return }
        for op in ["contains", "equals", "startsWith"] {
            let clause = GeneratedClause(field: "title", comparator: op, text: "spec")
            #expect(clause.toIntermediateClause() == IntermediateClause(field: .title, op: Op(rawValue: op)!, value: .text("spec")))
        }
    }

    @Test("tagNames carrier feeds includesAny/includesAll/excludesAll, empty when absent")
    func tagNamesCarrier() {
        guard #available(iOS 26, macOS 26, *) else { return }
        let withNames = GeneratedClause(field: "tag", comparator: "includesAny", tagNames: ["Work", "Home"])
        #expect(withNames.toIntermediateClause() == IntermediateClause(field: .tag, op: .includesAny, value: .tagNames(["Work", "Home"])))

        let withoutNames = GeneratedClause(field: "tag", comparator: "includesAny")
        #expect(withoutNames.toIntermediateClause() == IntermediateClause(field: .tag, op: .includesAny, value: .tagNames([])))
    }

    @Test("statuses carrier resolves recognized names, including common synonyms")
    func statusesCarrier() {
        guard #available(iOS 26, macOS 26, *) else { return }
        let clause = GeneratedClause(field: "status", comparator: "isNot", statuses: ["Done", "BLOCKED"])
        guard case .statuses(let resolved)? = clause.toIntermediateClause()?.value else {
            Issue.record("expected a .statuses value")
            return
        }
        #expect(Set(resolved) == [.closed, .blocked])
    }

    @Test("statuses carrier with no recognizable names falls back to boolValue, then none")
    func statusesCarrierFallback() {
        guard #available(iOS 26, macOS 26, *) else { return }
        let unrecognized = GeneratedClause(field: "status", comparator: "is", statuses: ["nonsense"])
        #expect(unrecognized.toIntermediateClause()?.value == IntermediateValue.none)
    }

    @Test("boolValue carrier feeds is for boolean fields")
    func boolValueCarrier() {
        guard #available(iOS 26, macOS 26, *) else { return }
        let clause = GeneratedClause(field: "isPinned", comparator: "is", boolValue: true)
        #expect(clause.toIntermediateClause() == IntermediateClause(field: .isPinned, op: .is, value: .boolean(true)))
    }

    @Test("relativeDate carrier parses via RelativeDate.parse for before/after/on")
    func relativeDateCarrier() {
        guard #available(iOS 26, macOS 26, *) else { return }
        for op in ["before", "after", "on"] {
            let clause = GeneratedClause(field: "deadline", comparator: op, relativeDate: "today")
            #expect(clause.toIntermediateClause() == IntermediateClause(field: .deadline, op: Op(rawValue: op)!, value: .relativeDate(.today)))
        }
        let offset = GeneratedClause(field: "deadline", comparator: "before", relativeDate: "+3d")
        #expect(offset.toIntermediateClause() == IntermediateClause(field: .deadline, op: .before, value: .relativeDate(.daysFromNow(3))))
    }

    @Test("an unparsable relativeDate string falls back to absoluteDate, then none")
    func relativeDateFallsBackToAbsolute() {
        guard #available(iOS 26, macOS 26, *) else { return }
        let clause = GeneratedClause(field: "deadline", comparator: "before", relativeDate: "not a date", absoluteDate: "2026-07-20")
        #expect(clause.toIntermediateClause() == IntermediateClause(field: .deadline, op: .before, value: .absoluteDateISO8601("2026-07-20")))
    }

    @Test("dayCount carrier feeds withinLastDays/withinNextDays")
    func dayCountCarrier() {
        guard #available(iOS 26, macOS 26, *) else { return }
        for op in ["withinLastDays", "withinNextDays"] {
            let clause = GeneratedClause(field: "deadline", comparator: op, dayCount: 7)
            #expect(clause.toIntermediateClause() == IntermediateClause(field: .deadline, op: Op(rawValue: op)!, value: .dayCount(7)))
        }
    }

    @Test("isSet/isUnset/equalsModifiedAt need no carrier")
    func noCarrierOps() {
        guard #available(iOS 26, macOS 26, *) else { return }
        for op in ["isSet", "isUnset", "equalsModifiedAt"] {
            let clause = GeneratedClause(field: "createdAt", comparator: op)
            #expect(clause.toIntermediateClause() == IntermediateClause(field: .createdAt, op: Op(rawValue: op)!, value: .none))
        }
    }

    @Test("offeredFields excludes ancestor; offeredComparators excludes isDescendantOf/isAncestorOf")
    func offeredVocabularyExcludesUnsupported() {
        guard #available(iOS 26, macOS 26, *) else { return }
        let context = TranslationContext()
        #expect(!GeneratedFilter.offeredFields(from: context).contains(.ancestor))
        #expect(GeneratedFilter.offeredFields(from: context).count == Field.allCases.count - 1)
        #expect(!GeneratedFilter.offeredComparators.contains(.isDescendantOf))
        #expect(!GeneratedFilter.offeredComparators.contains(.isAncestorOf))
    }

    @Test("end-to-end: the issue's compound example converts to the expected IntermediateFilter")
    func compoundIssueExampleConverts() {
        guard #available(iOS 26, macOS 26, *) else { return }
        let generated = GeneratedFilter(combinator: "all", clauses: [
            GeneratedClause(field: "deadline", comparator: "before", relativeDate: "today"),
            GeneratedClause(field: "status", comparator: "isNot", statuses: ["closed"])
        ])
        let intermediate = generated.toIntermediateFilter()
        #expect(intermediate == IntermediateFilter(combinator: .all, clauses: [
            IntermediateClause(field: .deadline, op: .before, value: .relativeDate(.today)),
            IntermediateClause(field: .status, op: .isNot, value: .statuses([.closed]))
        ]))
    }
}
// Note: no custom convenience initializer needed here — the `@Generable`
// macro already synthesizes a memberwise init with every property
// defaulting to `nil` where optional, so call sites can name only the
// carriers each test actually needs.
#endif
