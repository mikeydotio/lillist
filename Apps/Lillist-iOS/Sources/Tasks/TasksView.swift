import SwiftUI
import LillistCore
import LillistUI

/// Container for the single primary iOS surface. Owns the fetch and
/// reload lifecycle, the AppStorage-backed sort selection, the
/// ephemeral filter state, and the navigation destination wiring. The
/// presentation is delegated to `LillistUI.TasksScreen`.
struct TasksView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.isQuickCapturePresentedBinding) private var isQuickCapturePresented
    @Environment(\.sortBinding) private var sortBinding

    @State private var records: [TaskStore.TaskRecord] = []
    @State private var savedFilters: [SmartFilterStore.SmartFilterRecord] = []
    @State private var loadError: String?

    @State private var collapsedNodeIDs: Set<UUID> = []
    @State private var isFilterHeaderExpanded: Bool = false
    @State private var searchText: String = ""
    @State private var selectedTokens: Set<QuickFilterToken> = []
    @State private var selectedSavedFilters: Set<UUID> = []
    @State private var isSettingsPresented = false

    @State private var searchDebounceTask: Task<Void, Never>?

    var body: some View {
        TasksScreen(
            roots: tree,
            loadError: loadError,
            syncIndicator: env.syncMonitor.indicator,
            buildVersion: env.buildVersion,
            sort: sortBinding,
            isFilterHeaderExpanded: $isFilterHeaderExpanded,
            searchText: $searchText,
            selectedTokens: $selectedTokens,
            selectedSavedFilters: $selectedSavedFilters,
            savedFilters: savedFilterSpecs,
            collapsedNodeIDs: collapsedNodeIDs,
            onToggleCollapsed: { id in
                if collapsedNodeIDs.contains(id) {
                    collapsedNodeIDs.remove(id)
                } else {
                    collapsedNodeIDs.insert(id)
                }
            },
            onRefresh: { await reload() },
            onStatusClick: { record in Task { await cycle(record) } },
            onStatusSet: { record, newStatus in
                Task { await setStatus(record, to: newStatus) }
            },
            onDelete: { record in
                Task {
                    try? await env.taskStore.softDelete(id: record.id)
                    await reload()
                }
            },
            onMoveSiblings: { parentID, sources, destination in
                Task { await reorderSiblings(parentID: parentID, sources: sources, destination: destination) }
            },
            onClearFilter: {
                searchText = ""
                selectedTokens.removeAll()
                selectedSavedFilters.removeAll()
            },
            onOpenSettings: {
                isSettingsPresented = true
            }
        )
        .sheet(isPresented: $isSettingsPresented) {
            SettingsTab()
        }
        .environment(\.quickCaptureAction, { isQuickCapturePresented.wrappedValue = true })
        .overlay(alignment: .bottomTrailing) {
            FloatingAddButton(onTap: { isQuickCapturePresented.wrappedValue = true })
                .padding(.trailing, 16)
                .padding(.bottom, 16)
                .accessibilityIdentifier("TasksQuickCaptureFAB")
        }
        .modifier(QuickCaptureDialogHost(isPresented: isQuickCapturePresented))
        .task { await initialLoad() }
        .onChange(of: sortBinding.wrappedValue) { _, _ in Task { await reload() } }
        .onChange(of: selectedTokens) { _, _ in Task { await reload() } }
        .onChange(of: selectedSavedFilters) { _, _ in Task { await reload() } }
        .onChange(of: searchText) { _, newValue in
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if Task.isCancelled { return }
                if searchText == newValue {
                    await reload()
                }
            }
        }
    }

    // MARK: - Derived

    private var tree: [TaskNode] {
        TaskTree.build(
            records: records,
            tagsByTask: [:],
            sort: sortBinding.wrappedValue
        )
    }

    private var savedFilterSpecs: [SavedFilterChipSpec] {
        savedFilters
            .filter { $0.isPinned }
            .sorted { $0.position < $1.position }
            .map { SavedFilterChipSpec(id: $0.id, title: $0.name) }
    }

    // MARK: - Load

    private func initialLoad() async {
        await loadSavedFilters()
        await reload()
    }

    private func loadSavedFilters() async {
        do {
            savedFilters = try await env.smartFilterStore.list()
        } catch {
            // Saved filters are an additive convenience; silently
            // surface as empty rather than blocking the whole view.
            savedFilters = []
        }
    }

    private func reload() async {
        do {
            let group = buildActivePredicateGroup()
            records = try await env.smartFilterStore.evaluate(
                group: group,
                sort: storeSortField,
                ascending: storeSortAscending
            )
            loadError = nil
        } catch {
            loadError = "\(error)"
            records = []
        }
    }

    // MARK: - Predicate composition

    /// Combine the default `status != closed` baseline with whatever
    /// quick tokens / saved filters / search text the user has applied.
    /// The `done` token is special — it replaces the closed-exclusion
    /// rather than AND-ing with it (otherwise the result would always
    /// be empty).
    private func buildActivePredicateGroup() -> PredicateGroup {
        var predicates: [LillistCore.Predicate] = []

        if selectedTokens.contains(.done) {
            predicates.append(
                .leaf(Leaf(field: .status, op: .is, value: .statusSet([.closed])))
            )
        } else {
            predicates.append(
                .leaf(Leaf(field: .status, op: .isNot, value: .statusSet([.closed])))
            )
        }

        if selectedTokens.contains(.today) {
            predicates.append(.group(PredicateGroup(
                combinator: .any,
                predicates: [
                    .leaf(Leaf(field: .deadline, op: .on, value: .relativeDate(.today))),
                    .leaf(Leaf(field: .start, op: .on, value: .relativeDate(.today)))
                ]
            )))
        }

        if selectedTokens.contains(.thisWeek) {
            predicates.append(.group(PredicateGroup(
                combinator: .any,
                predicates: [
                    .leaf(Leaf(field: .deadline, op: .withinNextDays, value: .dayCount(7))),
                    .leaf(Leaf(field: .start, op: .withinLastDays, value: .dayCount(7)))
                ]
            )))
        }

        for id in selectedSavedFilters {
            if let filter = savedFilters.first(where: { $0.id == id }) {
                predicates.append(.group(filter.group))
            }
        }

        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            predicates.append(
                .leaf(Leaf(field: .title, op: .contains, value: .string(trimmed)))
            )
        }

        return PredicateGroup(combinator: .all, predicates: predicates)
    }

    private var storeSortField: SortField {
        switch sortBinding.wrappedValue {
        case .personalized: return .manualPosition
        case .due: return .deadline
        case .modified: return .modifiedAt
        }
    }

    private var storeSortAscending: Bool {
        switch sortBinding.wrappedValue {
        case .personalized, .due: return true
        case .modified: return false
        }
    }

    // MARK: - Mutations

    private func cycle(_ record: TaskStore.TaskRecord) async {
        let next = StatusCycler.nextOnClick(from: record.status)
        try? await env.taskStore.transition(id: record.id, to: next)
        await reload()
    }

    private func setStatus(_ record: TaskStore.TaskRecord, to newStatus: Status) async {
        try? await env.taskStore.transition(id: record.id, to: newStatus)
        await reload()
    }

    /// Resolve sibling-relative move semantics: `TaskStore.reorder`
    /// needs `after` and `before` UUID anchors. We compute them in the
    /// sibling-only subsequence so cross-parent attempts (already
    /// rejected upstream in `TasksScreen.performMove`) can't sneak in.
    @MainActor
    private func reorderSiblings(parentID: UUID?, sources: IndexSet, destination: Int) async {
        let flat = TreeFlattener.flatten(tree, collapsed: collapsedNodeIDs)
        let siblingFlatIndices = flat.indices.filter { flat[$0].parentID == parentID }
        let siblings = siblingFlatIndices.map { flat[$0].node.record.id }

        let sourceSibIndices = sources.compactMap { siblingFlatIndices.firstIndex(of: $0) }
        guard !sourceSibIndices.isEmpty else { return }

        let destSibIndex: Int
        if destination >= flat.count {
            destSibIndex = siblings.count
        } else if let pos = siblingFlatIndices.firstIndex(of: destination) {
            destSibIndex = pos
        } else {
            return
        }

        var newOrder = siblings
        newOrder.move(fromOffsets: IndexSet(sourceSibIndices), toOffset: destSibIndex)

        for sibIndex in sourceSibIndices {
            let movedID = siblings[sibIndex]
            guard let newPos = newOrder.firstIndex(of: movedID) else { continue }
            let after = newPos > 0 ? newOrder[newPos - 1] : nil
            let before = newPos < newOrder.count - 1 ? newOrder[newPos + 1] : nil
            try? await env.taskStore.reorder(id: movedID, after: after, before: before)
        }
        await reload()
    }
}
