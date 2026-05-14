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
}
