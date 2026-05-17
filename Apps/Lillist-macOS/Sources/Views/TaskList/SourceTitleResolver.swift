import Foundation
import LillistCore

/// Resolves a `SidebarSelection` to the actual user-facing name of the
/// selected source (e.g. "Buy milk" for a pinned task, "Today" for a
/// filter, "groceries" for a tag). When a referent ID has been deleted
/// out from under the selection, falls back to the generic kind string
/// so the title bar never goes blank.
///
/// Lifted out of `TaskListView` so the resolver is testable from the
/// standalone macOS test bundle without pulling SwiftUI/AppEnvironment
/// into the test target — pattern matches `QuickCapturePlacementMath`
/// (Plan 15 Task 13).
enum SourceTitleResolver {
    static func resolve(
        for selection: SidebarSelection,
        taskStore: TaskStore,
        tagStore: TagStore,
        smartFilterStore: SmartFilterStore
    ) async -> String {
        switch selection {
        case .pinnedTask(let id):
            return (try? await taskStore.fetch(id: id))?.title ?? "Pinned task"
        case .pinnedFilter(let id):
            return (try? await smartFilterStore.list().first(where: { $0.id == id }))?.name ?? "Pinned filter"
        case .filter(let id):
            return (try? await smartFilterStore.list().first(where: { $0.id == id }))?.name ?? "Filter"
        case .tag(let id):
            return (try? await tagStore.fetch(id: id))?.name ?? "Tag"
        case .trash:
            return "Trash"
        }
    }
}
