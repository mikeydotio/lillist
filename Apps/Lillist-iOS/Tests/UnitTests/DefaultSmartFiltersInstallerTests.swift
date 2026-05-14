import XCTest
@testable import LillistCore

/// Exercises `SmartFilterStore.installDefaultsIfNeeded()` under the iOS test
/// runner. The iOS-side `DefaultSmartFiltersInstaller` wrapper itself is a
/// trivial UserDefaults gate around this LillistCore method; the meaningful
/// coverage is that the five filters land idempotently when invoked from an
/// iOS-style environment.
///
/// The standalone test bundle cannot `@testable import Lillist_iOS` (no test
/// host with the required entitlements), so we exercise the core installer
/// directly and trust the gate wrapper.
final class DefaultSmartFiltersInstallerTests: XCTestCase {
    func test_freshInstall_creates_five_defaults() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let store = SmartFilterStore(persistence: persistence)
        try await store.installDefaultsIfNeeded()
        let names = try await store.list().map(\.name).sorted()
        XCTAssertEqual(names, ["No Tags", "Recently Closed", "Stale", "This Week", "Today"])
    }

    func test_idempotent_on_second_install() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let store = SmartFilterStore(persistence: persistence)
        try await store.installDefaultsIfNeeded()
        try await store.installDefaultsIfNeeded()
        let count = try await store.list().count
        XCTAssertEqual(count, 5)
    }

    func test_does_not_overwrite_a_user_filter_with_the_same_name() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let store = SmartFilterStore(persistence: persistence)
        let existingID = try await store.create(
            name: "Today",
            group: PredicateGroup(combinator: .all, predicates: []),
            tintColor: nil,
            sortField: .title,
            sortAscending: true
        )
        try await store.installDefaultsIfNeeded()
        let reloaded = try await store.list().first { $0.id == existingID }
        XCTAssertEqual(reloaded?.sortField, .title)
    }
}
