import SwiftUI
import LillistCore
import LillistUI

struct FilterResultsView: View {
    let filterID: UUID
    @Environment(AppEnvironment.self) private var env
    @Environment(\.taskSelectionBinding) private var taskSelection

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
                listBody
            }
        }
        .navigationTitle(filterName)
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

    @ViewBuilder
    private var listBody: some View {
        if let taskSelection {
            List(selection: taskSelection) {
                ForEach(results, id: \.id) { record in
                    row(record).tag(record.id)
                }
            }
            .listStyle(.plain)
        } else {
            List {
                ForEach(results, id: \.id) { record in
                    NavigationLink(value: record.id) { row(record) }
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func row(_ record: TaskStore.TaskRecord) -> some View {
        TaskRowView(
            task: record,
            tagNames: [],
            onStatusClick: { Task { await cycle(record) } },
            onStatusLongPress: {}
        )
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button("Complete") {
                Task { try? await env.taskStore.transition(id: record.id, to: .closed); await reload() }
            }.tint(.green)
        }
        .swipeActions(edge: .trailing) {
            Button("Snooze") { Task { await snooze(record) } }
            Button(role: .destructive) {
                Task { try? await env.taskStore.softDelete(id: record.id); await reload() }
            } label: { Text("Delete") }
        }
        .contextMenu {
            Menu("Change status") {
                ForEach(Status.allCases, id: \.self) { s in
                    Button(StatusGlyph.accessibilityLabel(for: s)) {
                        Task { try? await env.taskStore.transition(id: record.id, to: s); await reload() }
                    }
                }
            }
            Button(role: .destructive) {
                Task { try? await env.taskStore.softDelete(id: record.id); await reload() }
            } label: { Text("Delete") }
        }
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

    private func snooze(_ record: TaskStore.TaskRecord) async {
        let cal = Calendar.current
        let base = record.deadline ?? Date()
        guard let newDeadline = cal.date(byAdding: .day, value: 1, to: base) else { return }
        try? await env.taskStore.update(id: record.id) { mut in
            mut.deadline = newDeadline
        }
        await reload()
    }

    private func cycle(_ record: TaskStore.TaskRecord) async {
        let next = StatusCycler.nextOnClick(from: record.status)
        try? await env.taskStore.transition(id: record.id, to: next)
        await reload()
    }
}
