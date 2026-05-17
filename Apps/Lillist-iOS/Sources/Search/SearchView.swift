import SwiftUI
import LillistCore
import LillistUI

// MARK: - Accessibility audit (Plan 8, Task 26)
// - `.searchable` produces a standard VoiceOver-labeled search field.
// - Result rows use SearchResultRow → TaskRowView which has a combined
//   accessibility element with status spelled out.
// - No fixed font sizes; semantic colors only.

/// Full-screen search. The query string is treated as a title-substring
/// match against non-trashed tasks (sorted by most-recently-modified).
///
/// Deviation note: the plan text references `PredicateParser.parse(query)`
/// for a full smart-filter DSL search, but LillistCore doesn't ship a public
/// DSL parser. Title-contains gets us the common case; a follow-up can swap
/// in the DSL parser when one lands.
struct SearchView: View {
    enum Scope: Hashable, CaseIterable {
        case all, open, closed
        var title: String {
            switch self {
            case .all: return "All"
            case .open: return "Open"
            case .closed: return "Closed"
            }
        }
    }

    private struct SearchTrigger: Hashable {
        let query: String
        let scope: Scope
    }

    @Environment(AppEnvironment.self) private var env
    @Environment(\.taskSelectionBinding) private var taskSelection

    @State private var query = ""
    @State private var scope: Scope = .all
    @State private var results: [TaskStore.TaskRecord] = []
    @State private var recents = RecentSearchesStore()

    var body: some View {
        Group {
            if query.isEmpty {
                List {
                    ContentUnavailableView(
                        "Search Lillist",
                        systemImage: "magnifyingglass",
                        description: Text("Type a word from a task title.")
                    )
                }
            } else if results.isEmpty {
                List {
                    ContentUnavailableView(
                        "No matches for \"\(query)\"",
                        systemImage: "questionmark.text.page"
                    )
                }
            } else {
                resultsBody
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
        .searchScopes($scope, scopes: {
            ForEach(Scope.allCases, id: \.self) { s in
                Text(s.title).tag(s)
            }
        })
        .searchSuggestions {
            if query.isEmpty && !recents.recent.isEmpty {
                Section("Recent") {
                    ForEach(recents.recent, id: \.self) { recent in
                        Text(recent).searchCompletion(recent)
                    }
                    Button("Clear recent searches", role: .destructive) {
                        recents.clear()
                    }
                }
            }
        }
        .navigationTitle("Search")
        .navigationDestination(for: UUID.self) { id in
            TaskDetailView(taskID: id)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SyncStatusBadge(indicator: env.syncMonitor.indicator)
            }
        }
        .task(id: SearchTrigger(query: query, scope: scope)) { await runSearch() }
    }

    @ViewBuilder
    private var resultsBody: some View {
        if let taskSelection {
            List(selection: taskSelection) {
                ForEach(results, id: \.id) { task in
                    row(task).tag(task.id)
                }
            }
        } else {
            List {
                ForEach(results, id: \.id) { task in
                    NavigationLink(value: task.id) { row(task) }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ task: TaskStore.TaskRecord) -> some View {
        SearchResultRow(task: task, tagNames: [], query: query)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button("Complete") {
                    Task { try? await env.taskStore.transition(id: task.id, to: .closed); await runSearch() }
                }.tint(.green)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    Task { try? await env.taskStore.softDelete(id: task.id); await runSearch() }
                } label: { Text("Delete") }
            }
            .contextMenu {
                Menu("Change status") {
                    ForEach(Status.allCases, id: \.self) { s in
                        Button(StatusGlyph.accessibilityLabel(for: s)) {
                            Task { try? await env.taskStore.transition(id: task.id, to: s); await runSearch() }
                        }
                    }
                }
                Button(role: .destructive) {
                    Task { try? await env.taskStore.softDelete(id: task.id); await runSearch() }
                } label: { Text("Delete") }
            }
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
}
