import Testing
import Foundation
@testable import LillistCore

@Suite("FilterQueryTranslator default translate(_:context:)")
struct FilterQueryTranslatorTests {
    static let ctx = TranslationContext(now: Date(), calendar: .current)

    @Test("translate maps the proposed IntermediateFilter through the mapper and renders an explanation")
    func translateHappyPath() async throws {
        let filter = IntermediateFilter(combinator: .all, clauses: [
            IntermediateClause(field: .createdAt, op: .before, value: .relativeDate(.today))
        ])
        let translator = MockQueryTranslator(returning: filter)
        let result = try await translator.translate("added before today", context: Self.ctx)

        #expect(result.source == .mock)
        #expect(result.group.predicates == [.leaf(Leaf(field: .createdAt, op: .before, value: .relativeDate(.today)))])
        #expect(result.explanation == "created before today")
        #expect(result.unmappedTerms.isEmpty)
        #expect(!result.isEmpty)
    }

    @Test("dropped clauses and unresolved tag names surface as unmappedTerms")
    func translateSurfacesUnmapped() async throws {
        let filter = IntermediateFilter(combinator: .all, clauses: [
            IntermediateClause(field: .createdAt, op: .before, value: .relativeDate(.today)),
            IntermediateClause(field: .journalText, op: .equals, value: .text("nope")),
            IntermediateClause(field: .tag, op: .includesAny, value: .tagNames(["Ghost"]))
        ])
        let translator = MockQueryTranslator(returning: filter)
        let result = try await translator.translate("a messy query", context: Self.ctx)

        #expect(result.unmappedTerms.contains("journalText equals"))
        #expect(result.unmappedTerms.contains("tag “Ghost”"))
    }

    @Test("an empty query throws before the translator is even consulted")
    func emptyQueryThrows() async throws {
        let translator = MockQueryTranslator(throwing: .unsupported)
        await #expect(throws: TranslationFailure.emptyQuery) {
            _ = try await translator.translate("   ", context: Self.ctx)
        }
    }

    @Test("a translator failure propagates")
    func translatorFailurePropagates() async throws {
        let translator = MockQueryTranslator(throwing: .underlying("model unavailable"))
        await #expect(throws: TranslationFailure.underlying("model unavailable")) {
            _ = try await translator.translate("anything", context: Self.ctx)
        }
    }

    @Test("a query that maps to nothing produces an empty TranslatedQuery, not a crash")
    func allDroppedProducesEmptyQuery() async throws {
        let filter = IntermediateFilter(combinator: .all, clauses: [
            IntermediateClause(field: .ancestor, op: .isDescendantOf, value: .none)
        ])
        let translator = MockQueryTranslator(returning: filter)
        let result = try await translator.translate("gibberish", context: Self.ctx)
        #expect(result.isEmpty)
        #expect(result.explanation == nil)
    }
}
