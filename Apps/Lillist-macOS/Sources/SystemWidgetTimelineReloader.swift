import WidgetKit

import LillistCore

/// The app target's one `WidgetTimelineReloading` conformance — the only
/// place in this call chain that imports WidgetKit. `WidgetRefreshController`
/// (LillistCore) owns detecting a change and rebuilding the snapshot cache;
/// this just tells the system to re-render from the fresh JSON.
struct SystemWidgetTimelineReloader: WidgetTimelineReloading {
    func reloadAllTimelines() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
