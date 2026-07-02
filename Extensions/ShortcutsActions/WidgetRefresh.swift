import Foundation
import WidgetKit

import LillistCore

/// Rebuilds the widget snapshot cache and reloads widget timelines after an
/// intent mutates the store.
///
/// The App Intents extension runs in its own process, so the main app's
/// `NSPersistentStoreRemoteChange` observer won't fire while the app is
/// backgrounded — each mutating intent refreshes widgets itself. Reuses the
/// intent's already-open `PersistenceController` (no second gate consult).
enum WidgetRefresh {
    static func refreshAfterMutation(persistence: PersistenceController) async {
        guard let snapshotStore = WidgetSnapshotStore(appGroupID: IntentSupport.appGroupID) else { return }
        let builder = WidgetSnapshotBuilder(
            smartFilterStore: SmartFilterStore(persistence: persistence),
            snapshotStore: snapshotStore
        )
        await builder.regenerate()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
