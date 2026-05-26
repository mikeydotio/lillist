import SwiftUI
import LillistUI

/// Scene-level state bindings owned by `LillistApp` and consumed by
/// shells / commands deep in the view tree. The 3-tab restructure
/// replaced the previous tab/section selection plumbing with a single
/// primary `TasksView`; this file now carries only the two bindings
/// still in active use:
///
/// - `isQuickCapturePresentedBinding`: drives the Quick Capture sheet
///   from both `LillistCommands` (⌘⇧N) and the bottom-trailing FAB.
/// - `sortBinding`: `@AppStorage("lillist.ios.sort")`-backed sort
///   selection threaded down to `TasksView`.
struct IsQuickCapturePresentedBindingKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

struct SortBindingKey: EnvironmentKey {
    static let defaultValue: Binding<TasksSort> = .constant(.personalized)
}

extension EnvironmentValues {
    var isQuickCapturePresentedBinding: Binding<Bool> {
        get { self[IsQuickCapturePresentedBindingKey.self] }
        set { self[IsQuickCapturePresentedBindingKey.self] = newValue }
    }

    var sortBinding: Binding<TasksSort> {
        get { self[SortBindingKey.self] }
        set { self[SortBindingKey.self] = newValue }
    }
}
