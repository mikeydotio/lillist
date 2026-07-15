import SwiftUI
import LillistCore
import LillistUI

/// macOS Preferences pane mirroring the iOS `TagsAndFiltersSection`. Pipes
/// `AppEnvironment` stores into the cross-platform `TagsAndFiltersSettingsSection`
/// and owns the edit-sheet state. Store failures surface on `errorMessage` rather
/// than being swallowed.
///
/// Unlike the self-sizing (`.fixedSize()`) panes, this one pins a fixed height so a
/// long tag/filter list scrolls inside the pane instead of growing the window
/// unboundedly.
struct TagsAndFiltersPane: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var tags: [TagNode] = []
    @State private var filters: [SavedFilterRow] = []
    @State private var route: TagsFiltersEditRoute?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            TagsAndFiltersSettingsSection(viewState: viewState, actions: actions)
        }
        .formStyle(.grouped)
        .frame(width: PreferencesMetrics.contentWidth, height: 460)
        .task { await load() }
        .sheet(item: $route) { route in
            editSheet(for: route)
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ),
            presenting: errorMessage
        ) { _ in
            Button("OK") { errorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    private var viewState: TagsAndFiltersSettingsSection.ViewState {
        .init(tags: tags, filters: filters)
    }

    private var actions: TagsAndFiltersSettingsSection.Actions {
        .init(
            editTag: { route = .tag($0) },
            editFilter: { route = .filter($0) },
            setFilterPinned: { id, pinned in Task { await setFilterPinned(id, pinned) } }
        )
    }

    @ViewBuilder
    private func editSheet(for route: TagsFiltersEditRoute) -> some View {
        switch route {
        case .tag(let node):
            TagEditorSheet(
                name: node.name,
                tintHex: node.tintHex,
                descendantCount: node.descendantCount,
                onSave: { name, hex in Task { await saveTag(node, name: name, hex: hex) } },
                onDelete: { Task { await deleteTag(node) } },
                onCancel: { self.route = nil }
            )
        case .filter(let row):
            FilterEditorSheet(
                name: row.name,
                onSave: { name in Task { await saveFilter(row, name: name) } },
                onDelete: { Task { await deleteFilter(row) } },
                onCancel: { self.route = nil }
            )
        }
    }

    // MARK: - Store lifecycle

    private func load() async {
        do {
            tags = try await TagTreeLoader.flattenedTags { parent in
                try await environment.tagStore.children(of: parent).map {
                    FlatTagInput(id: $0.id, name: $0.name, tintHex: $0.tintColor, parentID: $0.parentID, position: $0.position)
                }
            }
            filters = try await environment.smartFilterStore.list().map {
                SavedFilterRow(id: $0.id, name: $0.name, tintHex: $0.tintColor, isPinned: $0.isPinned)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveTag(_ node: TagNode, name: String, hex: String?) async {
        route = nil
        do {
            if name != node.name { try await environment.tagStore.rename(id: node.id, to: name) }
            if hex != node.tintHex { try await environment.tagStore.setTintColor(id: node.id, hex: hex) }
            await load()
        } catch { errorMessage = error.localizedDescription }
    }

    private func deleteTag(_ node: TagNode) async {
        route = nil
        do { try await environment.tagStore.delete(id: node.id); await load() }
        catch { errorMessage = error.localizedDescription }
    }

    private func saveFilter(_ row: SavedFilterRow, name: String) async {
        route = nil
        do {
            if name != row.name { try await environment.smartFilterStore.update(id: row.id) { $0.name = name } }
            await load()
        } catch { errorMessage = error.localizedDescription }
    }

    private func deleteFilter(_ row: SavedFilterRow) async {
        route = nil
        do { try await environment.smartFilterStore.delete(id: row.id); await load() }
        catch { errorMessage = error.localizedDescription }
    }

    private func setFilterPinned(_ id: UUID, _ pinned: Bool) async {
        do { try await environment.smartFilterStore.setPinned(id: id, pinned: pinned); await load() }
        catch { errorMessage = error.localizedDescription }
    }
}
