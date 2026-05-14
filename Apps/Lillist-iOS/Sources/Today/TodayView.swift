import SwiftUI
import LillistCore
import LillistUI

// MARK: - Accessibility audit (Plan 8, Task 26)
// - Interactive elements use TaskRowView (already accessibilityElement-combined
//   with a status-spelled-out label and trait) and ContentUnavailableView
//   (system-provided VoiceOver labels).
// - No fixed font sizes; relies on system text styles (Dynamic Type).
// - Sync indicator badge exposes localized state via SyncStatusBadge.
// - No `preferredColorScheme` override; semantic colors only.

/// Built-in "Today" smart-filter surface. Fetches the user's "Today" filter
/// (installed by `LillistCore.DefaultsInstaller`) and renders its results
/// with the shared `TaskRowView`. Design Section 7 iOS subsection.
struct TodayView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var results: [TaskStore.TaskRecord] = []
    @State private var loadError: String?

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView(
                    "Could not load Today",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else if results.isEmpty {
                ContentUnavailableView(
                    "Nothing for today",
                    systemImage: "sparkles",
                    description: Text("Tasks with a start or deadline of today show up here.")
                )
            } else {
                List(results, id: \.id) { record in
                    NavigationLink(value: record.id) {
                        TaskRowView(
                            task: record,
                            tagNames: [],
                            onStatusClick: { Task { await cycle(record) } },
                            onStatusLongPress: { /* status menu lands in Task 13 */ }
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Today")
        .navigationDestination(for: UUID.self) { id in
            TaskDetailView(taskID: id)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SyncStatusBadge(indicator: env.syncMonitor.indicator)
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        do {
            let filter = try await env.smartFilterStore.fetch(byName: "Today")
            results = try await env.smartFilterStore.evaluate(id: filter.id)
            loadError = nil
        } catch {
            loadError = "\(error)"
            results = []
        }
    }

    private func cycle(_ record: TaskStore.TaskRecord) async {
        let next: Status
        switch record.status {
        case .todo:    next = .started
        case .started: next = .closed
        case .closed:  next = .todo
        case .blocked: next = .started
        }
        try? await env.taskStore.transition(id: record.id, to: next)
        await reload()
    }
}
