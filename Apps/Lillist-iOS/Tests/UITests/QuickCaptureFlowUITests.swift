import XCTest

/// Diagnostic UI tests for the iOS new-task flow. Verifies that a task
/// created via Quick Capture is reachable via the in-place filter
/// search inside the same launch *and* after a relaunch. Designed in
/// service of an RCA — if either assertion fails the bug is in the
/// iOS-app persistence wiring (App Group / sandbox / CloudKit container
/// init), since the equivalent `LillistCore` round-trip is already
/// verified by `TaskStoreCRUDTests.createIsReadableAsRootChild`.
///
/// The UI surface this drives changed in the 3-tab restructure:
/// - Quick Capture is now reached via the bottom-trailing floating
///   action button (identifier `TasksQuickCaptureFAB`) on the single
///   primary surface, or via the empty-state capture button
///   (`TasksEmptyStateCaptureButton`) when the list is empty.
/// - Search lives inside the expanding filter header rather than a
///   dedicated sheet — tap `TasksFilterToggle` to expand, then type
///   into `FilterSearchField` to filter the same list view.
@MainActor
final class QuickCaptureFlowUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func test_quickCapture_via_floating_plus_persists_and_is_searchable() throws {
        let unique = "uitest-\(UUID().uuidString.prefix(8))"

        let app = launchFresh()
        openQuickCapture(in: app, via: .floatingPlus)
        typeAndSubmit(in: app, text: unique)
        assertFound(in: app, query: unique, contextMessage: "same launch")
        app.terminate()

        let relaunched = launchExisting()
        assertFound(in: relaunched, query: unique, contextMessage: "after relaunch")
    }

    func test_quickCapture_via_empty_state_persists_and_is_searchable() throws {
        let unique = "uitest-\(UUID().uuidString.prefix(8))"

        let app = launchFresh()
        openQuickCapture(in: app, via: .emptyState)
        typeAndSubmit(in: app, text: unique)
        assertFound(in: app, query: unique, contextMessage: "same launch")
        app.terminate()

        let relaunched = launchExisting()
        assertFound(in: relaunched, query: unique, contextMessage: "after relaunch")
    }

    // MARK: - Helpers

    /// Shared launch/onboarding plumbing lives in `UITestHelpers`.
    private func launchFresh() -> XCUIApplication {
        UITestHelpers.launchFresh()
    }

    private func launchExisting() -> XCUIApplication {
        UITestHelpers.launchExisting()
    }

    private enum CaptureEntryPoint {
        case floatingPlus
        case emptyState
    }

    private func openQuickCapture(in app: XCUIApplication, via entry: CaptureEntryPoint) {
        // Allow ample time for the initial cold launch: AppEnvironment.make()
        // loads the persistent store and the reset-state seam may also need
        // to wipe a previous directory.
        let timeout: TimeInterval = 20
        switch entry {
        case .floatingPlus:
            let plus = app.buttons["TasksQuickCaptureFAB"]
            if !plus.waitForExistence(timeout: timeout) {
                XCTFail("Floating + button missing. App tree:\n\(app.debugDescription)")
                return
            }
            plus.tap()
        case .emptyState:
            let emptyState = app.buttons["TasksEmptyStateCaptureButton"]
            if !emptyState.waitForExistence(timeout: timeout) {
                XCTFail("Tasks empty-state Capture button missing. App tree:\n\(app.debugDescription)")
                return
            }
            emptyState.tap()
        }
    }

    private func typeAndSubmit(in app: XCUIApplication, text: String) {
        let field = app.textFields["QuickCaptureField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "QuickCaptureField missing")
        field.tap()
        field.typeText(text)
        // The dialog has no Save button; Return submits.
        app.typeText("\n")
        // Wait for dialog to dismiss.
        XCTAssertTrue(
            waitForDisappearance(of: field, timeout: 5),
            "Quick Capture dialog did not dismiss after submit — submit may have failed"
        )
    }

    /// Find the captured task via the expanding filter header's search
    /// field. Search now filters the primary list in-place rather than
    /// presenting a sheet.
    private func assertFound(in app: XCUIApplication, query: String, contextMessage: String) {
        let filterToggle = app.buttons["TasksFilterToggle"]
        XCTAssertTrue(filterToggle.waitForExistence(timeout: 5),
                      "Filter toggle missing")
        filterToggle.tap()

        let field = app.textFields["FilterSearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5),
                      "FilterSearchField missing after expanding the filter header")
        if !field.hasFocus { field.tap() }
        field.typeText(query)

        // The list reload debounces 250ms; allow generous wait for the row to render.
        let row = app.cells.containing(NSPredicate(format: "label CONTAINS[c] %@", query)).firstMatch
        let found = row.waitForExistence(timeout: 8)
        XCTAssertTrue(
            found,
            "Created task '\(query)' was not found in the filtered list (\(contextMessage)). " +
            "This indicates the task did not persist via the iOS AppEnvironment path."
        )
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        UITestHelpers.waitForDisappearance(of: element, timeout: timeout)
    }
}

private extension XCUIElement {
    var hasFocus: Bool {
        (value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }
}
