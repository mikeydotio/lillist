import AppIntents
import WidgetKit

import LillistCore

/// Marks a task closed directly from the widget (tapping its status circle).
/// Reuses the shared `CLIBridge.StatusHandler`, then rebuilds the snapshot cache
/// + reloads timelines so the row reflects the change immediately. Not shown in
/// the Shortcuts app — it's a widget-interaction intent, not a user action.
struct CompleteTaskFromWidget: AppIntent {
    static let title: LocalizedStringResource = "Complete Task"
    static let isDiscoverable = false

    @Parameter(title: "Task ID")
    var taskID: String

    init() {}

    init(taskID: String) {
        self.taskID = taskID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let persistence = try await WidgetIntentSupport.makePersistence()
        try await CLIBridge.StatusHandler.run(
            token: taskID,
            to: .closed,
            note: nil,
            persistence: persistence
        )
        if let store = WidgetSnapshotStore(appGroupID: WidgetIntentSupport.appGroupID) {
            await WidgetSnapshotBuilder(
                smartFilterStore: SmartFilterStore(persistence: persistence),
                snapshotStore: store
            ).regenerate()
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
