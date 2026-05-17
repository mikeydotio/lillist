import SwiftUI

/// Environment key for the iPad three-column layout's "selected task"
/// binding (Plan 16 Task 8). `SplitShell` provides the binding via
/// `.environment(\.taskSelectionBinding, $taskSelection)`; leaf
/// task-list views read it to decide whether to drive a third-column
/// detail (binding non-nil → `List(selection:)`) or to push onto the
/// existing NavigationStack (binding nil → iPhone compact / TabShell).
///
/// We use an environment-value indirection rather than threading an
/// optional binding through every list view's `init` because
/// `AllTagsView` → `TagTaskListView` and `FiltersListView` →
/// `FilterResultsView` are two-level navigations whose intermediate
/// shells (AllTagsView, FiltersListView) don't display tasks at all —
/// they'd otherwise need a pass-through binding they never use. The
/// environment lets the binding skip those intermediate layers.
struct TaskSelectionBindingKey: EnvironmentKey {
    static let defaultValue: Binding<UUID?>? = nil
}

extension EnvironmentValues {
    var taskSelectionBinding: Binding<UUID?>? {
        get { self[TaskSelectionBindingKey.self] }
        set { self[TaskSelectionBindingKey.self] = newValue }
    }
}
