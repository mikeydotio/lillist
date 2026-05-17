import SwiftUI
import LillistCore
import LillistUI

struct RootSplitView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var uiState = UIStatePersistence()
    @State private var sidebarSelection: SidebarSelection?
    @State private var taskSelection: UUID?
    @SceneStorage("lillist.ui.columnVisibility") private var columnVisibilityRaw: String = "all"
    @State private var sortField: SortField = .deadline
    @State private var sortAscending: Bool = true
    @FocusState private var focusedColumn: ListColumn?

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

    var body: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            SidebarView(selection: $sidebarSelection)
                .focused($focusedColumn, equals: .sidebar)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } content: {
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
        } detail: {
            if let id = taskSelection {
                TaskDetailView(taskID: id)
                    .focused($focusedColumn, equals: .detail)
                    .navigationSplitViewColumnWidth(min: 360, ideal: 520)
            } else {
                NoSelectionDetailView()
                    .navigationSplitViewColumnWidth(min: 360, ideal: 520)
            }
        }
        .toolbar { toolbarContent }
        .onAppear { focusedColumn = .list }
        .onReceive(NotificationCenter.default.publisher(for: .lillistFocusSidebar)) { _ in focusedColumn = .sidebar }
        .onReceive(NotificationCenter.default.publisher(for: .lillistFocusList)) { _ in focusedColumn = .list }
        .onReceive(NotificationCenter.default.publisher(for: .lillistFocusDetail)) { _ in focusedColumn = .detail }
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
            withAnimation(.easeInOut(duration: 0.18)) {
                let current = Self.parseVisibility(columnVisibilityRaw)
                columnVisibilityRaw = Self.encodeVisibility(
                    current == .all ? .doubleColumn : .all
                )
            }
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
        }
        .onChange(of: taskSelection) { _, new in
            if let sel = sidebarSelection {
                uiState.setTaskSelection(new, for: sel)
            }
        }
        .focusedValue(\.listColumn, focusedColumn)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Sidebar toggle. NavigationSplitView ships its own affordance
        // on Tahoe, but binding a button to columnVisibility lets us
        // persist the user's choice and expose a stable target for the
        // ⌃⌘S menu command (Task 29).
        ToolbarItem(placement: .navigation) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    let current = Self.parseVisibility(columnVisibilityRaw)
                    columnVisibilityRaw = Self.encodeVisibility(
                        current == .all ? .doubleColumn : .all
                    )
                }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .help("Toggle sidebar")
            .accessibilityLabel(String(localized: "Toggle sidebar"))
        }

        // Principal: the source title. TaskListHeaderView used to own
        // this; the toolbar is the right home so it survives column
        // collapse and matches Mac Mail / Notes / Reminders.
        ToolbarItem(placement: .principal) {
            Text(sidebarSelection.map(principalTitle(for:)) ?? "Lillist")
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

    private func principalTitle(for selection: SidebarSelection) -> String {
        switch selection {
        case .pinnedTask:    return "Pinned task"
        case .pinnedFilter:  return "Pinned filter"
        case .tag:           return "Tag"
        case .filter:        return "Filter"
        case .trash:         return "Trash"
        }
    }
}
