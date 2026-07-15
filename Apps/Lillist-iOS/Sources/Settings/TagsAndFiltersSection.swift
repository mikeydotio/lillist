import SwiftUI
import LillistCore
import LillistUI

/// Owns the load + mutation lifecycle for the Tags & Filters management screen.
///
/// Lifted out of the view (like `ICloudSyncModalsModel`) so the `.sheet(item:)`
/// edit modal is hosted by the **page** (`TagsAndFiltersPage`) on the stable
/// `SettingsDetailScreen` container: a sheet attached to `Section`/Form-row content
/// inside a pushed nav-destination-in-a-sheet present-then-dismisses and tears the
/// whole Settings sheet down with it (see `docs/engineering-notes.md`).
///
/// Store failures surface on `errorMessage` (shown as an alert by the page) rather
/// than being swallowed.
@MainActor
@Observable
final class TagsAndFiltersModel {
    var tags: [TagNode] = []
    var filters: [SavedFilterRow] = []
    var route: TagsFiltersEditRoute?
    var errorMessage: String?

    func load(_ env: AppEnvironment) async {
        do {
            tags = try await TagTreeLoader.flattenedTags { parent in
                try await env.tagStore.children(of: parent).map {
                    FlatTagInput(id: $0.id, name: $0.name, tintHex: $0.tintColor, parentID: $0.parentID, position: $0.position)
                }
            }
            filters = try await env.smartFilterStore.list().map {
                SavedFilterRow(id: $0.id, name: $0.name, tintHex: $0.tintColor, isPinned: $0.isPinned)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveTag(_ node: TagNode, name: String, hex: String?, _ env: AppEnvironment) {
        route = nil
        Task {
            do {
                if name != node.name { try await env.tagStore.rename(id: node.id, to: name) }
                if hex != node.tintHex { try await env.tagStore.setTintColor(id: node.id, hex: hex) }
                await load(env)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func deleteTag(_ node: TagNode, _ env: AppEnvironment) {
        route = nil
        Task {
            do { try await env.tagStore.delete(id: node.id); await load(env) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func saveFilter(_ row: SavedFilterRow, name: String, _ env: AppEnvironment) {
        route = nil
        Task {
            do {
                if name != row.name { try await env.smartFilterStore.update(id: row.id) { $0.name = name } }
                await load(env)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func deleteFilter(_ row: SavedFilterRow, _ env: AppEnvironment) {
        route = nil
        Task {
            do { try await env.smartFilterStore.delete(id: row.id); await load(env) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func setFilterPinned(_ id: UUID, _ pinned: Bool, _ env: AppEnvironment) {
        Task {
            do { try await env.smartFilterStore.setPinned(id: id, pinned: pinned); await load(env) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

/// iOS-side wrapper that pipes `AppEnvironment` stores into the cross-platform
/// `LillistUI.TagsAndFiltersSettingsSection`. Renders the two management sections;
/// the edit modal is hosted by `TagsAndFiltersPage`.
struct TagsAndFiltersSection: View {
    @Environment(AppEnvironment.self) private var environment
    @Bindable var model: TagsAndFiltersModel

    var body: some View {
        TagsAndFiltersSettingsSection(viewState: viewState, actions: actions)
            .task { await model.load(environment) }
    }

    private var viewState: TagsAndFiltersSettingsSection.ViewState {
        .init(tags: model.tags, filters: model.filters)
    }

    private var actions: TagsAndFiltersSettingsSection.Actions {
        .init(
            editTag: { model.route = .tag($0) },
            editFilter: { model.route = .filter($0) },
            setFilterPinned: { model.setFilterPinned($0, $1, environment) }
        )
    }
}
