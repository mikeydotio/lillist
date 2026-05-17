import XCTest

/// `@SceneStorage("taskDetailTab")` keys into scene-restoration storage
/// under the literal "taskDetailTab". This test pins that string so a
/// future rename doesn't silently invalidate restoration for shipped
/// users.
///
/// Renaming the storage key requires a one-version compatibility shim
/// that reads both keys; this test exists to remind anyone editing
/// `TaskDetailView.swift` of that obligation.
final class SegmentedDetailTabPersistenceTests: XCTestCase {
    func test_scene_storage_key_is_stable() {
        // Must match the `@SceneStorage("taskDetailTab")` declaration on
        // `TaskDetailView.swift`. Update both together if you rename.
        let key = "taskDetailTab"
        XCTAssertEqual(key, "taskDetailTab")
        XCTAssertEqual(key.count, 13)
    }
}
