import XCTest
import LillistCore

@MainActor
final class ToolbarPersistenceTests: XCTestCase {
    private let suiteName = "ToolbarPersistenceTests"

    override func tearDownWithError() throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    func test_taskSelection_persistsPerSidebarSource() throws {
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = UIStatePersistence(defaults: defaults)

        let filterA = SidebarSelection.filter(UUID())
        let filterB = SidebarSelection.filter(UUID())
        let taskA = UUID()
        let taskB = UUID()

        store.setTaskSelection(taskA, for: filterA)
        store.setTaskSelection(taskB, for: filterB)

        XCTAssertEqual(store.taskSelection(for: filterA), taskA)
        XCTAssertEqual(store.taskSelection(for: filterB), taskB)
    }

    func test_taskSelection_nilClears() throws {
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = UIStatePersistence(defaults: defaults)

        let filter = SidebarSelection.filter(UUID())
        let task = UUID()
        store.setTaskSelection(task, for: filter)
        XCTAssertEqual(store.taskSelection(for: filter), task)
        store.setTaskSelection(nil, for: filter)
        XCTAssertNil(store.taskSelection(for: filter))
    }
}
