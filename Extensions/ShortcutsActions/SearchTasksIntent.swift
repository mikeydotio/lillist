import AppIntents
import LillistCore

struct SearchTasksIntent: AppIntent {
    static var title: LocalizedStringResource = "Search Tasks"
    static var description = IntentDescription("Search Lillist by title or notes substring.")

    @Parameter(title: "Query") var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Search Lillist for \(\.$query)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[TaskEntity]> {
        let persistence = try await IntentSupport.makePersistence()
        let records = try await CLIBridge.SearchHandler.run(
            query: query,
            scopeToken: nil,
            persistence: persistence
        )
        return .result(value: records.map(TaskEntity.init))
    }
}
