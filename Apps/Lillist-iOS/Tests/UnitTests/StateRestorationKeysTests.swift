import XCTest
import SwiftUI

/// Plan: state-restoration. Pins the persisted-shape contract for the
/// iOS app's two new `@AppStorage` keys. The iOS app target isn't
/// importable from this standalone test bundle (see
/// `RecentSearchesStoreTests` for the same constraint), so we
/// exercise the observable storage shape via `UserDefaults` and
/// `NavigationPath` directly. If the production keys or encoding
/// shape change, update both the app and these tests together.
final class StateRestorationKeysTests: XCTestCase {
    private let sectionKey = "lillist.ios.section"
    private let pathKey = "lillist.ios.filters.path"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: sectionKey)
        UserDefaults.standard.removeObject(forKey: pathKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: sectionKey)
        UserDefaults.standard.removeObject(forKey: pathKey)
        super.tearDown()
    }

    // MARK: - Storage key stability

    func test_section_key_is_stable() {
        // Match `@AppStorage("lillist.ios.section")` in LillistApp.swift.
        XCTAssertEqual(sectionKey, "lillist.ios.section")
    }

    func test_filters_path_key_is_stable() {
        // Match `@AppStorage("lillist.ios.filters.path")` in LillistApp.swift.
        XCTAssertEqual(pathKey, "lillist.ios.filters.path")
    }

    // MARK: - Section raw-value round-trip

    func test_section_raw_values_roundtrip() {
        for raw in ["today", "all", "filters"] {
            UserDefaults.standard.set(raw, forKey: sectionKey)
            XCTAssertEqual(UserDefaults.standard.string(forKey: sectionKey), raw)
        }
    }

    func test_unknown_section_raw_value_can_be_read_back() {
        // The production code defaults to `.today` on unknown values
        // via `iPadSection(rawValue: ...) ?? .today`. The store itself
        // is opaque to that logic; just confirm it survives storage.
        UserDefaults.standard.set("future-tab-not-yet-shipped", forKey: sectionKey)
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: sectionKey),
            "future-tab-not-yet-shipped"
        )
    }

    // MARK: - NavigationPath codable round-trip (UUID values)

    func test_navigation_path_with_uuids_roundtrips() throws {
        // Filter rows in `FiltersListScreen` push bare `UUID` values
        // onto the path. Confirm a path of UUIDs can be encoded and
        // decoded back into an equivalent `NavigationPath`.
        var path = NavigationPath()
        let id1 = UUID()
        let id2 = UUID()
        path.append(id1)
        path.append(id2)

        let representation = try XCTUnwrap(path.codable, "UUID values must be Codable on the path")
        let data = try JSONEncoder().encode(representation)
        let decoded = try JSONDecoder().decode(
            NavigationPath.CodableRepresentation.self,
            from: data
        )
        let restored = NavigationPath(decoded)
        XCTAssertEqual(restored.count, 2)
    }

    func test_empty_path_codable_is_non_nil() throws {
        // `path.codable` returns nil only when an item isn't Codable.
        // The empty path should always be Codable.
        let path = NavigationPath()
        XCTAssertNotNil(path.codable)
    }

    func test_garbage_path_data_decodes_to_nil() {
        // Mirrors the production catch in `LillistApp.restoreFiltersPathIfNeeded`:
        // a corrupt blob should yield nil (not crash) so the user lands
        // on the Filters root rather than triggering an unhandled throw.
        let bytes = Data([0xFF, 0x00, 0x42, 0x7E])
        let decoded = try? JSONDecoder().decode(
            NavigationPath.CodableRepresentation.self,
            from: bytes
        )
        XCTAssertNil(decoded)
    }
}
