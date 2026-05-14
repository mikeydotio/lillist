import XCTest
import LillistCore
@testable import Lillist_macOS

@MainActor
final class DefaultSmartFiltersInstallerTests: XCTestCase {
    func test_runsOnceThenSkips() async throws {
        let p = try await PersistenceController(configuration: .inMemory)
        let store = SmartFilterStore(persistence: p)
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!

        try await DefaultSmartFiltersInstaller.installIfNeeded(store: store, defaults: defaults)
        let firstCount = try await store.list().count
        XCTAssertGreaterThanOrEqual(firstCount, 5)

        try await DefaultSmartFiltersInstaller.installIfNeeded(store: store, defaults: defaults)
        let secondCount = try await store.list().count
        XCTAssertEqual(firstCount, secondCount, "Second invocation should not double-install")
    }
}
