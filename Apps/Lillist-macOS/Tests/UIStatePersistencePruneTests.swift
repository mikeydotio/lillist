import XCTest
import LillistCore

/// Plan: state-restoration audit. Exercises `UIStatePersistence`'s
/// stale-UUID pruning + decode resilience against deliberately
/// corrupt data, both of which guard the macOS app from crashing
/// after a CloudKit sync deletes the user's selected filter/tag
/// between launches.
@MainActor
final class UIStatePersistencePruneTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "UIStatePersistencePruneTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    // MARK: - Round-trip

    func test_sidebar_selection_roundtrip_all_cases() throws {
        let store = UIStatePersistence(defaults: defaults)
        let filterID = UUID()
        let tagID = UUID()
        let taskID = UUID()

        for sel in [SidebarSelection.pinnedTask(taskID),
                    .pinnedFilter(filterID),
                    .tag(tagID),
                    .filter(filterID),
                    .trash] {
            store.sidebarSelection = sel
            // Round-trip through a freshly-constructed instance so we
            // exercise the on-disk encoded form, not the in-memory
            // value we just wrote.
            let echo = UIStatePersistence(defaults: defaults).sidebarSelection
            XCTAssertEqual(echo, sel)
        }
    }

    // MARK: - Decode resilience

    func test_garbage_data_decodes_to_nil() {
        // Inject arbitrary bytes under the production key. The store
        // must swallow the decode error and return `nil` instead of
        // crashing the next launch.
        defaults.set(Data([0xFF, 0x00, 0x42]), forKey: "lillist.ui.sidebarSelection")
        let store = UIStatePersistence(defaults: defaults)
        XCTAssertNil(store.sidebarSelection)
    }

    // MARK: - Stale pruning

    func test_prune_clears_missing_filter_selection() {
        let store = UIStatePersistence(defaults: defaults)
        store.sidebarSelection = .pinnedFilter(UUID())

        store.pruneStaleSidebarSelection(
            filterExists: { _ in false },
            tagExists: { _ in false },
            taskExists: { _ in false }
        )

        XCTAssertNil(store.sidebarSelection)
    }

    func test_prune_keeps_existing_filter_selection() {
        let store = UIStatePersistence(defaults: defaults)
        let liveID = UUID()
        store.sidebarSelection = .pinnedFilter(liveID)

        store.pruneStaleSidebarSelection(
            filterExists: { $0 == liveID },
            tagExists: { _ in false },
            taskExists: { _ in false }
        )

        XCTAssertEqual(store.sidebarSelection, .pinnedFilter(liveID))
    }

    func test_prune_keeps_trash_unconditionally() {
        let store = UIStatePersistence(defaults: defaults)
        store.sidebarSelection = .trash

        store.pruneStaleSidebarSelection(
            filterExists: { _ in false },
            tagExists: { _ in false },
            taskExists: { _ in false }
        )

        XCTAssertEqual(store.sidebarSelection, .trash)
    }

    func test_prune_clears_missing_tag_and_task_selections() {
        let store = UIStatePersistence(defaults: defaults)

        store.sidebarSelection = .tag(UUID())
        store.pruneStaleSidebarSelection(
            filterExists: { _ in true },
            tagExists: { _ in false },
            taskExists: { _ in true }
        )
        XCTAssertNil(store.sidebarSelection, "stale tag should be cleared")

        store.sidebarSelection = .pinnedTask(UUID())
        store.pruneStaleSidebarSelection(
            filterExists: { _ in true },
            tagExists: { _ in true },
            taskExists: { _ in false }
        )
        XCTAssertNil(store.sidebarSelection, "stale pinned task should be cleared")
    }

    func test_prune_is_noop_when_nothing_selected() {
        let store = UIStatePersistence(defaults: defaults)
        XCTAssertNil(store.sidebarSelection)

        store.pruneStaleSidebarSelection(
            filterExists: { _ in false },
            tagExists: { _ in false },
            taskExists: { _ in false }
        )

        XCTAssertNil(store.sidebarSelection)
    }
}
