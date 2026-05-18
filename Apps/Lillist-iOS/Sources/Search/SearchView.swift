import SwiftUI
import LillistCore
import LillistUI

/// Thin wrapper around `LillistUI.SearchScreen`. Owns the @State for
/// query, scope, results, and recents; runs the debounced
/// title-substring match through `SmartFilterStore`; and registers the
/// `.navigationDestination(for: UUID.self)` that turns a tapped row
/// into a `TaskDetailView`. Plan 20a Task 4d.
///
/// Deviation note: the plan text references `PredicateParser.parse(query)`
/// for a full smart-filter DSL search, but LillistCore doesn't ship a public
/// DSL parser. Title-contains gets us the common case; a follow-up can swap
/// in the DSL parser when one lands.
struct SearchView: View {
    private struct SearchTrigger: Hashable {
        let query: String
        let scope: SearchScreen.Scope
    }

    @Environment(AppEnvironment.self) private var env

    @State private var query = ""
    @State private var scope: SearchScreen.Scope = .all
    @State private var results: [TaskStore.TaskRecord] = []
    @State private var recents = RecentSearchesStore()

    var body: some View {
        SearchScreen(
            query: $query,
            scope: $scope,
            results: results,
            recents: recents.recent,
            syncIndicator: env.syncMonitor.indicator,
            onClearRecents: { recents.clear() },
            onStatusClick: { record in Task { await cycle(record) } },
            onStatusSet: { record, newStatus in
                Task { await setStatus(record, to: newStatus) }
            },
            onComplete: { record in
                Task {
                    try? await env.taskStore.transition(id: record.id, to: .closed)
                    await runSearch()
                }
            },
            onDelete: { record in
                Task {
                    try? await env.taskStore.softDelete(id: record.id)
                    await runSearch()
                }
            }
        )
        .navigationDestination(for: UUID.self) { id in
            TaskDetailView(taskID: id)
        }
        .task(id: SearchTrigger(query: query, scope: scope)) { await runSearch() }
    }

    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(250))
        } catch {
            return  // cancelled — newer query incoming
        }
        var predicates: [LillistCore.Predicate] = [
            .leaf(Leaf(field: .title, op: .contains, value: .string(trimmed))),
            .leaf(Leaf(field: .inTrash, op: .is, value: .bool(false)))
        ]
        switch scope {
        case .all:
            break
        case .open:
            predicates.append(.leaf(Leaf(field: .status, op: .isNot, value: .statusSet([.closed]))))
        case .closed:
            predicates.append(.leaf(Leaf(field: .status, op: .is, value: .statusSet([.closed]))))
        }
        let group = PredicateGroup(combinator: .all, predicates: predicates)
        do {
            results = try await env.smartFilterStore.evaluate(
                group: group,
                sort: .modifiedAt,
                ascending: false
            )
            if !results.isEmpty {
                recents.record(trimmed)
            }
        } catch {
            results = []
        }
    }

    private func cycle(_ record: TaskStore.TaskRecord) async {
        let next = StatusCycler.nextOnClick(from: record.status)
        try? await env.taskStore.transition(id: record.id, to: next)
        await runSearch()
    }

    private func setStatus(_ record: TaskStore.TaskRecord, to newStatus: Status) async {
        try? await env.taskStore.transition(id: record.id, to: newStatus)
        await runSearch()
    }
}
