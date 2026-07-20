import Testing
import Foundation
@testable import LillistCore

@Suite("CLIBridge.AskHandler")
struct AskHandlerTests {
    @Test("Runs the injected translator's proposal through SmartFilterStore and returns matches")
    func runsTranslatorProposal() async throws {
        let p = try await TestStore.make()
        let milk = try await TaskStore(persistence: p).create(title: "Buy milk")
        _ = try await TaskStore(persistence: p).create(title: "Walk dog")

        let filter = IntermediateFilter(combinator: .all, clauses: [
            IntermediateClause(field: .title, op: .contains, value: .text("milk"))
        ])
        let translator = MockQueryTranslator(returning: filter)

        let outcome = try await CLIBridge.AskHandler.run(
            query: "things about milk",
            persistence: p,
            translator: translator
        )

        #expect(outcome.records.map(\.id) == [milk])
        #expect(outcome.translated.source == .mock)
        #expect(outcome.translated.explanation == "title contains “milk”")
    }

    @Test("Builds the TranslationContext from the real TagStore, so tag names resolve to real ids")
    func buildsContextFromRealTags() async throws {
        let p = try await TestStore.make()
        let workID = try await TagStore(persistence: p).create(name: "Work")
        let tagged = try await TaskStore(persistence: p).create(title: "Report")
        try await TaskStore(persistence: p).assignTag(taskID: tagged, tagID: workID)
        _ = try await TaskStore(persistence: p).create(title: "Untagged")

        let filter = IntermediateFilter(combinator: .all, clauses: [
            IntermediateClause(field: .tag, op: .includesAny, value: .tagNames(["Work"]))
        ])
        let translator = MockQueryTranslator(returning: filter)

        let outcome = try await CLIBridge.AskHandler.run(query: "tagged Work", persistence: p, translator: translator)

        #expect(outcome.translated.group == PredicateGroup(combinator: .all, predicates: [
            .leaf(Leaf(field: .tag, op: .includesAny, value: .uuidSet([workID])))
        ]))
        #expect(outcome.records.map(\.id) == [tagged])
        #expect(outcome.translated.unmappedTerms.isEmpty)
    }

    @Test("An unknown tag name surfaces as an unmapped term but still returns a (possibly empty) result")
    func unknownTagNameSurfaces() async throws {
        let p = try await TestStore.make()
        _ = try await TaskStore(persistence: p).create(title: "Report")

        let filter = IntermediateFilter(combinator: .all, clauses: [
            IntermediateClause(field: .tag, op: .includesAny, value: .tagNames(["Ghost"]))
        ])
        let translator = MockQueryTranslator(returning: filter)

        let outcome = try await CLIBridge.AskHandler.run(query: "tagged Ghost", persistence: p, translator: translator)

        #expect(outcome.records.isEmpty)
        #expect(outcome.translated.unmappedTerms == ["tag “Ghost”"])
    }

    @Test("A translator failure propagates to the caller")
    func translatorFailurePropagates() async throws {
        let p = try await TestStore.make()
        let translator = MockQueryTranslator(throwing: .unsupported)
        await #expect(throws: TranslationFailure.unsupported) {
            _ = try await CLIBridge.AskHandler.run(query: "anything", persistence: p, translator: translator)
        }
    }
}
