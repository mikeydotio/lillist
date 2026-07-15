import XCTest

/// macOS real-input coverage of the custom swipe-reveal → Delete chain —
/// issue #18 evidence for `SwipeableRow`'s macOS `DragGesture` branch.
///
/// A *horizontal* click-drag reveals the trailing Delete action
/// (reveal-only: `allowsFullSwipe: false`, so no accidental full-swipe
/// delete); clicking the revealed button soft-deletes the task and the
/// deletion persists across a relaunch. A *vertical* drag must not reveal
/// Delete — the swipe axis arbiter yields vertical motion to reorder/scroll.
///
/// macOS UITests are not run in CI; this is the standing regression guard
/// for a manual run on a signed Mac.
@MainActor
final class MacSwipeUITests: XCTestCase {

    private static let seedCount = 5

    private static func titles() -> [String] {
        (1...seedCount).map { MacUITestHelpers.seedTitle($0) }
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Left drag reveals (does not commit) Delete; clicking it soft-deletes
    /// the row; the deletion survives a relaunch.
    func test_horizontalDragRevealsDelete_clickDeletes_andPersists() throws {
        let app = MacUITestHelpers.launchGestureSeeded(count: Self.seedCount)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30),
                      "Main window never appeared")
        let order = try waitForStableOrder(in: app, titles: Self.titles())
        let victim = order[0]
        let row = MacUITestHelpers.rowElement(in: app, containing: victim)

        // Left drag from the trailing side (dx 0.85, clear of the leading
        // status control) to reveal — not commit — the trailing Delete.
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        let end = start.withOffset(CGVector(dx: -160, dy: 0))
        MacUITestHelpers.dragMouse(from: start, to: end)

        // The Delete button is always in the tree (0-width + disabled when
        // closed), so gate on hittability, not existence.
        let deleteButton = app.buttons["Delete"].firstMatch
        wait(for: [expectation(
            for: NSPredicate(format: "isHittable == true"),
            evaluatedWith: deleteButton
        )], timeout: 4)
        XCTAssertTrue(
            row.exists,
            "Swipe deleted the row outright instead of just revealing Delete"
        )

        deleteButton.click()
        XCTAssertTrue(
            MacUITestHelpers.waitForDisappearance(of: row, timeout: 5),
            "Clicking Delete did not remove the row — the revealed action's " +
            "tap did not reach `TaskStore.softDelete`"
        )

        // Soft-delete persisted: still absent after relaunch of the on-disk store.
        app.terminate()
        let relaunched = MacUITestHelpers.launchExistingStore()
        let gone = MacUITestHelpers.rowElement(in: relaunched, containing: victim)
        XCTAssertFalse(
            gone.waitForExistence(timeout: 3),
            "Soft-deleted task reappeared after relaunch"
        )
    }

    /// A *vertical* drag on the row (reorder/scroll territory) must not
    /// reveal the Delete action.
    func test_verticalDragOnRow_doesNotRevealDelete() throws {
        let app = MacUITestHelpers.launchGestureSeeded(count: Self.seedCount)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30),
                      "Main window never appeared")
        let order = try waitForStableOrder(in: app, titles: Self.titles())
        let row = MacUITestHelpers.rowElement(in: app, containing: order[0])

        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: 140))
        MacUITestHelpers.dragMouse(from: start, to: end, holdDuration: 0.15)

        // Give any (erroneous) reveal time to animate in before asserting.
        Thread.sleep(forTimeInterval: 1.0)
        let deleteButton = app.buttons["Delete"].firstMatch
        XCTAssertFalse(
            deleteButton.isHittable,
            "A vertical drag revealed the Delete action — the swipe axis " +
            "arbiter is claiming vertical motion."
        )
    }
}
