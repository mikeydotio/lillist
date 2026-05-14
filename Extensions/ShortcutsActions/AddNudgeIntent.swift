import AppIntents
import Foundation
import LillistCore

struct AddNudgeIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Nudge"
    static let description = IntentDescription("Schedule a one-off notification on a task.")

    @Parameter(title: "Task") var task: TaskEntity
    @Parameter(title: "Fire At") var fireAt: Date

    static var parameterSummary: some ParameterSummary {
        Summary("Nudge \(\.$task) at \(\.$fireAt)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let persistence = try await IntentSupport.makePersistence()
        // NudgeHandler takes a `atToken` string (date DSL). The intent gives
        // us a concrete Date; route it through the spec store directly with
        // the same shape NudgeHandler uses, bypassing the DSL parser.
        let specs = NotificationSpecStore(persistence: persistence)
        _ = try await specs.add(
            taskID: task.id,
            kind: .nudge,
            offsetMinutes: nil,
            fireDate: fireAt
        )
        return .result()
    }
}
