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
    @State private var seriesRule: RecurrenceRule?
    @State private var showingRecurrenceSheet = false

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingRecurrenceSheet = true
                } label: {
                    HStack(spacing: LillistSpacing.xs) {
                        Image(systemName: seriesRule == nil ? "repeat" : "repeat.circle.fill")
                        Text(seriesRuleSummary)
                            .font(LillistTypography.caption)
                    }
                }
                .accessibilityLabel(seriesRule == nil ? "Add recurrence" : "Edit recurrence")
                .accessibilityValue(seriesRuleSummary)
            }
        }
        .sheet(isPresented: $showingRecurrenceSheet) {
            RecurrenceSheet(
                taskID: taskID,
                initialRule: seriesRule,
                initialSeriesID: record?.seriesID,
                onClose: {
                    showingRecurrenceSheet = false
                    Task { await reload() }
                }
            )
        }
        .task { await reload() }
    }

    private func reload() async {
        do {
            record = try await env.taskStore.fetch(id: taskID)
            if let sid = record?.seriesID {
                seriesRule = (try? await env.seriesStore.fetch(id: sid))?.rule
            } else {
                seriesRule = nil
            }
            loadError = nil
        } catch {
            loadError = "\(error)"
        }
    }

    private var seriesRuleSummary: String {
        RecurrenceEditorViewModel(rule: seriesRule).humanSummary
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
                Label(
                    StatusGlyph.accessibilityLabel(for: task.status),
                    systemImage: StatusGlyph.symbol(for: task.status)
                )
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
}
