import SwiftUI
import LillistCore
import LillistUI

struct RootSplitView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var uiState = UIStatePersistence()
    @State private var sidebarSelection: SidebarSelection?
    @State private var taskSelection: UUID?
    @FocusState private var focusedColumn: ListColumn?

    init() {
        let persisted = UIStatePersistence().sidebarSelection
        _sidebarSelection = State(initialValue: persisted)
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $sidebarSelection)
                .focused($focusedColumn, equals: .sidebar)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } content: {
            if let sel = sidebarSelection {
                TaskListView(selection: sel, taskSelection: $taskSelection)
                    .focused($focusedColumn, equals: .list)
                    .navigationSplitViewColumnWidth(min: 320, ideal: 460)
            } else {
                EmptyStateView(title: "Select a source", message: "Pick a pinned item, tag, or filter from the sidebar.")
            }
        } detail: {
            if let id = taskSelection {
                TaskDetailView(taskID: id)
                    .focused($focusedColumn, equals: .detail)
            } else {
                NoSelectionDetailView()
            }
        }
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
        .onChange(of: sidebarSelection) { _, new in uiState.sidebarSelection = new }
        .focusedValue(\.listColumn, focusedColumn)
    }
}
