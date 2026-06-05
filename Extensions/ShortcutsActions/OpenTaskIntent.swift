import AppIntents

/// Opens Lillist with a chosen task. The app currently has no AppIntents
/// deep-link surface to scroll to a specific task, so this intent's only
/// effect is to bring the app to the foreground (`openAppWhenRun`). The
/// task parameter is retained so the Shortcuts UI still lets the user pick
/// a task and so the surface is ready when in-app navigation lands.
struct OpenTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Task"
    static let description = IntentDescription("Open a task in Lillist.")
    static let openAppWhenRun = true

    @Parameter(title: "Task") var task: TaskEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$task)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}
