import SwiftUI
import LillistCore
import LillistUI

/// Subtasks tab: lists `taskStore.children(of: taskID)` and lets the user add
/// a new subtask inline.
struct TaskSubtasksTab: View {
    let taskID: UUID
    @Environment(AppEnvironment.self) private var env

    @State private var children: [TaskStore.TaskRecord] = []
    @State private var newTitle: String = ""

    var body: some View {
        List {
            Section("Subtasks") {
                ForEach(children, id: \.id) { child in
                    NavigationLink(value: child.id) {
                        TaskRowView(
                            task: child,
                            tagNames: [],
                            onStatusClick: { Task { await cycle(child) } },
                            onStatusSet: { newStatus in Task { await setStatus(child, to: newStatus) } }
                        )
                    }
                }
                if children.isEmpty {
                    Text("No subtasks yet")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Add") {
                HStack {
                    TextField("New subtask", text: $newTitle)
                        .submitLabel(.done)
                        .onSubmit { Task { await create() } }
                    Button("Add") { Task { await create() } }
                        .disabled(newTitle.isEmpty)
                }
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
        .accessibilityLabel(String(localized: "Subtasks"))
    }

    private func reload() async {
        children = (try? await env.taskStore.children(of: taskID)) ?? []
    }

    private func create() async {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = try? await env.taskStore.create(title: trimmed, parent: taskID)
        newTitle = ""
        await reload()
    }

    private func cycle(_ record: TaskStore.TaskRecord) async {
        let next = StatusCycler.nextOnClick(from: record.status)
        try? await env.taskStore.transition(id: record.id, to: next)
        await reload()
    }

    private func setStatus(_ record: TaskStore.TaskRecord, to newStatus: Status) async {
        try? await env.taskStore.transition(id: record.id, to: newStatus)
        await reload()
    }
}
