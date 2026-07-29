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
        // X8: route through the scheduler's addNudge (persist + reconcile in
        // one call, matching the app-level API) instead of the spec store
        // directly — a nudge added from Shortcuts previously persisted the
        // NotificationSpec row but never installed a UNNotificationRequest,
        // so it silently never fired unless the main app happened to
        // reconcile it later.
        let scheduler = try await IntentSupport.makeNotificationScheduler(persistence: persistence)
        _ = try await scheduler.addNudge(taskID: task.id, fireDate: fireAt)
        await WidgetRefresh.refreshAfterMutation(persistence: persistence)
        return .result()
    }
}
