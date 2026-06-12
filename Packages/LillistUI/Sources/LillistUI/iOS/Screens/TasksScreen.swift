#if os(iOS)
import SwiftUI
import LillistCore

/// The iOS app's single primary surface. Renders an outline of every
/// incomplete task (subtasks nested under their parent, with collapsible
/// disclosure chevrons), an expanding filter header, a sort menu, and
/// trailing-edge full-swipe-to-delete on each row.
///
/// Pure presentation. The hosting `TasksView` owns the Core Data fetch,
/// the @AppStorage-backed sort selection, the filter state, the
/// `DragController` lifecycle, and the `.navigationDestination(for: UUID.self)
/// { TaskDetailView(taskID:) }` that turns a row tap into a detail push.
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
    @Binding public var isArchiveToastPresented: Bool
    @Binding public var isReorderToastPresented: Bool
    public var savedFilters: [SavedFilterChipSpec]
    public var collapsedNodeIDs: Set<UUID>
    public var archivedCount: Int

    @ObservedObject public var dragController: DragController

    public var onToggleCollapsed: (UUID) -> Void
    public var onRefresh: @MainActor () async -> Void
    public var onStatusClick: @MainActor (TaskStore.TaskRecord) -> Void
    public var onStatusSet: @MainActor (TaskStore.TaskRecord, Status) -> Void
    public var onDelete: @MainActor (TaskStore.TaskRecord) -> Void
    public var onClearFilter: @MainActor () -> Void
    public var onOpenSettings: @MainActor () -> Void
    public var onUndoArchive: @MainActor () -> Void

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
        isArchiveToastPresented: Binding<Bool> = .constant(false),
        isReorderToastPresented: Binding<Bool> = .constant(false),
        savedFilters: [SavedFilterChipSpec] = [],
        collapsedNodeIDs: Set<UUID> = [],
        archivedCount: Int = 0,
        dragController: DragController,
        onToggleCollapsed: @escaping (UUID) -> Void = { _ in },
        onRefresh: @escaping @MainActor () async -> Void = {},
        onStatusClick: @escaping @MainActor (TaskStore.TaskRecord) -> Void = { _ in },
        onStatusSet: @escaping @MainActor (TaskStore.TaskRecord, Status) -> Void = { _, _ in },
        onDelete: @escaping @MainActor (TaskStore.TaskRecord) -> Void = { _ in },
        onClearFilter: @escaping @MainActor () -> Void = {},
        onOpenSettings: @escaping @MainActor () -> Void = {},
        onUndoArchive: @escaping @MainActor () -> Void = {}
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
        self._isArchiveToastPresented = isArchiveToastPresented
        self._isReorderToastPresented = isReorderToastPresented
        self.savedFilters = savedFilters
        self.collapsedNodeIDs = collapsedNodeIDs
        self.archivedCount = archivedCount
        self.dragController = dragController
        self.onToggleCollapsed = onToggleCollapsed
        self.onRefresh = onRefresh
        self.onStatusClick = onStatusClick
        self.onStatusSet = onStatusSet
        self.onDelete = onDelete
        self.onClearFilter = onClearFilter
        self.onOpenSettings = onOpenSettings
        self.onUndoArchive = onUndoArchive
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
        .overlay(alignment: .bottom) {
            ArchiveToast(
                count: archivedCount,
                isPresented: $isArchiveToastPresented,
                onUndo: onUndoArchive
            )
        }
        .overlay(alignment: .bottom) {
            ReorderFailureToast(isPresented: $isReorderToastPresented)
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

    // MARK: - List

    @ViewBuilder
    private var listBody: some View {
        // `.coordinateSpace(name:)` must be on the List (not a wrapping
        // ZStack). When the named space is on a parent of the List,
        // rows' `proxy.frame(in: .named(...))` does not resolve to
        // positions that match the rows' visual rendering — it appears
        // SwiftUI's named coord space does not propagate cleanly
        // through the List's internal UICollectionView. The List's own
        // frame extends behind safe areas though, so the `.overlay {}`
        // (which is laid out *inside* the safe area) has its local
        // anchor offset from the named anchor by `safeAreaTop`;
        // `DragOverlay` compensates for that with a runtime
        // `proxy.frame(in: .named(...)).minY` shift.
        List {
            ForEach(flat) { row in
                outlineRow(row)
                    .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                    .opacity(row.node.record.id == draggedID ? 0 : 1)
                    .allowsHitTesting(row.node.record.id != draggedID)
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
                    // Geometry only — the drag gesture lives inside
                    // `outlineRow` on the NavigationLink so it never
                    // covers the chevron or status controls (their taps
                    // die under a row-wide long-press gesture; see
                    // engineering-notes 2026-06-12).
                    .reportRowGeometry(id: row.node.record.id)
            }
        }
        .listStyle(.plain)
        .coordinateSpace(name: DragCoordinateSpace.name)
        .onPreferenceChange(RowFramePreferenceKey.self) { frames in
            dragController.geometry = frames
        }
        .onChange(of: flat) { _, newFlat in
            syncDragControllerInputs(flat: newFlat)
        }
        .onAppear {
            syncDragControllerInputs(flat: flat)
        }
        .overlay {
            DragOverlay(controller: dragController) { id in
                phantomRow(forID: id)
            }
        }
    }

    private var draggedID: UUID? {
        switch dragController.state {
        case .dragging(let s), .dropping(let s, _): return s.draggedID
        case .idle: return nil
        }
    }

    @ViewBuilder
    private func phantomRow(forID id: UUID) -> some View {
        if let row = flat.first(where: { $0.node.record.id == id }) {
            outlineRow(row)
                .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                .padding(.horizontal, 12)
                .background(Color(.systemBackground))
        }
    }

    private func syncDragControllerInputs(flat: [FlatTaskRow]) {
        dragController.flatRows = flat.map {
            DragReorderRow(
                id: $0.node.record.id,
                parentID: $0.parentID,
                depth: $0.depth
            )
        }
        dragController.sortMode = (sort == .personalized) ? .personalized : .sortedByOther
        dragController.isFilterActive = hasActiveFilter
    }

    // MARK: - Row rendering

    @ViewBuilder
    private func outlineRow(_ row: FlatTaskRow) -> some View {
        // The NavigationLink and drag gesture wrap ONLY the text label
        // (the closure's parameter); the chevron and status indicator
        // are composed outside them by `TaskOutlineRowView` so their
        // taps are never consumed by the link or the long-press drag
        // sequence.
        TaskOutlineRowView(
            row: row,
            isCollapsed: collapsedNodeIDs.contains(row.node.id),
            onToggleDisclosure: { onToggleCollapsed(row.node.id) },
            onStatusClick: { onStatusClick(row.node.record) },
            onStatusSet: { newStatus in onStatusSet(row.node.record, newStatus) }
        ) { label in
            NavigationLink(value: row.node.record.id) {
                label
            }
            .dragReorderGesture(id: row.node.record.id, controller: dragController)
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
}
#endif
