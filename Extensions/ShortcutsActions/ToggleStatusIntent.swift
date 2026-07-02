import AppIntents
import LillistCore

struct ToggleStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Task Status"
    static let description = IntentDescription("Set a task's status.")

    @Parameter(title: "Task") var task: TaskEntity
    @Parameter(title: "Status") var status: StatusAppEnum

    static var parameterSummary: some ParameterSummary {
        Summary("Set \(\.$task) to \(\.$status)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let persistence = try await IntentSupport.makePersistence()
        try await CLIBridge.StatusHandler.run(
            token: task.id.uuidString,
            to: status.coreStatus,
            note: nil,
            persistence: persistence
        )
        await WidgetRefresh.refreshAfterMutation(persistence: persistence)
        return .result()
    }
}
