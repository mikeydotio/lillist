import XCTest

/// Shared launch / capture / wait plumbing for the iOS UI tests.
///
/// All launches ride the `--ui-test-reset-store` / `--ui-test-bypass-gates`
/// seams (see `LillistApp`), which force a localOnly store so the suite
/// runs without an iCloud account.
enum UITestHelpers {

    /// Launch with the reset-state seam so the test sees a known-clean
    /// store + onboarding/crash gates bypassed.
    @MainActor
    static func launchFresh() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-reset-store", "--ui-test-bypass-gates"]
        app.launch()
        dismissOnboardingIfPresent(in: app)
        return app
    }

    /// Launch the existing install — no reset, so previously created
    /// tasks are still on disk. Gates still bypassed.
    @MainActor
    static func launchExisting() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-bypass-gates"]
        app.launch()
        dismissOnboardingIfPresent(in: app)
        return app
    }

    /// Defense-in-depth: the reset seam *should* bypass onboarding, but
    /// the onboarding cover can present asynchronously a few seconds
    /// after launch. Poll for either the settings button
    /// (post-onboarding) or the Skip button (onboarding active).
    @MainActor
    static func dismissOnboardingIfPresent(in app: XCUIApplication) {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if app.buttons["TasksSettingsButton"].exists { return }
            let skip = app.buttons["Skip for now"]
            if skip.exists {
                skip.tap()
                return
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
    }

    /// Create one task via Quick Capture (FAB, or the empty-state button
    /// on a fresh store) and return its unique title.
    ///
    /// The plain task list does not reload after an in-session capture,
    /// so callers that need the row visible in the *unfiltered* list
    /// must relaunch (`launchExisting`) or filter-search afterwards.
    @MainActor
    static func createTask(in app: XCUIApplication, prefix: String = "uitest") -> String {
        let title = "\(prefix)-\(UUID().uuidString.prefix(8))"
        let fab = app.buttons["TasksQuickCaptureFAB"]
        let emptyState = app.buttons["TasksEmptyStateCaptureButton"]
        let deadline = Date().addingTimeInterval(20)
        var opened = false
        while Date() < deadline {
            if emptyState.exists { emptyState.tap(); opened = true; break }
            if fab.exists { fab.tap(); opened = true; break }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertTrue(opened, "No Quick Capture entry point appeared")

        let field = app.textFields["QuickCaptureField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "QuickCaptureField missing")
        field.tap()
        field.typeText(title)
        // The dialog has no Save button; Return submits.
        app.typeText("\n")
        XCTAssertTrue(
            waitForDisappearance(of: field, timeout: 5),
            "Quick Capture dialog did not dismiss after submit"
        )
        return title
    }

    /// Fresh-launch + capture one task + relaunch, returning the running
    /// app and the task's title — the standard setup for tests that
    /// drive a row in the unfiltered list.
    @MainActor
    static func launchWithOneTask() -> (XCUIApplication, String) {
        let first = launchFresh()
        let title = createTask(in: first)
        first.terminate()
        return (launchExisting(), title)
    }

    /// The list cell whose subtree carries `text` in a label.
    @MainActor
    static func cell(in app: XCUIApplication, containing text: String) -> XCUIElement {
        let cell = app.cells
            .containing(NSPredicate(format: "label CONTAINS[c] %@", text))
            .firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 8), "Row for '\(text)' not found")
        return cell
    }

    /// True once any descendant of `element` (or the element itself)
    /// carries a label containing `text`. Row labels live on descendants
    /// of the cell, not reliably on the Cell element itself.
    @MainActor
    static func waitForLabel(
        of element: XCUIElement,
        toContain text: String,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", text)
        let match = element.descendants(matching: .any).matching(predicate).firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if match.exists { return true }
            if element.exists,
               (element.label as NSString).range(of: text, options: .caseInsensitive).location != NSNotFound {
                return true
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    @MainActor
    static func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return !element.exists
    }
}
