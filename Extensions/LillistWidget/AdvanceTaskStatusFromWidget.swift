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

        // X8: wired so completing a task from the widget actually cancels
        // its pending reminder — previously this bare TaskStore had no
        // scheduler, so the reminder kept firing after the task showed
        // closed in the widget. Built directly off the already-resolved
        // `persistence` (rather than `WidgetIntentSupport.makeTaskStore()`)
        // so this function resolves the store exactly once.
        let taskStore = TaskStore(persistence: persistence)
        taskStore.notificationScheduler = try await WidgetIntentSupport.makeNotificationScheduler(persistence: persistence)
        let current = try await taskStore.fetch(id: id)
        let next = StatusCycler.nextOnClick(from: current.status)
        if next != current.status {
            try await taskStore.transition(id: id, to: next)
        }

        if let store = WidgetSnapshotStore(appGroupID: WidgetIntentSupport.appGroupID) {
            await WidgetSnapshotBuilder(
                smartFilterStore: SmartFilterStore(persistence: persistence),
                taskLookup: taskStore,
                snapshotStore: store
            ).regenerate()
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
