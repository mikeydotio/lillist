import SwiftUI
import LillistCore
import LillistUI

/// Thin wrapper around `LillistUI.AllScreen`. Fetches every open
/// non-trashed task via an ad-hoc `PredicateGroup` (status != closed;
/// the compiler adds the implicit "not in trash" leaf), holds the
/// results as @State, and re-runs on every appearance + after every
/// mutation. Plan: RCA — iOS new-task flow / 3-tab restructure.
struct AllView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var results: [TaskStore.TaskRecord] = []
    @State private var loadError: String?

    var body: some View {
        AllScreen(
            results: results,
            loadError: loadError,
            syncIndicator: env.syncMonitor.indicator,
            buildVersion: env.buildVersion,
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

    /// Open + not-in-trash. Trash exclusion is added implicitly by
    /// `NSPredicateCompiler` when the predicate doesn't mention `inTrash`.
    private static let allOpenGroup = PredicateGroup(
        combinator: .all,
        predicates: [
            .leaf(Leaf(field: .status, op: .isNot, value: .statusSet([.closed])))
        ]
    )

    private func reload() async {
        do {
            results = try await env.smartFilterStore.evaluate(
                group: Self.allOpenGroup,
                sort: .modifiedAt,
                ascending: false
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

    private func setStatus(_ record: TaskStore.TaskRecord, to newStatus: Status) async {
        try? await env.taskStore.transition(id: record.id, to: newStatus)
        await reload()
    }
}
