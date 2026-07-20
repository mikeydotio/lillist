import AppIntents
import LillistCore
import LillistSearchIntelligence

struct SearchTasksIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Tasks"
    static let description = IntentDescription("Search Lillist by title or notes substring, or as natural language.")

    @Parameter(title: "Query") var query: String
    @Parameter(
        title: "Smart Search",
        description: "Interpret the query as natural language (requires Apple Intelligence) instead of a literal substring match.",
        default: false
    )
    var smart: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Search Lillist for \(\.$query)") {
            \.$smart
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[TaskEntity]> {
        let persistence = try await IntentSupport.makePersistence()
        let records: [TaskStore.TaskRecord]
        if smart {
            guard let translator = FilterTranslatorFactory.makeBest() else {
                throw TranslationFailure.unsupported
            }
            records = try await CLIBridge.AskHandler.run(
                query: query,
                persistence: persistence,
                translator: translator
            ).records
        } else {
            records = try await CLIBridge.SearchHandler.run(
                query: query,
                scopeToken: nil,
                persistence: persistence
            )
        }
        return .result(value: records.map(TaskEntity.init))
    }
}
