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
    @Environment(AppEnvironment.self) private var env

    @State private var query = ""
    @State private var results: [TaskStore.TaskRecord] = []

    var body: some View {
        List {
            if query.isEmpty {
                ContentUnavailableView(
                    "Search Lillist",
                    systemImage: "magnifyingglass",
                    description: Text("Type a word from a task title.")
                )
            } else if results.isEmpty {
                ContentUnavailableView(
                    "No matches for \"\(query)\"",
                    systemImage: "questionmark.text.page"
                )
            } else {
                ForEach(results, id: \.id) { task in
                    NavigationLink(value: task.id) {
                        SearchResultRow(task: task, tagNames: [])
                    }
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
        .navigationTitle("Search")
        .navigationDestination(for: UUID.self) { id in
            TaskDetailView(taskID: id)
        }
        .task(id: query) { await runSearch() }
    }

    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        let group = PredicateGroup(
            combinator: .all,
            predicates: [
                .leaf(Leaf(field: .title, op: .contains, value: .string(trimmed))),
                .leaf(Leaf(field: .inTrash, op: .is, value: .bool(false)))
            ]
        )
        do {
            results = try await env.smartFilterStore.evaluate(
                group: group,
                sort: .modifiedAt,
                ascending: false
            )
        } catch {
            results = []
        }
    }
}
