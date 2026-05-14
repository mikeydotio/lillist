import SwiftUI
import LillistCore
import LillistUI

// MARK: - Accessibility audit (Plan 8, Task 26)
// - Detail header uses `accessibilityElement(children: .combine)` so VoiceOver
//   reads title + status + deadline as one element with `.isHeader` trait.
// - Each tab body sets `.accessibilityLabel("…")` on its container.
// - TabView(.page) exposes page-index dots; the system labels them.
// - No fixed font sizes; semantic colors only.

/// Task detail surface. Notes / Subtasks / Journal / Attachments are tabs
/// in a `TabView(.page)` to keep the navigation stack shallow.
/// Design Section 7 iOS subsection.
struct TaskDetailView: View {
    let taskID: UUID
    @Environment(AppEnvironment.self) private var env

    @State private var record: TaskStore.TaskRecord?
    @State private var loadError: String?
    @State private var selection: Tab = .notes

    enum Tab: Hashable { case notes, subtasks, journal, attachments }

    var body: some View {
        Group {
            if let record {
                VStack(spacing: 0) {
                    TaskDetailHeader(task: record)
                    TabView(selection: $selection) {
                        TaskNotesTab(taskID: record.id, initialText: record.notes)
                            .tag(Tab.notes)
                        TaskSubtasksTab(taskID: record.id)
                            .tag(Tab.subtasks)
                        TaskJournalTab(taskID: record.id)
                            .tag(Tab.journal)
                        TaskAttachmentsTab(taskID: record.id)
                            .tag(Tab.attachments)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                }
            } else if let loadError {
                ContentUnavailableView(
                    "Could not load task",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else {
                ProgressView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(record?.title ?? "")
        .task { await reload() }
    }

    private func reload() async {
        do {
            record = try await env.taskStore.fetch(id: taskID)
            loadError = nil
        } catch {
            loadError = "\(error)"
        }
    }
}

private struct TaskDetailHeader: View {
    let task: TaskStore.TaskRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.title)
                .font(.title3)
                .strikethrough(task.status == .closed)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 8) {
                Label(statusLabel, systemImage: statusGlyph)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let deadline = task.deadline {
                    Label(
                        deadline.formatted(date: .abbreviated, time: task.deadlineHasTime ? .shortened : .omitted),
                        systemImage: "calendar"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var statusLabel: String {
        switch task.status {
        case .todo: return "To do"
        case .started: return "Started"
        case .blocked: return "Blocked"
        case .closed: return "Closed"
        }
    }

    private var statusGlyph: String {
        switch task.status {
        case .todo: return "circle"
        case .started: return "circle.lefthalf.filled"
        case .blocked: return "exclamationmark.octagon"
        case .closed: return "checkmark.circle.fill"
        }
    }
}
