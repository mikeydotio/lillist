import SwiftUI
import CoreData
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

    // Plan 19 Task 6: context-menu editor sheet targets.
    @State private var renamingPinnedTask: TaskStore.TaskRecord?
    @State private var renamingFilter: SmartFilterStore.SmartFilterRecord?
    @State private var renamingTag: TagStore.TagRecord?
    @State private var changingTagColor: TagStore.TagRecord?

    var body: some View {
        List(selection: $selection) {
            Section("Pinned") {
                ForEach(pinnedTasks, id: \.id) { task in
                    SidebarRowView(icon: "pin.fill", label: task.title, kind: .task,
                                   isSelected: selection == .pinnedTask(task.id))
                        .tag(SidebarSelection.pinnedTask(task.id))
                        .contextMenu {
                            Button("Rename…") { renamingPinnedTask = task }
                            Button("Unpin") {
                                Task {
                                    try? await env.taskStore.update(id: task.id) { $0.isPinned = false }
                                    await refresh()
                                }
                            }
                        }
                }
                ForEach(pinnedFilters, id: \.id) { f in
                    SidebarRowView(icon: "line.3.horizontal.decrease.circle", label: f.name, kind: .smartFilter,
                                   isSelected: selection == .pinnedFilter(f.id))
                        .tag(SidebarSelection.pinnedFilter(f.id))
                        .contextMenu {
                            Button("Rename…") { renamingFilter = f }
                            Divider()
                            Button("Delete", role: .destructive) {
                                Task {
                                    try? await env.smartFilterStore.delete(id: f.id)
                                    await refresh()
                                }
                            }
                        }
                }
            }

            Section("Tags") {
                ForEach(rootTags, id: \.id) { tag in
                    TagDisclosureView(
                        tag: tag,
                        expanded: $expandedTags,
                        selection: $selection,
                        renamingTag: $renamingTag,
                        changingTagColor: $changingTagColor,
                        onMutation: { Task { await refresh() } }
                    )
                }
            }

            Section("Filters") {
                ForEach(nonPinnedFilters, id: \.id) { f in
                    SidebarRowView(icon: "line.3.horizontal.decrease.circle", label: f.name, kind: .smartFilter,
                                   isSelected: selection == .filter(f.id))
                        .tag(SidebarSelection.filter(f.id))
                        .contextMenu {
                            Button("Rename…") { renamingFilter = f }
                            Divider()
                            Button("Delete", role: .destructive) {
                                Task {
                                    try? await env.smartFilterStore.delete(id: f.id)
                                    await refresh()
                                }
                            }
                        }
                }
            }

            Section {
                SidebarRowView(icon: "trash", label: "Trash", badge: trashCount > 0 ? trashCount : nil, kind: .trash,
                               isSelected: selection == .trash)
                    .tag(SidebarSelection.trash)
            }
        }
        .listStyle(.sidebar)
        .task { await refresh() }
        // Build-version footer (moved here from the content pane — a
        // Mac-native sidebar-bottom spot; useful during alpha).
        .safeAreaInset(edge: .bottom) {
            BuildVersionLabel(version: env.buildVersion)
                .padding(.bottom, LillistSpacing.xs)
        }
        // Refresh on every Core Data save (the same signal AppDelegate uses
        // for the dock badge). Without this the sidebar only ran its one-shot
        // `.task` refresh, so freshly-installed default filters/tags (first
        // launch) or CLI/CloudKit-driven changes wouldn't appear until
        // relaunch. See docs/reviews/2026-06-23.
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { _ in
            Task { await refresh() }
        }
        .sheet(item: $renamingPinnedTask) { task in
            RenameSheet(title: "Rename Task", initialValue: task.title) { newName in
                try? await env.taskStore.update(id: task.id) { $0.title = newName }
                await refresh()
            }
        }
        .sheet(item: $renamingFilter) { filter in
            RenameSheet(title: "Rename Filter", initialValue: filter.name) { newName in
                try? await env.smartFilterStore.update(id: filter.id) { $0.name = newName }
                await refresh()
            }
        }
        .sheet(item: $renamingTag) { tag in
            RenameSheet(title: "Rename Tag", initialValue: tag.name) { newName in
                try? await env.tagStore.rename(id: tag.id, to: newName)
                await refresh()
            }
        }
        .sheet(item: $changingTagColor) { tag in
            TagColorSheet(initialHex: tag.tintColor) { newHex in
                try? await env.tagStore.setTintColor(id: tag.id, hex: newHex)
                await refresh()
            }
        }
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
    @Binding var renamingTag: TagStore.TagRecord?
    @Binding var changingTagColor: TagStore.TagRecord?
    let onMutation: () -> Void
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
                TagDisclosureView(
                    tag: child,
                    expanded: $expanded,
                    selection: $selection,
                    renamingTag: $renamingTag,
                    changingTagColor: $changingTagColor,
                    onMutation: onMutation
                )
            }
        } label: {
            SidebarRowView(
                icon: "tag.fill",
                label: tag.name,
                tint: TagTint(hex: tag.tintColor),
                kind: .tag,
                isSelected: selection == .tag(tag.id)
            )
            .tag(SidebarSelection.tag(tag.id))
            .contextMenu {
                Button("Rename…") { renamingTag = tag }
                Button("Change Color…") { changingTagColor = tag }
                Divider()
                Button("Delete", role: .destructive) {
                    Task {
                        try? await env.tagStore.delete(id: tag.id)
                        onMutation()
                    }
                }
            }
        }
        .task {
            children = (try? await env.tagStore.children(of: tag.id)) ?? []
        }
    }
}

// MARK: - Rename / color editor sheets

private struct RenameSheet: View {
    let title: String
    let initialValue: String
    let onSave: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(title: String, initialValue: String, onSave: @escaping (String) async -> Void) {
        self.title = title
        self.initialValue = initialValue
        self.onSave = onSave
        _text = State(initialValue: initialValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            TextField("Name", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit { Task { await save() } }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }

    private func save() async {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != initialValue else { dismiss(); return }
        await onSave(trimmed)
        dismiss()
    }
}

private struct TagColorSheet: View {
    let initialHex: String?
    let onSave: (String?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var color: Color

    init(initialHex: String?, onSave: @escaping (String?) async -> Void) {
        self.initialHex = initialHex
        self.onSave = onSave
        _color = State(initialValue: Color(hex: initialHex) ?? .gray)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Change Tag Color").font(.headline)
            ColorPicker("Tint", selection: $color, supportsOpacity: false)
                .frame(width: 280)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private func save() async {
        await onSave(color.toHex())
        dismiss()
    }
}

// `Identifiable` is required by `.sheet(item:)`. The record types from
// the LillistCore stores already carry stable UUIDs, so a one-line
// extension covers the requirement without exposing internal state.
extension TaskStore.TaskRecord: @retroactive Identifiable {}
extension SmartFilterStore.SmartFilterRecord: @retroactive Identifiable {}
extension TagStore.TagRecord: @retroactive Identifiable {}
