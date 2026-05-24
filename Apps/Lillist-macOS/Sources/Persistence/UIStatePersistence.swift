import Foundation
import LillistCore

/// Per-machine UI state. Stored in UserDefaults. Not synced (design Section 7).
@MainActor
final class UIStatePersistence {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private enum Key {
        static let sidebarSelection = "lillist.ui.sidebarSelection"
        static let expandedTagIDs   = "lillist.ui.expandedTagIDs"
        static let sortPerSource    = "lillist.ui.sortPerSource"   // [sourceID: "field|asc"]
        // Plan 15: per-source task selection. Key is a `SidebarSelection`
        // string representation (matching `TaskListView.sourceKey`), value
        // is a UUID string. Lookups return `nil` if the selection
        // hasn't been seen yet or was explicitly cleared.
        static let taskSelection    = "lillist.ui.taskSelection"
    }

    var sidebarSelection: SidebarSelection? {
        get {
            guard let data = defaults.data(forKey: Key.sidebarSelection) else { return nil }
            return try? JSONDecoder().decode(SidebarSelection.self, from: data)
        }
        set {
            guard let v = newValue, let data = try? JSONEncoder().encode(v) else {
                defaults.removeObject(forKey: Key.sidebarSelection); return
            }
            defaults.set(data, forKey: Key.sidebarSelection)
        }
    }

    var expandedTagIDs: Set<UUID> {
        get {
            guard let arr = defaults.array(forKey: Key.expandedTagIDs) as? [String] else { return [] }
            return Set(arr.compactMap(UUID.init(uuidString:)))
        }
        set {
            defaults.set(newValue.map(\.uuidString), forKey: Key.expandedTagIDs)
        }
    }

    func sort(for source: String) -> (SortField, Bool)? {
        guard let dict = defaults.dictionary(forKey: Key.sortPerSource) as? [String: String],
              let raw = dict[source] else { return nil }
        let parts = raw.split(separator: "|")
        guard parts.count == 2,
              let field = SortField(rawValue: String(parts[0])) else { return nil }
        return (field, parts[1] == "asc")
    }

    func setSort(_ field: SortField, ascending: Bool, for source: String) {
        var dict = (defaults.dictionary(forKey: Key.sortPerSource) as? [String: String]) ?? [:]
        dict[source] = "\(field.rawValue)|\(ascending ? "asc" : "desc")"
        defaults.set(dict, forKey: Key.sortPerSource)
    }

    /// Last task ID the user selected while viewing `source`. Returns
    /// `nil` if the user hasn't yet selected anything in this source or
    /// explicitly cleared the selection (see `setTaskSelection(_:for:)`).
    func taskSelection(for source: SidebarSelection) -> UUID? {
        let key = Self.persistenceKey(for: source)
        guard let dict = defaults.dictionary(forKey: Key.taskSelection) as? [String: String],
              let raw = dict[key] else { return nil }
        return UUID(uuidString: raw)
    }

    /// Sets the remembered task selection for `source`. Pass `nil` to
    /// clear (e.g. when the selected task is deleted).
    func setTaskSelection(_ id: UUID?, for source: SidebarSelection) {
        let key = Self.persistenceKey(for: source)
        var dict = (defaults.dictionary(forKey: Key.taskSelection) as? [String: String]) ?? [:]
        if let id {
            dict[key] = id.uuidString
        } else {
            dict.removeValue(forKey: key)
        }
        defaults.set(dict, forKey: Key.taskSelection)
    }

    /// Canonical string key for a `SidebarSelection`. Mirrors
    /// `TaskListView.sourceKey` so the sort and task-selection
    /// dictionaries can share the same notion of "source identity."
    private static func persistenceKey(for source: SidebarSelection) -> String {
        switch source {
        case .pinnedTask(let id):   return "pinnedTask.\(id.uuidString)"
        case .pinnedFilter(let id): return "pinnedFilter.\(id.uuidString)"
        case .tag(let id):          return "tag.\(id.uuidString)"
        case .filter(let id):       return "filter.\(id.uuidString)"
        case .trash:                return "trash"
        }
    }

    /// Clear `sidebarSelection` if its UUID no longer resolves in the
    /// live stores. CloudKit sync can delete the underlying filter,
    /// tag, or task between launches; without this, `RootSplitView`
    /// would briefly highlight a phantom row in the sidebar before the
    /// `TaskListView` resolved to "not found".
    ///
    /// Existence checks are passed in as closures so this method
    /// stays sync and the caller decides how to resolve IDs (typically
    /// by `try? await store.fetch(id:)`).
    /// Plan: state-restoration audit.
    func pruneStaleSidebarSelection(
        filterExists: (UUID) -> Bool,
        tagExists: (UUID) -> Bool,
        taskExists: (UUID) -> Bool
    ) {
        guard let current = sidebarSelection else { return }
        let resolves: Bool
        switch current {
        case .pinnedTask(let id):   resolves = taskExists(id)
        case .pinnedFilter(let id): resolves = filterExists(id)
        case .tag(let id):          resolves = tagExists(id)
        case .filter(let id):       resolves = filterExists(id)
        case .trash:                resolves = true
        }
        if !resolves {
            sidebarSelection = nil
        }
    }
}
