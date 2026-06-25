// Cross-platform: shared by the iOS app and the macOS main window.
import SwiftUI
import LillistCore

/// The iOS app's single primary surface. Renders an outline of every
/// incomplete task (subtasks nested under their parent, with collapsible
/// disclosure chevrons), an expanding filter header, a sort menu, and
/// trailing-edge full-swipe-to-delete on each row.
///
/// Pure presentation. The hosting `TasksView` owns the Core Data fetch,
/// the @AppStorage-backed sort selection, the filter state, the
/// `DragController` lifecycle, and the `onOpenTask` handler that turns a
/// row tap into a unified-editor presentation (the former
/// `NavigationLink`-to-`TaskDetailView` push was retired).
public struct TasksScreen: View {

    // MARK: - Inputs

    public var roots: [TaskNode]
    public var loadError: String?
    public var buildVersion: String?

    @Binding public var sort: TasksSort
    @Binding public var isFilterHeaderExpanded: Bool
    @Binding public var searchText: String
    @Binding public var selectedTokens: Set<QuickFilterToken>
    @Binding public var selectedSavedFilters: Set<UUID>
    @Binding public var isArchiveToastPresented: Bool
    @Binding public var isReorderToastPresented: Bool
    @Binding public var isStatusToastPresented: Bool
    public var savedFilters: [SavedFilterChipSpec]
    public var collapsedNodeIDs: Set<UUID>
    public var archivedCount: Int

    @ObservedObject public var dragController: DragController

    /// The single row whose swipe actions are currently held open (one at a
    /// time). `SwipeableRow` reads/writes this to close peers on open.
    @State private var openSwipeRowID: UUID?

    public var onToggleCollapsed: (UUID) -> Void
    public var onRefresh: @MainActor () async -> Void
    public var onStatusClick: @MainActor (TaskStore.TaskRecord) -> Void
    public var onStatusSet: @MainActor (TaskStore.TaskRecord, Status) -> Void
    public var onDelete: @MainActor (TaskStore.TaskRecord) -> Void
    public var onClearFilter: @MainActor () -> Void
    public var onOpenSettings: @MainActor () -> Void
    public var onUndoArchive: @MainActor () -> Void
    /// Open the unified task editor for the tapped row. Replaces the former
    /// `NavigationLink`-to-detail push.
    public var onOpenTask: @MainActor (UUID) -> Void

    @Environment(\.quickCaptureAction) private var quickCaptureAction

    public init(
        roots: [TaskNode],
        loadError: String? = nil,
        buildVersion: String? = nil,
        sort: Binding<TasksSort>,
        isFilterHeaderExpanded: Binding<Bool>,
        searchText: Binding<String>,
        selectedTokens: Binding<Set<QuickFilterToken>>,
        selectedSavedFilters: Binding<Set<UUID>>,
        isArchiveToastPresented: Binding<Bool> = .constant(false),
        isReorderToastPresented: Binding<Bool> = .constant(false),
        isStatusToastPresented: Binding<Bool> = .constant(false),
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
        onUndoArchive: @escaping @MainActor () -> Void = {},
        onOpenTask: @escaping @MainActor (UUID) -> Void = { _ in }
    ) {
        self.roots = roots
        self.loadError = loadError
        self.buildVersion = buildVersion
        self._sort = sort
        self._isFilterHeaderExpanded = isFilterHeaderExpanded
        self._searchText = searchText
        self._selectedTokens = selectedTokens
        self._selectedSavedFilters = selectedSavedFilters
        self._isArchiveToastPresented = isArchiveToastPresented
        self._isReorderToastPresented = isReorderToastPresented
        self._isStatusToastPresented = isStatusToastPresented
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
        self.onOpenTask = onOpenTask
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
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
            // Toasts stack in a VStack so co-visible Liquid Glass
            // capsules never overlap — that sidesteps glass-on-glass
            // without a GlassEffectContainer. (An always-present
            // container would blank every offscreen snapshot of this
            // screen, not just the toast variants — see
            // docs/engineering-notes.md 2026-06-12.) Each toast renders
            // nothing until presented, so the common no-toast state has
            // no glass at all.
            VStack(spacing: LillistSpacing.s) {
                ArchiveToast(
                    count: archivedCount,
                    isPresented: $isArchiveToastPresented,
                    onUndo: onUndoArchive
                )
                ReorderFailureToast(isPresented: $isReorderToastPresented)
                StatusChangeFailureToast(isPresented: $isStatusToastPresented)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isFilterHeaderExpanded)
    }

    @ViewBuilder
    private var emptyState: some View {
        if hasActiveFilter {
            RainbowEmptyStateView(
                title: String(localized: "No matching tasks", bundle: .module),
                message: String(localized: "Try clearing the filter to see all your tasks.", bundle: .module),
                systemImage: "line.3.horizontal.decrease.circle"
            ) {
                Button(String(localized: "Clear filter", bundle: .module)) {
                    onClearFilter()
                }
                .buttonStyle(.rainbow(.secondary))
            }
        } else {
            RainbowEmptyStateView(
                title: String(localized: "No tasks yet", bundle: .module),
                message: String(localized: "Every open task shows up here. Capture one to get started.", bundle: .module),
                systemImage: "checklist"
            ) {
                Button {
                    quickCaptureAction()
                } label: {
                    Label(String(localized: "Capture a task", bundle: .module),
                          systemImage: "plus.circle.fill")
                }
                .buttonStyle(.rainbow(.lavender))
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
                // Custom swipe (left = Delete, right = Mark open) replaces
                // `.swipeActions`, which can't coexist with the bespoke
                // long-press drag-reorder gesture — see SwipeableRow's note
                // and engineering-notes 2026-06-17.
                SwipeableRow(
                    rowID: row.node.record.id,
                    leading: SwipeActionSpec(
                        titleKey: "Mark open",
                        systemImage: StatusGlyph.symbol(for: .todo),
                        tint: RainbowPalette.focusBlue.base,
                        perform: { onStatusSet(row.node.record, .todo) }
                    ),
                    trailing: SwipeActionSpec(
                        titleKey: "Delete",
                        systemImage: "trash",
                        tint: RainbowPalette.actionOrange.base,
                        isDestructive: true,
                        perform: { onDelete(row.node.record) }
                    ),
                    isReorderActive: draggedID != nil,
                    openRowID: $openSwipeRowID
                ) {
                    outlineRow(row)
                }
                .listRowInsets(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .opacity(row.node.record.id == draggedID ? 0 : 1)
                .allowsHitTesting(row.node.record.id != draggedID)
                // Geometry only — the drag gesture lives inside `outlineRow`
                // on the inert text label so it never covers the chevron or
                // status controls (their taps die under a row-wide long-press
                // gesture; see engineering-notes 2026-06-12).
                .reportRowGeometry(id: row.node.record.id)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(LillistColor.workspace)
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
            // The drag ghost is the bare Rainbow card — no depth indent or
            // disclosure chevron — so DragOverlay's rainbow halo shrink-wraps
            // the card instead of the full-width row slot. Mirrors the macOS
            // phantom (`TaskRowView` + `.rainbowCard`).
            TaskRowView(
                task: row.node.record,
                tagNames: row.node.tagNames,
                onStatusClick: {},
                onStatusSet: { _ in }
            )
            .rainbowCard(
                accent: StatusPalette.color(for: row.node.record.status),
                isDone: row.node.record.status == .closed,
                border: .rainbow
            )
            .padding(.horizontal, 12)
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
        // The tap gesture and drag gesture wrap ONLY the text label
        // (the closure's parameter); the chevron and status indicator
        // are composed outside them by `TaskOutlineRowView` so their
        // taps are never consumed by the long-press drag sequence.
        // Tapping the label opens the unified editor (the former
        // `NavigationLink`-to-detail push was retired). We own the tap
        // as `.onTapGesture` rather than a `Button` on purpose: a
        // `Button`'s intrinsic press recognizer wins gesture arbitration
        // over the lower-priority `.dragReorderGesture` long-press and
        // starves it (tap works, reorder dies). Mirrors the macOS
        // `TaskListView` pattern; see engineering-notes 2026-06-17.
        TaskOutlineRowView(
            row: row,
            isCollapsed: collapsedNodeIDs.contains(row.node.id),
            isDropTargetParent: dragController.dropTargetParentID == row.node.id,
            onToggleDisclosure: { onToggleCollapsed(row.node.id) },
            onStatusClick: { onStatusClick(row.node.record) },
            onStatusSet: { newStatus in onStatusSet(row.node.record, newStatus) }
        ) { label in
            label
                .contentShape(Rectangle())
                .onTapGesture { onOpenTask(row.node.record.id) }
                .dragReorderGesture(id: row.node.record.id, controller: dragController)
                // Restore the VoiceOver affordance the dropped `Button`
                // gave for free: a single "button, double-tap to open"
                // element. Status circle and chevron stay outside this
                // closure, so their accessibility is unaffected.
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onOpenTask(row.node.record.id) }
        }
        .tag(row.node.record.id)
    }

    // MARK: - Toolbar

    /// Toolbar item placements differ by platform: iOS uses the
    /// navigation-bar leading/trailing slots; macOS has no nav bar, so we
    /// map them onto the window toolbar's navigation / primary-action areas.
    private var leadingPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }

    private var trailingPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: leadingPlacement) {
            Button {
                onOpenSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel(String(localized: "Settings", bundle: .module))
            .accessibilityIdentifier("TasksSettingsButton")
        }
        ToolbarItem(placement: trailingPlacement) {
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
        ToolbarItem(placement: trailingPlacement) {
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
