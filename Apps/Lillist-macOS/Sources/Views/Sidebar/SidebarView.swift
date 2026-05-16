import SwiftUI
import LillistCore
import LillistUI

struct SidebarView: View {
    @Environment(AppEnvironment.self) private var env
    @Binding var selection: SidebarSelection?

    @State private var pinnedTasks: [TaskStore.TaskRecord] = []
    @State private var pinnedFilters: [SmartFilterStore.SmartFilterRecord] = []
    @State private var rootTags: [TagStore.TagRecord] = []
    @State private var nonPinnedFilters: [SmartFilterStore.SmartFilterRecord] = []
    @State private var trashCount: Int = 0
    @State private var expandedTags: Set<UUID> = []

    var body: some View {
        List(selection: $selection) {
            Section("Pinned") {
                ForEach(pinnedTasks, id: \.id) { task in
                    SidebarRowView(icon: "pin.fill", label: task.title, kind: .task)
                        .tag(SidebarSelection.pinnedTask(task.id))
                }
                ForEach(pinnedFilters, id: \.id) { f in
                    SidebarRowView(icon: "line.3.horizontal.decrease.circle", label: f.name, kind: .smartFilter)
                        .tag(SidebarSelection.pinnedFilter(f.id))
                }
            }

            Section("Tags") {
                ForEach(rootTags, id: \.id) { tag in
                    TagDisclosureView(tag: tag, expanded: $expandedTags, selection: $selection)
                }
            }

            Section("Filters") {
                ForEach(nonPinnedFilters, id: \.id) { f in
                    SidebarRowView(icon: "line.3.horizontal.decrease.circle", label: f.name, kind: .smartFilter)
                        .tag(SidebarSelection.filter(f.id))
                }
            }

            Section {
                SidebarRowView(icon: "trash", label: "Trash", badge: trashCount > 0 ? trashCount : nil, kind: .trash)
                    .tag(SidebarSelection.trash)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                SyncStatusDotView(indicator: env.syncMonitor.indicator) {
                    Task { await env.syncMonitor.retry() }
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
        .task { await refresh() }
    }

    private func refresh() async {
        do {
            pinnedTasks = try await env.taskStore.pinned()
            let allFilters = try await env.smartFilterStore.list()
            pinnedFilters = allFilters.filter(\.isPinned)
            nonPinnedFilters = allFilters.filter { !$0.isPinned }
            rootTags = try await env.tagStore.children(of: nil)
            trashCount = try await env.taskStore.trashed().count
        } catch {
            // Surface in a banner later; sidebar stays empty for now.
        }
    }
}

private struct TagDisclosureView: View {
    let tag: TagStore.TagRecord
    @Binding var expanded: Set<UUID>
    @Binding var selection: SidebarSelection?
    @Environment(AppEnvironment.self) private var env
    @State private var children: [TagStore.TagRecord] = []

    var body: some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expanded.contains(tag.id) },
                set: { isOn in
                    if isOn { expanded.insert(tag.id) } else { expanded.remove(tag.id) }
                }
            )
        ) {
            ForEach(children, id: \.id) { child in
                TagDisclosureView(tag: child, expanded: $expanded, selection: $selection)
            }
        } label: {
            SidebarRowView(
                icon: "tag.fill",
                label: tag.name,
                tint: TagTint(hex: tag.tintColor),
                kind: .tag
            )
            .tag(SidebarSelection.tag(tag.id))
        }
        .task {
            children = (try? await env.tagStore.children(of: tag.id)) ?? []
        }
    }
}
