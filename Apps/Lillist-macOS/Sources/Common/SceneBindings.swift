import SwiftUI
import LillistUI

/// Scene-level state bindings owned by `LillistApp` and consumed by the
/// macOS main-window container (`MacTasksView`) and the command menu.
/// Mirrors the iOS app's `SceneBindings` so the shared `TasksScreen`
/// presenter is fed the same way on both platforms:
///
/// - `isQuickCapturePresentedBinding`: drives the in-window unified
///   editor's new-capture trigger from both `LillistCommands` (⌘N) and
///   the bottom-trailing FAB.
/// - `sortBinding`: `@AppStorage("lillist.macos.sort")`-backed sort
///   selection threaded down to `MacTasksView`.
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
