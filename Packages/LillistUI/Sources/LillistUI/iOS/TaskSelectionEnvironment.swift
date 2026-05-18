#if os(iOS)
import SwiftUI

/// Environment key for the iPad three-column layout's "selected task"
/// binding. The iOS app's `SplitShell` provides the binding via
/// `.environment(\.taskSelectionBinding, $taskSelection)`; leaf
/// task-list screens read it to decide whether to drive a third-column
/// detail (binding non-nil → `List(selection:)`) or to push onto the
/// existing NavigationStack (binding nil → iPhone compact / TabShell).
///
/// An environment-value indirection (rather than a threaded `init`
/// parameter) lets intermediate shells like `AllTagsScreen` →
/// `TagTaskListView` and `FiltersListScreen` → `FilterResultsView`
/// skip the binding they never use.
public struct TaskSelectionBindingKey: EnvironmentKey {
    public static let defaultValue: Binding<UUID?>? = nil
}

public extension EnvironmentValues {
    var taskSelectionBinding: Binding<UUID?>? {
        get { self[TaskSelectionBindingKey.self] }
        set { self[TaskSelectionBindingKey.self] = newValue }
    }
}
#endif
