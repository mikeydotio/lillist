#if os(iOS)
import SwiftUI

/// Environment key for "present Quick Capture" — surfaced by the iOS
/// shells (`TabShell`, `SplitShell`) and consumed by empty-state CTAs
/// deep in the view tree (`TodayScreen`, `AllTagsScreen`,
/// `FiltersListScreen`, `FilterResultsView`, `SearchScreen`). Lets a
/// CTA call into the shell's `isQuickCapturePresented` state without
/// threading a binding through every screen.
public struct QuickCaptureActionKey: EnvironmentKey {
    public static let defaultValue: @MainActor () -> Void = {}
}

public extension EnvironmentValues {
    var quickCaptureAction: @MainActor () -> Void {
        get { self[QuickCaptureActionKey.self] }
        set { self[QuickCaptureActionKey.self] = newValue }
    }
}
#endif
