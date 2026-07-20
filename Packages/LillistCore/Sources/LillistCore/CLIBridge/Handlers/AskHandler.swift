import Foundation

extension CLIBridge {
    /// Runs a natural-language query (`lillist search --smart`, and the
    /// Shortcuts `smart` search parameter) through an injected
    /// `FilterQueryTranslator` and `SmartFilterStore`. Deliberately
    /// translator-agnostic — this file has no FoundationModels dependency,
    /// same as the rest of `LillistCore` — the caller supplies whichever
    /// translator it wants (a real tier from
    /// `LillistSearchIntelligence.FilterTranslatorFactory` in production,
    /// `MockQueryTranslator` in tests).
    public enum AskHandler {
        /// The translated query alongside the records it matched, so the
        /// caller can render both the results and a "here's what I searched
        /// for" / "couldn't understand: …" diagnostic.
        public struct Outcome: Sendable {
            public var records: [TaskStore.TaskRecord]
            public var translated: TranslatedQuery

            public init(records: [TaskStore.TaskRecord], translated: TranslatedQuery) {
                self.records = records
                self.translated = translated
            }
        }

        public static func run(
            query: String,
            persistence: PersistenceController,
            translator: any FilterQueryTranslator,
            now: Date = Date(),
            calendar: Calendar = .current
        ) async throws -> Outcome {
            let tags = try await TagStore(persistence: persistence).list()
            let context = TranslationContext(
                knownTags: tags.map { TagRef(id: $0.id, name: $0.name) },
                now: now,
                calendar: calendar
            )
            let translated = try await translator.translate(query, context: context)
            let records = try await SmartFilterStore(persistence: persistence).evaluate(
                group: translated.group,
                now: now,
                calendar: calendar
            )
            return Outcome(records: records, translated: translated)
        }
    }
}
