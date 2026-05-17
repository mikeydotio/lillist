import Foundation
import SwiftUI

/// Stores the last 10 distinct search queries, most-recent-first.
/// Backed by `UserDefaults` so values survive relaunch (per-app
/// persistence — not per-window, since searches are an account-level
/// concept and the iPad-multi-window case wants shared recents).
///
/// Plan 16: surfaces `searchSuggestions` on the Search screen.
@Observable
final class RecentSearchesStore {
    private let key = "lillist.recentSearches"
    private let maxCount = 10
    private(set) var recent: [String] = []

    init() {
        recent = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func record(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = recent.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        list.insert(trimmed, at: 0)
        if list.count > maxCount {
            list = Array(list.prefix(maxCount))
        }
        recent = list
        UserDefaults.standard.set(list, forKey: key)
    }

    func clear() {
        recent = []
        UserDefaults.standard.removeObject(forKey: key)
    }
}
