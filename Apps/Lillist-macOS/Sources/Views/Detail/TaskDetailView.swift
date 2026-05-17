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
    @State private var recurrenceViewModel = RecurrenceEditorViewModel(rule: nil)
    @State private var showingRecurrenceEditor = false

    var body: some View {
        Form {
            if let r = record {
                Section {
                    TitleRow(title: $title, status: r.status, onStatusMenu: { s in
                        Task { await transition(to: s) }
                    })
                }

                Section("Dates") {
                    DatePicker("Start", selection: Binding(
                        get: { start ?? Date() }, set: { start = $0 }
                    ), displayedComponents: [.date])
                    DatePicker("Deadline", selection: Binding(
                        get: { deadline ?? Date() }, set: { deadline = $0 }
                    ), displayedComponents: [.date])
                }

                Section("Recurrence") {
                    recurrenceRow
                }

                if showFollowUpForm {
                    Section("Follow-up") {
                        FollowUpFormView(
                            blockedTaskID: r.id,
                            parentTitle: title,
                            onCommit: { showFollowUpForm = false },
                            onDismiss: { showFollowUpForm = false }
                        )
                    }
                }

                Section("Notes") {
                    NotesEditorView(markdown: $notes)
                }

                Section("Subtasks") {
                    SubtaskOutlineView(parentID: r.id)
                }

                Section("Journal") {
                    JournalStreamView(taskID: r.id)
                }
            } else {
                ProgressView()
            }
        }
        .formStyle(.grouped)
        .task(id: taskID) { await load() }
        .onChange(of: title) { _, new in Task { try? await env.taskStore.update(id: taskID) { $0.title = new } } }
        .onChange(of: notes) { _, new in Task { try? await env.taskStore.update(id: taskID) { $0.notes = new } } }
        .onChange(of: start) { _, new in Task { try? await env.taskStore.update(id: taskID) { $0.start = new } } }
        .onChange(of: deadline) { _, new in Task { try? await env.taskStore.update(id: taskID) { $0.deadline = new } } }
        .sheet(isPresented: $showingRecurrenceEditor) {
            RecurrenceEditorView(
                viewModel: $recurrenceViewModel,
                onCommit: { rule in
                    Task { await commitRecurrence(rule) }
                    showingRecurrenceEditor = false
                },
                onCancel: { showingRecurrenceEditor = false }
            )
            .frame(minWidth: 420, minHeight: 480)
        }
    }

    @ViewBuilder
    private var recurrenceRow: some View {
        HStack {
            Image(systemName: "repeat")
                .foregroundStyle(.secondary)
            Text(currentRecurrenceSummary)
                .foregroundStyle(.secondary)
            Spacer()
            Button(recurrenceViewModel.repeats ? "Edit…" : "Add…") {
                showingRecurrenceEditor = true
            }
        }
        .font(.callout)
    }

    private var currentRecurrenceSummary: String {
        recurrenceViewModel.humanSummary
    }

    private func load() async {
        guard let r = try? await env.taskStore.fetch(id: taskID) else { return }
        record = r
        title = r.title
        notes = r.notes
        start = r.start
        deadline = r.deadline
        showFollowUpForm = (r.status == .blocked)
        if let seriesID = r.seriesID,
           let series = try? await env.seriesStore.fetch(id: seriesID) {
            recurrenceViewModel = RecurrenceEditorViewModel(rule: series.rule)
        } else {
            recurrenceViewModel = RecurrenceEditorViewModel(rule: nil)
        }
    }

    private func transition(to s: Status) async {
        try? await env.taskStore.transition(id: taskID, to: s)
        if s == .blocked { showFollowUpForm = true } else { showFollowUpForm = false }
        await load()
    }

    private func commitRecurrence(_ rule: RecurrenceRule?) async {
        guard let r = record else { return }
        do {
            if let rule {
                if let seriesID = r.seriesID {
                    try await env.seriesStore.update(id: seriesID, rule: rule)
                } else {
                    _ = try await env.seriesStore.create(fromSeedTask: taskID, rule: rule)
                }
            } else if let seriesID = r.seriesID {
                try await env.seriesStore.delete(id: seriesID)
            }
            await load()
        } catch {
            // Surface in a banner later; failure leaves state unchanged.
        }
    }

    private struct TitleRow: View {
        @Binding var title: String
        let status: Status
        var onStatusMenu: (Status) -> Void

        var body: some View {
            HStack {
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.title3.bold())
                Menu {
                    ForEach(Status.allCases, id: \.self) { s in
                        Button { onStatusMenu(s) } label: {
                            Label(StatusGlyph.accessibilityLabel(for: s),
                                  systemImage: StatusGlyph.symbol(for: s))
                        }
                    }
                } label: {
                    Label(StatusGlyph.accessibilityLabel(for: status),
                          systemImage: StatusGlyph.symbol(for: status))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(.quaternary))
                }
                .menuStyle(.borderlessButton)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Status: \(StatusGlyph.accessibilityLabel(for: status))")
                .fixedSize()
            }
        }
    }
}
