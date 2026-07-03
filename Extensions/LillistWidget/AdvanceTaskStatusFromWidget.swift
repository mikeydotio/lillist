import AppIntents
import WidgetKit

import LillistCore
import LillistUI

/// Advances a task's status one step straight from the widget — the same
/// forward-only cycle the app's task rows use (`StatusCycler.nextOnClick`:
/// todo → started → closed, blocked → started, closed is terminal). Rebuilds the
/// snapshot cache + reloads timelines so the row reflects the change (and, once
/// closed, sinks to the bottom) immediately. Not shown in the Shortcuts app —
/// it's a widget-interaction intent, not a user action.
struct AdvanceTaskStatusFromWidget: AppIntent {
    static let title: LocalizedStringResource = "Advance Task Status"
    static let isDiscoverable = false

    @Parameter(title: "Task ID")
    var taskID: String

    init() {}

    init(taskID: String) {
        self.taskID = taskID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskID) else { return .result() }
        let persistence = try await WidgetIntentSupport.makePersistence()

        let taskStore = TaskStore(persistence: persistence)
        let current = try await taskStore.fetch(id: id)
        let next = StatusCycler.nextOnClick(from: current.status)
        if next != current.status {
            try await taskStore.transition(id: id, to: next)
        }

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
