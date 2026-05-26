import SwiftUI
import LillistCore
import LillistUI

/// Top-level iOS shell after the 3-tab restructure. A single primary
/// `TasksView` is hosted in a `NavigationSplitView(sidebar:detail:)`.
///
/// - On regular width (iPad), the user sees the tasks list in the
///   sidebar column and a task detail in the trailing column —
///   `NavigationLink(value:)` taps inside `TasksView` route to the
///   detail column via the `.navigationDestination(for: UUID.self)`
///   declared on the detail's `NavigationStack`.
/// - On compact width (iPhone), `NavigationSplitView` collapses to a
///   single-column stack and the same links push within it.
struct RootShell: View {
    var body: some View {
        NavigationSplitView {
            TasksView()
        } detail: {
            NavigationStack {
                detailPlaceholder
                    .navigationDestination(for: UUID.self) { id in
                        TaskDetailView(taskID: id)
                    }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var detailPlaceholder: some View {
        ContentUnavailableView(
            String(localized: "Select a task"),
            systemImage: "checklist",
            description: Text("Pick a task from the list to see its details.")
        )
    }
}
