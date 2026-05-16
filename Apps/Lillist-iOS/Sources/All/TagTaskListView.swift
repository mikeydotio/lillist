import SwiftUI
import LillistCore
import LillistUI

/// Tasks associated with a single tag (descendants implicit, mirroring
/// Plan 7's macOS tag selection behavior).
struct TagTaskListView: View {
    let tagID: UUID
    @Environment(AppEnvironment.self) private var env

    @State private var tagName: String = "Tag"
    @State private var results: [TaskStore.TaskRecord] = []
    @State private var loadError: String?

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView(
                    "Could not load tasks",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else if results.isEmpty {
                ContentUnavailableView(
                    "No tasks for \(tagName)",
                    systemImage: "tag",
                    description: Text("Tag a task with #\(tagName) to see it here.")
                )
            } else {
                List {
                    ForEach(results, id: \.id) { record in
                        NavigationLink(value: record.id) {
                            TaskRowView(
                                task: record,
                                tagNames: [tagName],
                                onStatusClick: { Task { await cycle(record) } },
                                onStatusLongPress: {}
                            )
                        }
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
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(tagName)
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
            let tag = try await env.tagStore.fetch(id: tagID)
            tagName = tag.name
            results = try await env.taskStore.tasks(
                forTag: tagID,
                includeDescendants: true,
                sort: .deadline,
                ascending: true
            )
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
