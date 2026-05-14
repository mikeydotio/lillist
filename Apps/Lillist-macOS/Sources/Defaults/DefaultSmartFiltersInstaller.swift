import Foundation
import LillistCore

/// Runs once on first launch (idempotent on subsequent launches) and asks
/// `SmartFilterStore` to install the five default filters from design Section 7:
/// Today, This Week, No Tags, Recently Closed, Stale.
@MainActor
enum DefaultSmartFiltersInstaller {
    private static let installedKey = "lillist.defaultFiltersInstalled"

    static func installIfNeeded(store: SmartFilterStore,
                                defaults: UserDefaults = .standard) async throws {
        guard defaults.bool(forKey: installedKey) == false else { return }
        try await store.installDefaultsIfNeeded()
        defaults.set(true, forKey: installedKey)
    }
}
