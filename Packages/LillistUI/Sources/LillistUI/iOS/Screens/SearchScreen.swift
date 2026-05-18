#if os(iOS)
import SwiftUI
import LillistCore

/// Full-screen search reachable from the "Search" tab. Pure
/// presentation — the hosting iOS app's `SearchView` owns the @State
/// for query, scope, results, and recents; it also owns the
/// debounced `.task(id:)` that runs the actual title-substring match
/// through `SmartFilterStore`. Plan 20a Task 4d.
public struct SearchScreen: View {
    /// Scope filter applied to the title-substring match.
    public enum Scope: Hashable, CaseIterable, Sendable {
        case all, open, closed

        public var title: String {
            switch self {
            case .all: return String(localized: "All", bundle: .module)
            case .open: return String(localized: "Open", bundle: .module)
            case .closed: return String(localized: "Closed", bundle: .module)
            }
        }
    }

    @Binding public var query: String
    @Binding public var scope: Scope
    public var results: [TaskStore.TaskRecord]
    public var recents: [String]
    public var syncIndicator: SyncIndicator
    public var onClearRecents: @MainActor () -> Void
    public var onStatusClick: @MainActor (TaskStore.TaskRecord) -> Void
    public var onStatusSet: @MainActor (TaskStore.TaskRecord, Status) -> Void
    public var onComplete: @MainActor (TaskStore.TaskRecord) -> Void
    public var onDelete: @MainActor (TaskStore.TaskRecord) -> Void

    @Environment(\.taskSelectionBinding) private var taskSelection
    @Environment(\.quickCaptureAction) private var quickCaptureAction

    public init(
        query: Binding<String>,
        scope: Binding<Scope>,
        results: [TaskStore.TaskRecord],
        recents: [String] = [],
        syncIndicator: SyncIndicator = .idle(lastSync: nil),
        onClearRecents: @escaping @MainActor () -> Void = {},
        onStatusClick: @escaping @MainActor (TaskStore.TaskRecord) -> Void = { _ in },
        onStatusSet: @escaping @MainActor (TaskStore.TaskRecord, Status) -> Void = { _, _ in },
        onComplete: @escaping @MainActor (TaskStore.TaskRecord) -> Void = { _ in },
        onDelete: @escaping @MainActor (TaskStore.TaskRecord) -> Void = { _ in }
    ) {
        self._query = query
        self._scope = scope
        self.results = results
        self.recents = recents
        self.syncIndicator = syncIndicator
        self.onClearRecents = onClearRecents
        self.onStatusClick = onStatusClick
        self.onStatusSet = onStatusSet
        self.onComplete = onComplete
        self.onDelete = onDelete
    }

    public var body: some View {
        Group {
            if query.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "Search Lillist", bundle: .module),
                          systemImage: "magnifyingglass")
                } description: {
                    Text("Type a word from a task title.")
                } actions: {
                    Button {
                        quickCaptureAction()
                    } label: {
                        Label(String(localized: "Capture a task", bundle: .module),
                              systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
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
        .searchable(text: $query, placement: .automatic)
        .searchScopes($scope, scopes: {
            ForEach(Scope.allCases, id: \.self) { s in
                Text(s.title).tag(s)
            }
        })
        .searchSuggestions {
            if query.isEmpty && !recents.isEmpty {
                Section(String(localized: "Recent", bundle: .module)) {
                    ForEach(recents, id: \.self) { recent in
                        Text(recent).searchCompletion(recent)
                    }
                    Button(String(localized: "Clear recent searches", bundle: .module),
                           role: .destructive) {
                        onClearRecents()
                    }
                }
            }
        }
        .navigationTitle(Text(String(localized: "Search", bundle: .module)))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SyncStatusBadge(indicator: syncIndicator)
            }
        }
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
        SearchResultRowView(task: task, query: query)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button(String(localized: "Complete", bundle: .module)) {
                    onComplete(task)
                }
                .tint(.green)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    onDelete(task)
                } label: { Text(String(localized: "Delete", bundle: .module)) }
            }
            .contextMenu {
                Menu(String(localized: "Change status", bundle: .module)) {
                    ForEach(Status.allCases, id: \.self) { s in
                        Button(StatusGlyph.accessibilityLabel(for: s)) {
                            onStatusSet(task, s)
                        }
                    }
                }
                Button(role: .destructive) {
                    onDelete(task)
                } label: { Text(String(localized: "Delete", bundle: .module)) }
            }
    }
}
#endif
