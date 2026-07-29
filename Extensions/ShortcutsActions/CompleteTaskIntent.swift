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
        // X8: without a scheduler, closing a task from Shortcuts left its
        // pending reminder(s) firing anyway — the transition itself is
        // correct, but nothing ever told the OS to cancel them.
        try await CLIBridge.StatusHandler.run(
            token: task.id.uuidString,
            to: .closed,
            note: nil,
            persistence: persistence,
            notificationScheduler: try await IntentSupport.makeNotificationScheduler(persistence: persistence)
        )
        await WidgetRefresh.refreshAfterMutation(persistence: persistence)
        return .result()
    }
}
