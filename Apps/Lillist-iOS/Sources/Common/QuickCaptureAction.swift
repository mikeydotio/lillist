import SwiftUI

/// Environment key for "present Quick Capture" — surfaced by the shells
/// (TabShell, SplitShell) and consumed by empty-state CTAs deep in the
/// view tree (TodayView, AllTagsView, FiltersListView, FilterResultsView,
/// SearchView). Lets the CTA call into the same `isQuickCapturePresented`
/// state binding the shell already owns without threading a binding
/// through every screen.
struct QuickCaptureActionKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Void = {}
}

extension EnvironmentValues {
    var quickCaptureAction: @MainActor () -> Void {
        get { self[QuickCaptureActionKey.self] }
        set { self[QuickCaptureActionKey.self] = newValue }
    }
}
