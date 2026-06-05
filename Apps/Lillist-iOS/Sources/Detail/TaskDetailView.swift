import SwiftUI
import LillistCore
import LillistUI

// MARK: - Accessibility audit
// - Detail header uses `accessibilityElement(children: .combine)` so VoiceOver
//   reads title + status + deadline as one element with `.isHeader` trait.
// - Each tab body sets `.accessibilityLabel("…")` on its container.
// - The segmented Picker carries an explicit "Detail section" a11y label.
// - No fixed font sizes; semantic colors only.

/// Task detail surface. Notes / Subtasks / Journal / Attachments are
/// labeled named sections behind a segmented `Picker` for one-tap
/// access — mirrors Reminders, Things 3, and Todoist.
/// Design Section 7 iOS subsection.
struct TaskDetailView: View {
    let taskID: UUID
    @Environment(AppEnvironment.self) private var env

    @State private var record: TaskStore.TaskRecord?
    @State private var loadError: String?
    @SceneStorage("taskDetailTab") private var selection: Tab = .notes
    @State private var seriesRule: RecurrenceRule?
    @State private var showingRecurrenceSheet = false

    enum Tab: String, Hashable { case notes, subtasks, journal, attachments }

    var body: some View {
        Group {
            if let record {
                VStack(spacing: 0) {
                    TaskDetailHeader(task: record)
                    Picker("Section", selection: $selection) {
                        Text("Notes").tag(Tab.notes)
                        Text("Subtasks").tag(Tab.subtasks)
                        Text("Journal").tag(Tab.journal)
                        Text("Attachments").tag(Tab.attachments)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, LillistSpacing.s)
                    .accessibilityLabel(String(localized: "Detail section"))
                    Group {
                        switch selection {
                        case .notes:
                            TaskNotesTab(taskID: record.id, initialText: record.notes)
                        case .subtasks:
                            TaskSubtasksTab(taskID: record.id)
                        case .journal:
                            TaskJournalTab(taskID: record.id)
                        case .attachments:
                            TaskAttachmentsTab(taskID: record.id)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .navigationBarTitleDisplayMode(.large)
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
                .accessibilityLabel(seriesRule == nil
                    ? String(localized: "Add recurrence")
                    : String(localized: "Edit recurrence"))
                .accessibilityValue(seriesRuleSummary)
            }
        }
        .sheet(isPresented: $showingRecurrenceSheet) {
            RecurrenceSheet(
                taskID: taskID,
                initialRule: seriesRule,
                initialSeriesID: record?.seriesID,
                initialAnchorDate: record?.start ?? record?.deadline,
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
        RecurrenceSummaryFormatter.string(for: RecurrenceEditorViewModel(rule: seriesRule).summary)
    }
}

private struct TaskDetailHeader: View {
    let task: TaskStore.TaskRecord

    var body: some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityCombinedLabel)
    }

    /// Combine status + deadline into one VoiceOver label since the
    /// title now lives in the nav bar where the system announces it as
    /// the screen heading.
    private var accessibilityCombinedLabel: String {
        let statusLabel = StatusGlyph.accessibilityLabel(for: task.status)
        if let deadline = task.deadline {
            let formatted = deadline.formatted(
                date: .abbreviated,
                time: task.deadlineHasTime ? .shortened : .omitted
            )
            return "\(statusLabel), due \(formatted)"
        }
        return statusLabel
    }
}
