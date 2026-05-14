import Foundation
import LillistCore

/// Runs once on first launch (idempotent on subsequent launches) and asks
/// `SmartFilterStore` to install the five default filters from design
/// Section 7: Today, This Week, No Tags, Recently Closed, Stale.
///
/// The actual filter specs live in `LillistCore.DefaultSmartFilters`; this
/// wrapper is the iOS-side first-launch gate (mirroring the macOS app's
/// `Apps/Lillist-macOS/Sources/Defaults/DefaultSmartFiltersInstaller.swift`).
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
