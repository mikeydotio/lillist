import XCTest

/// Guards the bug where presenting a modal from a Settings *sub-page* dismisses
/// the entire Settings sheet ("nukes" it). Runs LocalOnly via the `--ui-test-*`
/// seams, so it needs no iCloud — the diagnostic-package include sheet is the
/// iCloud-independent reproduction of the same teardown that also hits the
/// iCloud-disable sheet (which requires an iCloud account to reach, so that one
/// is verified manually). The presentation teardown happens at sheet-*present*
/// time, before any work runs, so this deterministically reproduces in the sim.
final class SettingsSheetPresentationUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func test_prepareDiagnosticPackage_keepsSettingsPresented() {
        let app = UITestHelpers.launchFresh()

        let gear = app.buttons["TasksSettingsButton"]
        XCTAssertTrue(gear.waitForExistence(timeout: 10), "Settings gear missing")
        gear.tap()

        // Settings → Debug (the last drill-down row).
        let debugRow = app.cells
            .containing(NSPredicate(format: "label CONTAINS[c] %@", "Debug"))
            .firstMatch
        XCTAssertTrue(debugRow.waitForExistence(timeout: 5), "Debug settings row missing")
        debugRow.tap()

        // Trigger the include sheet.
        let exportButton = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Export Diagnostic Package"))
            .firstMatch
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5), "Export Diagnostic Package button missing")
        exportButton.tap()

        // Give the (buggy) flash-then-dismiss a beat to settle, then assert the
        // teardown did NOT happen. When the bug fires, the whole Settings sheet
        // tears down and the user is dumped back to the Tasks list — so the
        // Tasks FAB becomes hittable again. The include sheet ("Create") should
        // instead still be up.
        Thread.sleep(forTimeInterval: 2.5)
        XCTAssertFalse(
            app.buttons["TasksQuickCaptureFAB"].isHittable,
            "Settings sheet was dismissed — returned to the Tasks list (the nuke)"
        )
        XCTAssertTrue(
            app.buttons["Create"].exists,
            "Include sheet is not present after settling"
        )
    }
}
