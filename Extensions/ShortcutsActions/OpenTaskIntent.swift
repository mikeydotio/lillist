import AppIntents

struct OpenTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Task"
    static var description = IntentDescription("Open a task in Lillist.")
    static var openAppWhenRun = true

    @Parameter(title: "Task") var task: TaskEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$task)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenTaskInAppIntent(taskID: task.id.uuidString))
    }
}

/// Hidden helper intent that the main app handles to scroll to the right
/// task. Marked `isDiscoverable = false` so it doesn't surface in Shortcuts.
struct OpenTaskInAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Task In App"
    static var isDiscoverable = false

    @Parameter(title: "Task ID") var taskID: String

    func perform() async throws -> some IntentResult {
        .result()
    }
}
