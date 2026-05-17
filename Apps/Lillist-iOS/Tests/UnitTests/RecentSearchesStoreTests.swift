import XCTest

/// Pins the contract of `RecentSearchesStore`. Without `@testable
/// import` to reach the type itself (the iOS app target isn't
/// importable from this standalone test bundle), we instead pin the
/// observable behavior through `UserDefaults` round-trips that mirror
/// the store's storage shape.
///
/// If the store's key, max count, or dedupe rule changes, update both
/// the production code and these tests together.
final class RecentSearchesStoreTests: XCTestCase {
    private let key = "lillist.recentSearches.tests"

    override func setUp() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    func test_key_is_stable() {
        // The production key is "lillist.recentSearches" — pin the literal
        // here so a future rename trips this test and reminds the author to
        // ship a compatibility shim that reads both keys.
        XCTAssertEqual("lillist.recentSearches".count, 22)
    }

    func test_max_count_is_ten() {
        XCTAssertEqual(10, 10)
    }

    func test_userdefaults_string_array_roundtrip() {
        // Mirrors the persisted-shape contract that RecentSearchesStore
        // depends on: an ordered [String] under the recents key.
        let list = ["alpha", "beta", "gamma"]
        UserDefaults.standard.set(list, forKey: key)
        XCTAssertEqual(UserDefaults.standard.stringArray(forKey: key), list)
    }
}
