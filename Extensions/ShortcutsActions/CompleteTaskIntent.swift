import AppIntents
import LillistCore

struct CompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Task"
    static let description = IntentDescription("Mark a task closed.")

    @Parameter(title: "Task") var task: TaskEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Complete \(\.$task)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let persistence = try await IntentSupport.makePersistence()
        try await CLIBridge.StatusHandler.run(
            token: task.id.uuidString,
            to: .closed,
            note: nil,
            persistence: persistence
        )
        await WidgetRefresh.refreshAfterMutation(persistence: persistence)
        return .result()
    }
}
