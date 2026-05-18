import SwiftUI
import LillistCore
import LillistUI

/// Thin wrapper around `LillistUI.TodayScreen`. Owns the live data
/// machinery — fetches the user's "Today" smart filter, holds the
/// loaded records as @State, mutates state via the swipe / context
/// actions — and forwards the rendered chrome to the shared
/// presentation in `TodayScreen`. Plan 20a Task 4a: composition lives
/// in `LillistUI` so the `IOSScreenTourTests` snapshot suite renders
/// the real screen instead of inline mocks.
struct TodayView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var results: [TaskStore.TaskRecord] = []
    @State private var loadError: String?

    var body: some View {
        TodayScreen(
            results: results,
            loadError: loadError,
            syncIndicator: env.syncMonitor.indicator,
            onRefresh: { await reload() },
            onStatusClick: { record in Task { await cycle(record) } },
            onStatusSet: { record, newStatus in
                Task { await setStatus(record, to: newStatus) }
            },
            onComplete: { record in
                Task {
                    try? await env.taskStore.transition(id: record.id, to: .closed)
                    await reload()
                }
            },
            onSnooze: { record in
                Task { await snooze(record) }
            },
            onDelete: { record in
                Task {
                    try? await env.taskStore.softDelete(id: record.id)
                    await reload()
                }
            }
        )
        .navigationDestination(for: UUID.self) { id in
            TaskDetailView(taskID: id)
        }
        .task { await reload() }
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

    private func setStatus(_ record: TaskStore.TaskRecord, to newStatus: Status) async {
        try? await env.taskStore.transition(id: record.id, to: newStatus)
        await reload()
    }
}
