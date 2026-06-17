import SwiftUI
import LillistCore
import LillistUI

struct RootSplitView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openTaskEditorAction) private var openTaskEditorAction
    @State private var uiState = UIStatePersistence()
    @State private var sidebarSelection: SidebarSelection?
    @State private var taskSelection: UUID?
    @SceneStorage("lillist.ui.columnVisibility") private var columnVisibilityRaw: String = "all"
    @State private var sortField: SortField = .deadline
    @State private var sortAscending: Bool = true
    @FocusState private var focusedColumn: ListColumn?
    @State private var resolvedPrincipalTitle: String = "Lillist"

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { Self.parseVisibility(columnVisibilityRaw) },
            set: { columnVisibilityRaw = Self.encodeVisibility($0) }
        )
    }

    static func parseVisibility(_ raw: String) -> NavigationSplitViewVisibility {
        switch raw {
        case "doubleColumn": return .doubleColumn
        case "detailOnly":   return .detailOnly
        default:             return .all
        }
    }

    static func encodeVisibility(_ v: NavigationSplitViewVisibility) -> String {
        switch v {
        case .doubleColumn: return "doubleColumn"
        case .detailOnly:   return "detailOnly"
        default:            return "all"
        }
    }

    init() {
        let persisted = UIStatePersistence().sidebarSelection
        _sidebarSelection = State(initialValue: persisted)
    }

    @ViewBuilder private var contentColumn: some View {
        if let sel = sidebarSelection {
            TaskListView(
                selection: sel,
                taskSelection: $taskSelection,
                sortField: $sortField,
                sortAscending: $sortAscending
            )
            .focused($focusedColumn, equals: .list)
            .navigationSplitViewColumnWidth(min: 320, ideal: 460)
        } else {
            EmptyStateView(title: "Select a source", message: "Pick a pinned item, tag, or filter from the sidebar.")
        }
    }

    // Detail column retired: clicking/Return on a row opens the unified
    // floating editor (`openTaskEditorAction`) instead of filling a docked
    // pane. `taskSelection` now just drives the list highlight. The split view
    // is extracted so `body`'s long modifier chain type-checks in time.
    private var splitView: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            SidebarView(selection: $sidebarSelection)
                .focused($focusedColumn, equals: .sidebar)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            contentColumn
        }
    }

    var body: some View {
        splitView
        .toolbar { toolbarContent }
        .onAppear { focusedColumn = .list }
        .onReceive(NotificationCenter.default.publisher(for: .lillistFocusSidebar)) { _ in focusedColumn = .sidebar }
        .onReceive(NotificationCenter.default.publisher(for: .lillistFocusList)) { _ in focusedColumn = .list }
        .onReceive(NotificationCenter.default.publisher(for: .lillistOpenTaskEditor)) { _ in
            if let id = taskSelection { openTaskEditorAction(id) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lillistMarkClosed)) { _ in
            if let id = taskSelection { Task { try? await env.taskStore.transition(id: id, to: .closed) } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lillistToggleStarted)) { _ in
            if let id = taskSelection {
                Task {
                    guard let r = try? await env.taskStore.fetch(id: id) else { return }
                    try? await env.taskStore.transition(id: id, to: StatusCycler.nextOnSpace(from: r.status))
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lillistMarkBlocked)) { _ in
            if let id = taskSelection {
                Task { try? await env.taskStore.transition(id: id, to: .blocked) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lillistToggleSidebar)) { _ in
            toggleSidebar()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lillistSelectTodayFilter)) { _ in
            Task {
                if let today = try? await env.smartFilterStore.fetch(byName: "Today") {
                    sidebarSelection = .pinnedFilter(today.id)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lillistSelectFilter)) { note in
            if let id = note.userInfo?["id"] as? UUID {
                sidebarSelection = .pinnedFilter(id)
            }
        }
        .onChange(of: sidebarSelection) { _, new in
            uiState.sidebarSelection = new
            // Restore the remembered task selection for the new source
            // (or clear if none).
            taskSelection = new.flatMap { uiState.taskSelection(for: $0) }
            Task { await refreshPrincipalTitle(for: new) }
        }
        .onChange(of: taskSelection) { _, new in
            if let sel = sidebarSelection {
                uiState.setTaskSelection(new, for: sel)
            }
            // If the principal title shows the selected task's title
            // (the `.pinnedTask` case), re-resolve on selection change
            // so renames in the detail pane flow up.
            if case .pinnedTask = sidebarSelection {
                Task { await refreshPrincipalTitle(for: sidebarSelection) }
            }
        }
        .task {
            await pruneStaleSidebarSelectionIfNeeded()
            await refreshPrincipalTitle(for: sidebarSelection)
        }
        .focusedValue(\.listColumn, focusedColumn)
    }

    /// Clear `sidebarSelection` if its underlying record was deleted
    /// between launches (CloudKit sync from another device, or a
    /// destructive action on the CLI). Resolves a single store fetch
    /// based on the current selection's UUID — cheap, no scan.
    /// Plan: state-restoration audit.
    private func pruneStaleSidebarSelectionIfNeeded() async {
        guard let current = sidebarSelection else { return }
        let stillExists: Bool
        switch current {
        case .pinnedTask(let id):
            stillExists = (try? await env.taskStore.fetch(id: id)) != nil
        case .pinnedFilter(let id), .filter(let id):
            stillExists = (try? await env.smartFilterStore.fetch(id: id)) != nil
        case .tag(let id):
            stillExists = (try? await env.tagStore.fetch(id: id)) != nil
        case .trash:
            stillExists = true
        }
        if !stillExists {
            sidebarSelection = nil
            uiState.sidebarSelection = nil
        }
    }

    private func refreshPrincipalTitle(for selection: SidebarSelection?) async {
        guard let selection else {
            resolvedPrincipalTitle = "Lillist"
            return
        }
        resolvedPrincipalTitle = await SourceTitleResolver.resolve(
            for: selection,
            taskStore: env.taskStore,
            tagStore: env.tagStore,
            smartFilterStore: env.smartFilterStore
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Sidebar toggle. NavigationSplitView ships its own affordance
        // on Tahoe, but binding a button to columnVisibility lets us
        // persist the user's choice and expose a stable target for the
        // ⌃⌘S menu command (Task 29).
        ToolbarItem(placement: .navigation) {
            Button {
                toggleSidebar()
            } label: {
                Image(systemName: "sidebar.left")
            }
            .help("Toggle sidebar")
            .accessibilityLabel(String(localized: "Toggle sidebar"))
        }

        // Principal: the source title. TaskListHeaderView used to own
        // this; the toolbar is the right home so it survives column
        // collapse and matches Mac Mail / Notes / Reminders.
        // Plan 19 Task 7: title is resolved to the actual tag/filter/task
        // name via `SourceTitleResolver` rather than a generic kind
        // string; the same resolver feeds `.navigationTitle` on
        // `TaskListView`, so toolbar and window-chrome stay in lockstep.
        ToolbarItem(placement: .principal) {
            Text(resolvedPrincipalTitle)
                .font(.headline)
        }

        // Primary actions: + New Task and the sort menu. The Sort
        // menu used to live inside TaskListHeaderView's right side;
        // hoisting it here gives it standard chrome placement.
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                NotificationCenter.default.post(name: .lillistNewTask, object: nil)
            } label: {
                Label("New Task", systemImage: "plus")
            }
            .help("New Task (⌘N)")
            .keyboardShortcut("n", modifiers: [.command])

            TaskListSortControl(field: $sortField, ascending: $sortAscending)
        }

        // Status: the sync dot. SidebarView's safeAreaInset placement
        // is replaced by this — Task 1 deletes the inset block in
        // SidebarView.swift in the same commit.
        ToolbarItem(placement: .status) {
            SyncStatusDotView(indicator: env.syncMonitor.indicator) {
                Task { await env.syncMonitor.retry() }
            }
        }
    }

    private func toggleSidebar() {
        let current = Self.parseVisibility(columnVisibilityRaw)
        let next = current == .all
            ? NavigationSplitViewVisibility.doubleColumn
            : NavigationSplitViewVisibility.all
        let apply = { columnVisibilityRaw = Self.encodeVisibility(next) }
        if reduceMotion {
            apply()
        } else {
            withAnimation(.easeInOut(duration: 0.18)) { apply() }
        }
    }

}
