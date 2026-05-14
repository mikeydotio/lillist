import AppIntents
import LillistCore

struct AddNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Journal Note"
    static var description = IntentDescription("Add a note to a task's journal.")

    @Parameter(title: "Task") var task: TaskEntity
    @Parameter(title: "Body") var body: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add note to \(\.$task)") {
            \.$body
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let persistence = try await IntentSupport.makePersistence()
        _ = try await CLIBridge.NoteHandler.run(
            token: task.id.uuidString,
            body: body,
            persistence: persistence
        )
        return .result()
    }
}
