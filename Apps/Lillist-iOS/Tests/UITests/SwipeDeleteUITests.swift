import XCTest

/// Regression guard for the dead swipe-reveal Delete button (fixed 2026-06-25):
/// a transparent tap-catcher overlay was applied *after* `SwipeableRow`'s
/// `.offset`, so it blanketed the row's full layout width — including the
/// trailing strip where the revealed Delete `Button` renders — and ate the tap.
/// Every unit, arbiter, and snapshot test stayed green because none exercised
/// the real swipe → reveal → tap → store chain; the bug only surfaced once
/// full-swipe-to-delete was disabled and tap became the only path. Same family
/// as `status-tap-primaryaction-dead` (StatusCycleUITests).
///
/// Drives the chain end-to-end on a localOnly store (no iCloud) via the
/// `--ui-test-*` launch seams.
@MainActor
final class SwipeDeleteUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Swiping a row reveals (does not auto-delete) Delete; tapping the revealed
    /// button soft-deletes the task; the deletion survives a relaunch.
    func test_swipeRevealDelete_tapDeletes_andPersists() throws {
        let (app, title) = UITestHelpers.launchWithOneTask()
        let cell = UITestHelpers.cell(in: app, containing: title)

        // A controlled left drag that settles into the held-open state. A
        // velocity flick (`swipeLeft()`) has a non-deterministic settle offset;
        // a short press-drag ends with low velocity at offset ≈ -actionWidth.
        // Keep `forDuration` well under the 0.3 s drag-reorder long-press so the
        // swipe — not reorder — claims the gesture, and start on the trailing
        // side (dx 0.9) clear of the leading status control.
        let start = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        let end = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)

        // The Delete button is always in the tree (0-width + disabled when
        // closed), so gate on `isHittable`, not existence — non-hittability is
        // the precise pre-fix signal (the overlay covered the strip).
        let deleteButton = app.buttons["Delete"].firstMatch
        wait(
            for: [expectation(
                for: NSPredicate(format: "isHittable == true"),
                evaluatedWith: deleteButton
            )],
            timeout: 4
        )
        XCTAssertTrue(
            cell.exists,
            "Swipe deleted the row outright instead of just revealing Delete"
        )

        // The exact negative guard: the bug's failure mode is "tap closes the
        // row, cell remains". Deletion is a soft-delete; `TasksView.onDelete`
        // reloads the unfiltered list (which excludes trashed rows), so the
        // cell must disappear in-session.
        deleteButton.tap()
        XCTAssertTrue(
            UITestHelpers.waitForDisappearance(of: cell, timeout: 5),
            "Tapping Delete closed the row instead of deleting it — the overlay " +
            "tap-catcher ate the button tap (regression)"
        )

        // Soft-delete persisted: the row is still absent after a relaunch of
        // the existing on-disk store.
        app.terminate()
        let relaunched = UITestHelpers.launchExisting()
        let gone = relaunched.cells
            .containing(NSPredicate(format: "label CONTAINS[c] %@", title))
            .firstMatch
        XCTAssertFalse(
            gone.waitForExistence(timeout: 3),
            "Soft-deleted task reappeared after relaunch"
        )
    }
}
