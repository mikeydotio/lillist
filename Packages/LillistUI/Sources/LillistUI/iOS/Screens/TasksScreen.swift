#if os(iOS)
import SwiftUI
import LillistCore

/// The iOS app's single primary surface. Renders an outline of every
/// incomplete task (subtasks nested under their parent, with collapsible
/// disclosure chevrons), an expanding filter header, a sort menu, and
/// trailing-edge full-swipe-to-delete on each row.
///
/// Pure presentation. The hosting `TasksView` owns the Core Data fetch,
/// the @AppStorage-backed sort selection, the filter state, and the
/// `.navigationDestination(for: UUID.self) { TaskDetailView(taskID:) }`
/// that turns a row tap into a detail push.
public struct TasksScreen: View {

    // MARK: - Inputs

    public var roots: [TaskNode]
    public var loadError: String?
    public var syncIndicator: SyncIndicator
    public var buildVersion: String?

    @Binding public var sort: TasksSort
    @Binding public var isFilterHeaderExpanded: Bool
    @Binding public var searchText: String
    @Binding public var selectedTokens: Set<QuickFilterToken>
    @Binding public var selectedSavedFilters: Set<UUID>
    public var savedFilters: [SavedFilterChipSpec]
    public var collapsedNodeIDs: Set<UUID>

    public var onToggleCollapsed: (UUID) -> Void
    public var onRefresh: @MainActor () async -> Void
    public var onStatusClick: @MainActor (TaskStore.TaskRecord) -> Void
    public var onStatusSet: @MainActor (TaskStore.TaskRecord, Status) -> Void
    public var onDelete: @MainActor (TaskStore.TaskRecord) -> Void
    public var onMoveSiblings: @MainActor (_ parentID: UUID?, _ indices: IndexSet, _ destination: Int) -> Void
    public var onClearFilter: @MainActor () -> Void
    public var onOpenSettings: @MainActor () -> Void

    @Environment(\.quickCaptureAction) private var quickCaptureAction

    public init(
        roots: [TaskNode],
        loadError: String? = nil,
        syncIndicator: SyncIndicator = .idle(lastSync: nil),
        buildVersion: String? = nil,
        sort: Binding<TasksSort>,
        isFilterHeaderExpanded: Binding<Bool>,
        searchText: Binding<String>,
        selectedTokens: Binding<Set<QuickFilterToken>>,
        selectedSavedFilters: Binding<Set<UUID>>,
        savedFilters: [SavedFilterChipSpec] = [],
        collapsedNodeIDs: Set<UUID> = [],
        onToggleCollapsed: @escaping (UUID) -> Void = { _ in },
        onRefresh: @escaping @MainActor () async -> Void = {},
        onStatusClick: @escaping @MainActor (TaskStore.TaskRecord) -> Void = { _ in },
        onStatusSet: @escaping @MainActor (TaskStore.TaskRecord, Status) -> Void = { _, _ in },
        onDelete: @escaping @MainActor (TaskStore.TaskRecord) -> Void = { _ in },
        onMoveSiblings: @escaping @MainActor (UUID?, IndexSet, Int) -> Void = { _, _, _ in },
        onClearFilter: @escaping @MainActor () -> Void = {},
        onOpenSettings: @escaping @MainActor () -> Void = {}
    ) {
        self.roots = roots
        self.loadError = loadError
        self.syncIndicator = syncIndicator
        self.buildVersion = buildVersion
        self._sort = sort
        self._isFilterHeaderExpanded = isFilterHeaderExpanded
        self._searchText = searchText
        self._selectedTokens = selectedTokens
        self._selectedSavedFilters = selectedSavedFilters
        self.savedFilters = savedFilters
        self.collapsedNodeIDs = collapsedNodeIDs
        self.onToggleCollapsed = onToggleCollapsed
        self.onRefresh = onRefresh
        self.onStatusClick = onStatusClick
        self.onStatusSet = onStatusSet
        self.onDelete = onDelete
        self.onMoveSiblings = onMoveSiblings
        self.onClearFilter = onClearFilter
        self.onOpenSettings = onOpenSettings
    }

    // MARK: - Derived

    private var flat: [FlatTaskRow] {
        TreeFlattener.flatten(roots, collapsed: collapsedNodeIDs)
    }

    private var hasActiveFilter: Bool {
        !searchText.isEmpty || !selectedTokens.isEmpty || !selectedSavedFilters.isEmpty
    }

    // MARK: - Body

    public var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView(
                    String(localized: "Could not load tasks", bundle: .module),
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else if flat.isEmpty {
                emptyState
            } else {
                listBody
            }
        }
        .navigationTitle(Text(String(localized: "Tasks", bundle: .module)))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .safeAreaInset(edge: .top, spacing: 0) {
            if isFilterHeaderExpanded {
                FilterHeader(
                    searchText: $searchText,
                    selectedTokens: $selectedTokens,
                    selectedSavedFilters: $selectedSavedFilters,
                    savedFilters: savedFilters,
                    onClear: onClearFilter
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .refreshable { await onRefresh() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let buildVersion {
                BuildVersionLabel(version: buildVersion)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isFilterHeaderExpanded)
    }

    @ViewBuilder
    private var emptyState: some View {
        if hasActiveFilter {
            ContentUnavailableView {
                Label(String(localized: "No matching tasks", bundle: .module),
                      systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text(String(localized: "Try clearing the filter to see all your tasks.", bundle: .module))
            } actions: {
                Button(String(localized: "Clear filter", bundle: .module)) {
                    onClearFilter()
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView {
                Label(String(localized: "No tasks yet", bundle: .module),
                      systemImage: "checklist")
            } description: {
                Text(String(localized: "Every open task shows up here. Capture one to get started.", bundle: .module))
            } actions: {
                Button {
                    quickCaptureAction()
                } label: {
                    Label(String(localized: "Capture a task", bundle: .module),
                          systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("TasksEmptyStateCaptureButton")
            }
        }
    }

    /// Personalized = active editMode so SwiftUI's grab handles show on
    /// the trailing edge. Other sorts disable edit mode so the trailing
    /// swipe-to-delete action remains available.
    private var editModeBinding: Binding<EditMode> {
        let value: EditMode = (sort == .personalized) ? .active : .inactive
        return .constant(value)
    }

    private var moveHandler: ((IndexSet, Int) -> Void)? {
        guard sort == .personalized else { return nil }
        return { source, destination in
            performMove(source, to: destination)
        }
    }

    @ViewBuilder
    private var listBody: some View {
        List {
            ForEach(flat) { row in
                outlineRow(row)
                    .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            onDelete(row.node.record)
                        } label: {
                            Label(
                                String(localized: "Delete", bundle: .module),
                                systemImage: "trash"
                            )
                        }
                    }
            }
            .onMove(perform: moveHandler)
        }
        .listStyle(.plain)
        .environment(\.editMode, editModeBinding)
    }

    @ViewBuilder
    private func outlineRow(_ row: FlatTaskRow) -> some View {
        HStack(spacing: 0) {
            NavigationLink(value: row.node.record.id) {
                TaskOutlineRowView(
                    row: row,
                    isCollapsed: collapsedNodeIDs.contains(row.node.id),
                    onToggleDisclosure: { onToggleCollapsed(row.node.id) },
                    onStatusClick: { onStatusClick(row.node.record) },
                    onStatusSet: { newStatus in onStatusSet(row.node.record, newStatus) }
                )
            }
        }
        .tag(row.node.record.id)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                onOpenSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel(String(localized: "Settings", bundle: .module))
            .accessibilityIdentifier("TasksSettingsButton")
        }
        ToolbarItem(placement: .topBarTrailing) {
            SyncStatusBadge(indicator: syncIndicator)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker(String(localized: "Sort", bundle: .module),
                       selection: $sort) {
                    Text(String(localized: "Personalized", bundle: .module))
                        .tag(TasksSort.personalized)
                    Text(String(localized: "Due", bundle: .module))
                        .tag(TasksSort.due)
                    Text(String(localized: "Modified", bundle: .module))
                        .tag(TasksSort.modified)
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .accessibilityLabel(String(localized: "Sort", bundle: .module))
            .accessibilityIdentifier("TasksSortMenu")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isFilterHeaderExpanded.toggle()
            } label: {
                Image(systemName: hasActiveFilter
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
            }
            .accessibilityLabel(String(localized: "Filter", bundle: .module))
            .accessibilityIdentifier("TasksFilterToggle")
        }
    }

    // MARK: - Move

    /// Constrain `.onMove` to siblings of the same parent. If the user
    /// drops across parents, revert (no-op). All drops within a sibling
    /// group call `onMoveSiblings` with the resolved parent + indices.
    @MainActor
    private func performMove(_ source: IndexSet, to destination: Int) {
        let snapshot = flat
        guard let first = source.first else { return }
        guard first < snapshot.count else { return }
        let sourceParent = snapshot[first].parentID

        // SwiftUI's `to` destination is in the post-removal coordinate
        // space. Resolve it back to the equivalent row index in the
        // current snapshot for parent comparison.
        let resolvedDestinationIndex = min(max(0, destination), snapshot.count)
        let neighborIndex = resolvedDestinationIndex == snapshot.count
            ? snapshot.count - 1
            : resolvedDestinationIndex
        guard neighborIndex >= 0, neighborIndex < snapshot.count else { return }
        let neighborParent = snapshot[neighborIndex].parentID
        guard sourceParent == neighborParent else { return }

        // All sources must share the same parent for a valid move.
        let allSameParent = source.allSatisfy { snapshot[$0].parentID == sourceParent }
        guard allSameParent else { return }

        onMoveSiblings(sourceParent, source, destination)
    }
}
#endif
