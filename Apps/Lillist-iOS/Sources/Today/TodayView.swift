import SwiftUI
import LillistCore
import LillistUI

// MARK: - Accessibility audit (Plan 8, Task 26)
// - Interactive elements use TaskRowView (already accessibilityElement-combined
//   with a status-spelled-out label and trait) and ContentUnavailableView
//   (system-provided VoiceOver labels).
// - No fixed font sizes; relies on system text styles (Dynamic Type).
// - Sync indicator badge exposes localized state via SyncStatusBadge.
// - No `preferredColorScheme` override; semantic colors only.

/// Built-in "Today" smart-filter surface. Fetches the user's "Today" filter
/// (installed by `LillistCore.DefaultsInstaller`) and renders its results
/// with the shared `TaskRowView`. Design Section 7 iOS subsection.
struct TodayView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.taskSelectionBinding) private var taskSelection

    @State private var results: [TaskStore.TaskRecord] = []
    @State private var loadError: String?

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView(
                    "Could not load Today",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else if results.isEmpty {
                ContentUnavailableView(
                    "Nothing for today",
                    systemImage: "sparkles",
                    description: Text("Tasks with a start or deadline of today show up here.")
                )
            } else {
                listBody
            }
        }
        .navigationTitle("Today")
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
                    row(record)
                        .tag(record.id)
                }
            }
            .listStyle(.plain)
        } else {
            List {
                ForEach(results, id: \.id) { record in
                    NavigationLink(value: record.id) {
                        row(record)
                    }
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
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing) {
            Button("Snooze") {
                Task { await snooze(record) }
            }
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
            let filter = try await env.smartFilterStore.fetch(byName: "Today")
            results = try await env.smartFilterStore.evaluate(id: filter.id)
            loadError = nil
        } catch {
            loadError = "\(error)"
            results = []
        }
    }

    private func snooze(_ record: TaskStore.TaskRecord) async {
        // v1 snooze: push deadline forward by one day. Uses
        // Calendar.date(byAdding:) per the CLAUDE.md rule.
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
