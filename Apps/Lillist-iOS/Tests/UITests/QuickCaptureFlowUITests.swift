import XCTest

/// Diagnostic UI tests for the iOS new-task flow. Verifies that a task
/// created via Quick Capture is reachable via Search inside the same
/// launch *and* after a relaunch. Designed in service of an RCA — if
/// either assertion fails the bug is in the iOS-app persistence wiring
/// (App Group / sandbox / CloudKit container init), since the equivalent
/// `LillistCore` round-trip is already verified by
/// `TaskStoreCRUDTests.createIsReadableAsRootChild`.
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

    func test_quickCapture_via_today_empty_state_persists_and_is_searchable() throws {
        let unique = "uitest-\(UUID().uuidString.prefix(8))"

        let app = launchFresh()
        openQuickCapture(in: app, via: .todayEmptyState)
        typeAndSubmit(in: app, text: unique)
        assertFound(in: app, query: unique, contextMessage: "same launch")
        app.terminate()

        let relaunched = launchExisting()
        assertFound(in: relaunched, query: unique, contextMessage: "after relaunch")
    }

    // MARK: - Helpers

    /// Launch with the reset-state seam so the test sees a known-clean
    /// store + onboarding/crash gates bypassed.
    private func launchFresh() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-reset-store", "--ui-test-bypass-gates"]
        app.launch()
        dismissOnboardingIfPresent(in: app)
        return app
    }

    /// Launch the existing install — no reset, so a previously created
    /// task should still be on disk. Onboarding/crash gates still
    /// bypassed (the persistent-store contents are independent of the
    /// onboarding-completion flag's persistence).
    private func launchExisting() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-bypass-gates"]
        app.launch()
        dismissOnboardingIfPresent(in: app)
        return app
    }

    /// Defense-in-depth: the `--ui-test-reset-store` seam *should* bypass
    /// onboarding via `setHasCompletedOnboarding(true)`, but the
    /// onboarding fullScreenCover can present asynchronously up to a few
    /// seconds after launch (env init → modifier .task → evaluate →
    /// showOnboarding = true). Race-proof by polling for either the
    /// tab bar (post-onboarding) or the Skip button (onboarding active)
    /// up to a generous deadline before proceeding.
    private func dismissOnboardingIfPresent(in app: XCUIApplication) {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if app.tabBars.firstMatch.exists {
                return
            }
            let skip = app.buttons["Skip for now"]
            if skip.exists {
                skip.tap()
                return
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
    }

    private enum CaptureEntryPoint {
        case floatingPlus
        case todayEmptyState
    }

    private func openQuickCapture(in app: XCUIApplication, via entry: CaptureEntryPoint) {
        // Allow ample time for the initial cold launch: AppEnvironment.make()
        // loads the persistent store and the reset-state seam may also need
        // to wipe a previous directory.
        let timeout: TimeInterval = 20
        switch entry {
        case .floatingPlus:
            let plus = app.buttons["QuickCaptureAccessory"]
            if !plus.waitForExistence(timeout: timeout) {
                XCTFail("Floating + button missing. App tree:\n\(app.debugDescription)")
                return
            }
            plus.tap()
        case .todayEmptyState:
            let emptyState = app.buttons["TodayEmptyStateCaptureButton"]
            if !emptyState.waitForExistence(timeout: timeout) {
                XCTFail("Today empty-state Capture button missing. App tree:\n\(app.debugDescription)")
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

    private func assertFound(in app: XCUIApplication, query: String, contextMessage: String) {
        // Post-RCA-restructure: Search lives in a top-leading toolbar
        // sheet on every primary section, not as its own tab.
        let searchButton = app.buttons["SearchToolbarButton"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5),
                      "Search toolbar button missing")
        searchButton.tap()

        // `.searchable` on iOS 26 is rendered in a way that XCUI does not
        // expose as either `.searchField` or `.textField` to the test
        // process — see screen recording in `~/Enderchest/Lillist/...`.
        // The field is auto-focused on Search-tab landing (keyboard up,
        // cursor in field), so route the query through the keyboard via
        // `app.typeText` directly. If a future iOS update exposes it
        // again, prefer the typed-field path.
        if let field = firstSearchableField(in: app), field.waitForExistence(timeout: 2) {
            if !field.hasFocus { field.tap() }
            field.typeText(query)
        } else {
            // Give the search-tab transition a beat to settle and focus
            // to land in the field.
            Thread.sleep(forTimeInterval: 0.5)
            app.typeText(query)
        }

        // SearchView debounces 250ms; allow generous wait for the row to render.
        let row = app.cells.containing(NSPredicate(format: "label CONTAINS[c] %@", query)).firstMatch
        let found = row.waitForExistence(timeout: 8)
        XCTAssertTrue(
            found,
            "Created task '\(query)' was not found in Search (\(contextMessage)). " +
            "This indicates the task did not persist via the iOS AppEnvironment path."
        )
    }

    /// Returns whichever search-style input exists on screen. SwiftUI
    /// `.searchable` may register as either `.searchField` or `.textField`
    /// depending on placement and OS version; returns `nil` if neither.
    private func firstSearchableField(in app: XCUIApplication) -> XCUIElement? {
        let asSearch = app.searchFields.firstMatch
        if asSearch.exists { return asSearch }
        let asText = app.textFields.firstMatch
        if asText.exists { return asText }
        return nil
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let exp = expectation(for: predicate, evaluatedWith: element, handler: nil)
        return XCTWaiter().wait(for: [exp], timeout: timeout) == .completed
    }
}

private extension XCUIElement {
    var hasFocus: Bool {
        (value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }
}
