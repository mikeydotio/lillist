import XCTest

/// Regression guard for the dead status-circle tap (RCA
/// `status-tap-primaryaction-dead`, fixed 2026-06-12): a row-level
/// long-press drag gesture laid over the status control ate its quick
/// taps while every unit, snapshot, and store test stayed green —
/// because nothing exercised the real tap → closure → store chain.
/// These tests drive that chain end-to-end on a localOnly store (no
/// iCloud needed) via the `--ui-test-*` launch seams.
///
/// Known simulator limitation (iOS 26.2): tapping the row *title* does
/// not push the detail view under XCUITest even with all gestures
/// removed, although it works on device — the row only shows its
/// selection highlight. There is therefore no positive
/// "title tap navigates" arm here; navigation remains a device-pass
/// check. The negative arm (status tap must NOT navigate) is asserted.
@MainActor
final class StatusCycleUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Tap advances todo → Started → Closed (one-way: Closed is terminal,
    /// a further tap is a no-op), never navigates, and the final status
    /// survives a relaunch (store write, not just glyph state).
    func test_statusTap_cycles_and_persists() throws {
        let (app, title) = UITestHelpers.launchWithOneTask()
        let cell = UITestHelpers.cell(in: app, containing: title)
        let status = statusControl(in: cell)

        status.tap()
        XCTAssertTrue(
            UITestHelpers.waitForLabel(of: cell, toContain: "Started", timeout: 4),
            "First tap should cycle todo → Started"
        )
        XCTAssertTrue(
            app.buttons["TasksSettingsButton"].exists,
            "Status tap must not push the detail view"
        )

        status.tap()
        XCTAssertTrue(
            UITestHelpers.waitForLabel(of: cell, toContain: "Closed", timeout: 4),
            "Second tap should cycle Started → Closed"
        )

        // Regression (#15): on a Closed row the control must stay a full 44pt
        // hittable target. The Closed glyph is an SF-Symbol checkmark; when the
        // cube isn't AX-hidden its ~10pt implicit element steals the
        // `StatusIndicator` identifier and the hit frame collapses to it, so the
        // no-op tap below can't even be delivered (and it fails Apple's 44pt
        // HIG floor). Assert before the third tap so a future re-collapse fails
        // legibly here, not as the opaque synthesized-tap abort.
        XCTAssertTrue(
            status.isHittable,
            "Closed StatusIndicator is not hittable — its AX/hit frame collapsed " +
            "to the inner checkmark glyph (#15)"
        )
        XCTAssertGreaterThan(
            status.frame.height, 40,
            "Closed StatusIndicator height \(status.frame.height) collapsed below the 44pt target (#15)"
        )
        XCTAssertGreaterThan(
            status.frame.width, 40,
            "Closed StatusIndicator width \(status.frame.width) collapsed below the 44pt target (#15)"
        )

        // Closed is terminal under the one-way cycle — a further tap must
        // NOT loop back to "To do" (resetting is the swipe's job now).
        status.tap()
        XCTAssertFalse(
            UITestHelpers.waitForLabel(of: cell, toContain: "To do", timeout: 2),
            "Third tap on a Closed task looped back to todo — the status " +
            "cycle is no longer one-way"
        )

        app.terminate()
        let relaunched = UITestHelpers.launchExisting()
        let persisted = UITestHelpers.cell(in: relaunched, containing: title)
        XCTAssertTrue(
            UITestHelpers.waitForLabel(of: persisted, toContain: "Closed", timeout: 4),
            "Cycled status did not persist across relaunch — the tap " +
            "reached the glyph but not the store"
        )
    }

    /// Long-press opens the explicit status menu; selecting Blocked
    /// applies it. Pins the second half of the status control's
    /// contract (`Menu(primaryAction:)` long-press path).
    func test_statusLongPress_menu_sets_blocked() throws {
        let (app, title) = UITestHelpers.launchWithOneTask()
        let cell = UITestHelpers.cell(in: app, containing: title)

        statusControl(in: cell).press(forDuration: 0.8)

        let blocked = app.buttons["Blocked"]
        XCTAssertTrue(
            blocked.waitForExistence(timeout: 4),
            "Status menu did not open on long-press"
        )
        blocked.tap()
        XCTAssertTrue(
            UITestHelpers.waitForLabel(of: cell, toContain: "Blocked", timeout: 4),
            "Menu selection did not update the row to Blocked"
        )
    }

    /// The status control as a distinct, hittable element — itself part
    /// of the regression contract: when the control was swallowed into
    /// a row-wide wrapper it stopped being independently addressable.
    private func statusControl(in cell: XCUIElement) -> XCUIElement {
        let control = cell.descendants(matching: .any)
            .matching(identifier: "StatusIndicator")
            .firstMatch
        XCTAssertTrue(
            control.waitForExistence(timeout: 4),
            "StatusIndicator element missing from the row — is the " +
            "control wrapped inside the NavigationLink/gesture again?"
        )
        return control
    }
}
