import Foundation
import WidgetKit

import LillistCore

/// Owns widget-snapshot regeneration for the app process: coalesces a burst of
/// data changes into one snapshot rebuild + one `WidgetCenter` reload.
///
/// Lives in the app target (not LillistCore) because it imports WidgetKit, which
/// the headless `lillist-cli` — a LillistCore client — can't link. LillistCore
/// only ever *writes* snapshot JSON (``WidgetSnapshotBuilder``); the reload is an
/// app/extension concern.
@MainActor
final class WidgetRefreshCoordinator {
    private let builder: WidgetSnapshotBuilder
    private let debounce: Duration
    private var pending: Task<Void, Never>?

    /// Returns `nil` when the App Group container is unavailable (so there is
    /// nowhere to write snapshots) — callers then treat widgets as simply absent.
    init?(
        smartFilterStore: SmartFilterStore,
        appGroupID: String,
        debounce: Duration = .milliseconds(1500)
    ) {
        guard let snapshotStore = WidgetSnapshotStore(appGroupID: appGroupID) else { return nil }
        self.builder = WidgetSnapshotBuilder(smartFilterStore: smartFilterStore, snapshotStore: snapshotStore)
        self.debounce = debounce
    }

    /// Coalesce a burst of store changes: (re)start the debounce window, then
    /// regenerate all filters and reload every timeline when it elapses.
    func scheduleRefresh() {
        pending?.cancel()
        let builder = self.builder
        let debounce = self.debounce
        pending = Task {
            try? await Task.sleep(for: debounce)
            if Task.isCancelled { return }
            await builder.regenerate()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Regenerate immediately (no debounce). Used once at bootstrap to warm the
    /// cache so a freshly added widget renders without waiting for a change.
    func refreshNow() {
        pending?.cancel()
        let builder = self.builder
        pending = Task {
            await builder.regenerate()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
