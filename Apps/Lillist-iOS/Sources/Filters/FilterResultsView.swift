import SwiftUI
import LillistCore
import LillistUI

struct FilterResultsView: View {
    let filterID: UUID
    @Environment(AppEnvironment.self) private var env

    @State private var filterName: String = "Filter"
    @State private var results: [TaskStore.TaskRecord] = []
    @State private var loadError: String?

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView(
                    "Filter not found",
                    systemImage: "questionmark.folder",
                    description: Text(loadError)
                )
            } else if results.isEmpty {
                ContentUnavailableView(
                    "No matching tasks",
                    systemImage: "magnifyingglass"
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
        .navigationTitle(filterName)
        .navigationDestination(for: UUID.self) { id in
            TaskDetailView(taskID: id)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        do {
            let filter = try await env.smartFilterStore.fetch(id: filterID)
            filterName = filter.name
            results = try await env.smartFilterStore.evaluate(id: filterID)
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
