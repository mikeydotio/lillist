import SwiftUI
import LillistCore
import LillistUI

struct TaskDetailView: View {
    @Environment(AppEnvironment.self) private var env
    let taskID: UUID

    @State private var record: TaskStore.TaskRecord?
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var start: Date?
    @State private var deadline: Date?
    @State private var showFollowUpForm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let r = record {
                    DetailHeaderView(
                        title: $title,
                        status: r.status,
                        tagNames: [],
                        start: $start,
                        deadline: $deadline,
                        onStatusMenu: { s in Task { await transition(to: s) } }
                    )
                    RecurrenceFieldPlaceholderView().padding(.horizontal)
                    if showFollowUpForm {
                        FollowUpFormView(
                            blockedTaskID: r.id,
                            parentTitle: title,
                            onCommit: { showFollowUpForm = false },
                            onDismiss: { showFollowUpForm = false }
                        )
                        .padding(.horizontal)
                    }
                    NotesEditorView(markdown: $notes)
                    SubtaskOutlineView(parentID: r.id)
                    JournalStreamView(taskID: r.id)
                } else {
                    ProgressView().padding()
                }
            }
        }
        .task(id: taskID) { await load() }
        .onChange(of: title) { _, new in Task { try? await env.taskStore.update(id: taskID) { $0.title = new } } }
        .onChange(of: notes) { _, new in Task { try? await env.taskStore.update(id: taskID) { $0.notes = new } } }
        .onChange(of: start) { _, new in Task { try? await env.taskStore.update(id: taskID) { $0.start = new } } }
        .onChange(of: deadline) { _, new in Task { try? await env.taskStore.update(id: taskID) { $0.deadline = new } } }
    }

    private func load() async {
        guard let r = try? await env.taskStore.fetch(id: taskID) else { return }
        record = r
        title = r.title
        notes = r.notes
        start = r.start
        deadline = r.deadline
        showFollowUpForm = (r.status == .blocked)
    }

    private func transition(to s: Status) async {
        try? await env.taskStore.transition(id: taskID, to: s)
        if s == .blocked { showFollowUpForm = true } else { showFollowUpForm = false }
        await load()
    }
}
