import AppIntents
import Foundation
import LillistCore

struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Task"
    static let description = IntentDescription("Create a new task in Lillist.")
    static let openAppWhenRun = false

    /// Required so Siri/Shortcuts prompts for the title when a trigger phrase
    /// carries no inline value (e.g. plain "Add to Lillist"). Inline-capture
    /// phrases fill it directly when dictation provides the rest of the
    /// utterance.
    @Parameter(title: "Title", requestValueDialog: "What's the task?")
    var taskTitle: String
    @Parameter(title: "Deadline") var deadline: Date?
    @Parameter(title: "Tags") var tags: [String]?
    @Parameter(title: "Notes") var notes: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$taskTitle) to Lillist") {
            \.$deadline
            \.$tags
            \.$notes
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<TaskEntity> & ProvidesDialog {
        // Re-request if the spoken/typed title is blank after trimming, so a
        // dictation that captured only whitespace doesn't create an
        // empty-titled task (TaskStore.create would reject it anyway).
        guard let title = AddTaskInput.normalizedTitle(taskTitle) else {
            throw $taskTitle.needsValueError("What's the task?")
        }
        let persistence = try await IntentSupport.makePersistence()
        let id = try await CLIBridge.AddHandler.run(
            title: title,
            notes: notes ?? "",
            startToken: nil,
            deadlineToken: nil,
            tagNames: tags ?? [],
            parentToken: nil,
            statusToken: nil,
            persistence: persistence,
            diagnosticLog: await IntentSupport.diagnosticLog(),
            now: Date(),
            calendar: .current
        )
        if let deadline {
            let taskStore = TaskStore(persistence: persistence)
            try await taskStore.update(id: id) { draft in
                draft.deadline = deadline
                draft.deadlineHasTime = true
            }
        }
        let record = try await TaskStore(persistence: persistence).fetch(id: id)
        return .result(value: TaskEntity(record), dialog: "Added \(title) to Lillist.")
    }
}
