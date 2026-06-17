import SwiftUI
import LillistCore
import LillistUI

/// Top-level iOS shell. A single primary `TasksView` in a `NavigationStack`.
///
/// The former `NavigationSplitView` + detail column were retired with the
/// unified task editor: tapping a task no longer pushes a `TaskDetailView`,
/// it opens the singleton floating editor (`TaskEditorHost`, attached inside
/// `TasksView`). The `NavigationStack` remains for the toolbar/title chrome
/// and any future pushes.
struct RootShell: View {
    var body: some View {
        NavigationStack {
            TasksView()
        }
    }
}
