import SwiftUI
import LillistCore
import LillistUI

struct SubtaskOutlineView: View {
    @Environment(AppEnvironment.self) private var env
    let parentID: UUID
    @State private var children: [TaskStore.TaskRecord] = []
    @State private var newTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Subtasks").font(.headline)
            ForEach(children, id: \.id) { c in
                TaskRowView(task: c, tagNames: [],
                            onStatusClick: { Task { try? await cycle(c) } },
                            onStatusLongPress: { /* menu handled at row level */ })
            }
            HStack {
                Image(systemName: "plus")
                TextField("Add subtask", text: $newTitle)
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await addSubtask() } }
            }
            .padding(.vertical, 4)
        }
        .padding(.horizontal)
        .task { await refresh() }
        .onChange(of: parentID) { _, _ in Task { await refresh() } }
    }

    private func refresh() async {
        children = (try? await env.taskStore.children(of: parentID)) ?? []
    }

    private func addSubtask() async {
        let t = newTitle.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        _ = try? await env.taskStore.create(title: t, parent: parentID)
        newTitle = ""
        await refresh()
    }

    private func cycle(_ rec: TaskStore.TaskRecord) async throws {
        let next = StatusCycler.nextOnClick(from: rec.status)
        try await env.taskStore.transition(id: rec.id, to: next)
        await refresh()
    }
}
