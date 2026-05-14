import AppIntents

struct OpenTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Task"
    static let description = IntentDescription("Open a task in Lillist.")
    static let openAppWhenRun = true

    @Parameter(title: "Task") var task: TaskEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$task)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        var inner = OpenTaskInAppIntent()
        inner.taskID = task.id.uuidString
        return .result(opensIntent: inner)
    }
}

/// Hidden helper intent that the main app handles to scroll to the right
/// task. Marked `isDiscoverable = false` so it doesn't surface in Shortcuts.
struct OpenTaskInAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Task In App"
    static let isDiscoverable = false

    @Parameter(title: "Task ID") var taskID: String

    init() {}

    func perform() async throws -> some IntentResult {
        .result()
    }
}
