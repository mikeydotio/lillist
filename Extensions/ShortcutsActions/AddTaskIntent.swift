import AppIntents
import Foundation
import LillistCore

struct AddTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Task"
    static var description = IntentDescription("Create a new task in Lillist.")
    static var openAppWhenRun = false

    @Parameter(title: "Title") var taskTitle: String
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
    func perform() async throws -> some IntentResult & ReturnsValue<TaskEntity> {
        let persistence = try await IntentSupport.makePersistence()
        let id = try await CLIBridge.AddHandler.run(
            title: taskTitle,
            notes: notes ?? "",
            startToken: nil,
            deadlineToken: nil,
            tagNames: tags ?? [],
            parentToken: nil,
            statusToken: nil,
            persistence: persistence,
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
        return .result(value: TaskEntity(record))
    }
}
