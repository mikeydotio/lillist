import SwiftUI
import LillistCore
import LillistUI

struct TaskListView: View {
    @Environment(AppEnvironment.self) private var env
    let selection: SidebarSelection
    @Binding var taskSelection: UUID?
    @Binding var sortField: SortField
    @Binding var sortAscending: Bool

    @State private var uiState = UIStatePersistence()
    @State private var rootNodes: [TaskOutlineNode] = []
    @State private var flatResults: [TaskStore.TaskRecord] = []
    @State private var breadcrumbsByID: [UUID: [String]] = [:]
    @State private var inlineCreateText = ""
    @State private var showInlineCreate = false
    @State private var inlineCreateParent: UUID?
    @State private var resolvedSourceTitle: String = ""

    private var sourceKey: String {
        switch selection {
        case .pinnedTask(let id):   return "pinnedTask.\(id)"
        case .pinnedFilter(let id): return "pinnedFilter.\(id)"
        case .tag(let id):          return "tag.\(id)"
        case .filter(let id):       return "filter.\(id)"
        case .trash:                return "trash"
        }
    }

    private var isFlat: Bool {
        switch selection {
        case .filter, .pinnedFilter, .trash: return true
        case .tag, .pinnedTask: return false
        }
    }

    private var sourceTitle: String {
        resolvedSourceTitle.isEmpty ? defaultTitleFallback : resolvedSourceTitle
    }

    private var defaultTitleFallback: String {
        switch selection {
        case .pinnedTask:    return "Pinned task"
        case .pinnedFilter:  return "Pinned filter"
        case .tag:           return "Tag"
        case .filter:        return "Filter"
        case .trash:         return "Trash"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isFlat {
                if flatResults.isEmpty {
                    EmptyStateView(
                        title: "No matching tasks",
                        message: emptyMessage,
                        systemImage: "magnifyingglass"
                    )
                } else {
                    List(selection: $taskSelection) {
                        ForEach(flatResults, id: \.id) { rec in
                            VStack(alignment: .leading, spacing: 2) {
                                if let crumbs = breadcrumbsByID[rec.id], !crumbs.isEmpty {
                                    BreadcrumbView(path: crumbs)
                                }
                                TaskRowView(
                                    task: rec,
                                    tagNames: [],
                                    onStatusClick: { cycle(rec.id, rec.status, click: true) },
                                    onStatusSet: { newStatus in setStatus(rec.id, to: newStatus) }
                                )
                            }
                            .tag(rec.id)
                        }
                    }
                }
            } else {
                if rootNodes.isEmpty && !showInlineCreate {
                    EmptyStateView(title: "Nothing here yet",
                                   message: "Press ⌘N to create the first task.",
                                   systemImage: "plus.circle")
                } else {
                    List(selection: $taskSelection) {
                        OutlineGroup(rootNodes, children: \.children) { node in
                            TaskRowView(
                                task: node.record,
                                tagNames: [],
                                onStatusClick: { cycle(node.id, node.record.status, click: true) },
                                onStatusSet: { newStatus in setStatus(node.id, to: newStatus) }
                            )
                            .tag(node.id)
                            .onDrop(of: [.lillistTask], delegate: TaskDropDelegate(
                                targetTaskID: node.id,
                                rowHeight: 44,
                                onReorder: { dragged, before in
                                    Task { await reorder(dragged: dragged, target: node.id, before: before) }
                                },
                                onReparent: { dragged, newParent in
                                    Task { await reparent(dragged: dragged, newParent: newParent) }
                                }
                            ))
                            .draggable(TaskDragPayload(taskID: node.id))
                        }
                        if showInlineCreate {
                            InlineCreateField(
                                text: $inlineCreateText,
                                onReturn: { Task { await commitInlineCreate(asSiblingOf: inlineCreateParent) } },
                                onTab: { Task { await indentInlineCreate() } },
                                onShiftTab: { Task { await outdentInlineCreate() } },
                                onCancel: { showInlineCreate = false; inlineCreateText = "" }
                            )
                        }
                    }
                }
            }
        }
        .task(id: anchorIdentity) {
            if let saved = uiState.sort(for: sourceKey) {
                sortField = saved.0; sortAscending = saved.1
            }
            await refresh()
            resolvedSourceTitle = await SourceTitleResolver.resolve(
                for: selection,
                taskStore: env.taskStore,
                tagStore: env.tagStore,
                smartFilterStore: env.smartFilterStore
            )
        }
        .navigationTitle(sourceTitle)
        .onChange(of: sortField) { _, _ in
            uiState.setSort(sortField, ascending: sortAscending, for: sourceKey)
            Task { await refresh() }
        }
        .onChange(of: sortAscending) { _, _ in
            uiState.setSort(sortField, ascending: sortAscending, for: sourceKey)
            Task { await refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lillistNewTask)) { _ in
            showInlineCreate = true
            inlineCreateParent = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .lillistNewSibling)) { _ in
            showInlineCreate = true
            if let id = taskSelection {
                inlineCreateParent = id
            }
        }
    }

    private var emptyMessage: String {
        switch selection {
        case .filter, .pinnedFilter:
            return "This smart filter currently matches no tasks. Edit the predicate to see results."
        case .trash:
            return "The Trash is empty."
        default:
            return "Nothing to show."
        }
    }

    private var anchorIdentity: AnyHashable { AnyHashable("\(selection):\(sortField):\(sortAscending)") }

    private func refresh() async {
        do {
            switch selection {
            case .filter(let id), .pinnedFilter(let id):
                flatResults = try await env.smartFilterStore.evaluate(id: id)
                breadcrumbsByID = try await env.taskStore.breadcrumbs(for: flatResults.map(\.id))
                rootNodes = []
            case .trash:
                flatResults = try await env.taskStore.trashed()
                breadcrumbsByID = [:]
                rootNodes = []
            case .tag(let id):
                let recs = try await env.taskStore.tasks(
                    forTag: id,
                    includeDescendants: true,
                    sort: sortField,
                    ascending: sortAscending
                )
                rootNodes = try await buildTree(from: recs)
                flatResults = []
            case .pinnedTask(let id):
                let root = try await env.taskStore.fetch(id: id)
                let children = try await env.taskStore.children(of: id)
                rootNodes = [TaskOutlineNode(
                    id: root.id,
                    record: root,
                    children: children.map { TaskOutlineNode(id: $0.id, record: $0, children: nil) }
                )]
                flatResults = []
            }
        } catch { }
    }

    private func buildTree(from recs: [TaskStore.TaskRecord]) async throws -> [TaskOutlineNode] {
        var nodes: [TaskOutlineNode] = []
        for r in recs {
            let kids = try await env.taskStore.children(of: r.id)
            let kidNodes = kids.map { TaskOutlineNode(id: $0.id, record: $0, children: nil) }
            nodes.append(TaskOutlineNode(id: r.id, record: r, children: kidNodes.isEmpty ? nil : kidNodes))
        }
        return nodes
    }

    private func cycle(_ id: UUID, _ current: Status, click: Bool) {
        let next = click ? StatusCycler.nextOnClick(from: current) : StatusCycler.nextOnSpace(from: current)
        Task {
            try? await env.taskStore.transition(id: id, to: next)
            await refresh()
        }
    }

    private func setStatus(_ id: UUID, to newStatus: Status) {
        Task {
            try? await env.taskStore.transition(id: id, to: newStatus)
            await refresh()
        }
    }

    private func reorder(dragged: UUID, target: UUID, before: Bool) async {
        if before {
            try? await env.taskStore.reorder(id: dragged, after: nil, before: target)
        } else {
            try? await env.taskStore.reorder(id: dragged, after: target, before: nil)
        }
        await refresh()
    }

    private func reparent(dragged: UUID, newParent: UUID) async {
        try? await env.taskStore.reparent(id: dragged, newParent: newParent)
        await refresh()
    }

    private func commitInlineCreate(asSiblingOf siblingID: UUID?) async {
        let title = inlineCreateText.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { showInlineCreate = false; return }
        let parent: UUID?
        if let sid = siblingID, let s = try? await env.taskStore.fetch(id: sid) {
            parent = s.parentID
        } else {
            parent = nil
        }
        _ = try? await env.taskStore.create(title: title, parent: parent)
        inlineCreateText = ""
        await refresh()
    }

    private func indentInlineCreate() async {
        let title = inlineCreateText.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        if let prevSibling = inlineCreateParent ?? rootNodes.last?.id {
            _ = try? await env.taskStore.create(title: title, parent: prevSibling)
            inlineCreateText = ""
            await refresh()
        }
    }

    private func outdentInlineCreate() async {
        let title = inlineCreateText.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, let parentID = inlineCreateParent else { return }
        let parent = try? await env.taskStore.fetch(id: parentID)
        _ = try? await env.taskStore.create(title: title, parent: parent?.parentID)
        inlineCreateText = ""
        await refresh()
    }
}
