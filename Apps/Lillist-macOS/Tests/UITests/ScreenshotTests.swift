import XCTest

/// Drives the real `Lillist-macOS` app through its primary surfaces and
/// attaches a screenshot of each, in both light and dark appearance. These
/// are captures for a human visual design pass — they assert only that a
/// window appears, then record the pixels. `xcrun xcresulttool export
/// attachments` pulls the PNGs out of the result bundle.
///
/// This is the only way to verify macOS Liquid Glass: offscreen
/// NSHostingView→image capture blanks glass (see CLAUDE.md), so the macOS
/// glass snapshot suites are XCTSkip-quarantined. A live XCUITest screenshot
/// goes through the automation framework's window-server capture, which
/// renders glass.
final class ScreenshotTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Keep capturing the remaining surfaces even if one navigation step
        // can't find its target — a miss still yields a useful screenshot.
        continueAfterFailure = true
    }

    // MARK: - Main window

    @MainActor func testMainWindowLight() { captureMainWindow(.light) }
    @MainActor func testMainWindowDark()  { captureMainWindow(.dark) }

    @MainActor
    private func captureMainWindow(_ appearance: MacUITestHelpers.Appearance) {
        let app = MacUITestHelpers.launchSeeded(appearance)
        let suffix = appearance.rawValue
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30),
                      "Main window never appeared")

        // No source selected yet → the "Select a source" content empty state.
        captureScreenshot(app, named: "01-select-source-\(suffix)")

        // A tag source — hierarchical list mode, populated ("Work").
        clickSidebarRow(app, "Work")
        captureScreenshot(app, named: "02-tag-work-\(suffix)")

        // A smart-filter source — flat list mode, populated. "No Tags"
        // matches the untagged seeded tasks (no dates, so Today/This Week
        // would be empty).
        clickSidebarRow(app, "No Tags")
        captureScreenshot(app, named: "03-filter-no-tags-\(suffix)")

        // Another filter — "Recently Closed" shows the closed seeded task.
        clickSidebarRow(app, "Recently Closed")
        captureScreenshot(app, named: "04-filter-recently-closed-\(suffix)")

        // Trash (empty) — the flat-list empty state.
        clickSidebarRow(app, "Trash")
        captureScreenshot(app, named: "05-trash-empty-\(suffix)")

        // Inline create (⌘N) on a populated tag source.
        clickSidebarRow(app, "Work")
        app.typeKey("n", modifierFlags: .command)
        let field = app.textFields["InlineCreateField"]
        if field.waitForExistence(timeout: 5) {
            field.click()
            field.typeText("Plan offsite agenda")
        }
        captureScreenshot(app, named: "06-inline-create-\(suffix)")

        // Open the unified task editor on an existing row (floating panel).
        // Double-click opens the editor (single click only selects).
        app.typeKey(.escape, modifierFlags: [])
        clickSidebarRow(app, "Work")
        let row = app.staticTexts["Draft Q3 roadmap"]
        if row.waitForExistence(timeout: 8) {
            row.doubleClick()
            Thread.sleep(forTimeInterval: 1.5)
            // The editor is a separate floating NSPanel not surfaced in
            // `app.windows`; full-screen is the only reliable capture.
            captureFullScreen(named: "07-task-editor-\(suffix)")
        }

        app.terminate()
    }

    // MARK: - Preferences (all 8 panes)

    @MainActor func testPreferencesLight() { capturePreferences(.light) }
    @MainActor func testPreferencesDark()  { capturePreferences(.dark) }

    @MainActor
    private func capturePreferences(_ appearance: MacUITestHelpers.Appearance) {
        let app = MacUITestHelpers.launchSeeded(appearance)
        let suffix = appearance.rawValue
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30),
                      "Main window never appeared")

        // Open Settings (⌘,). The Settings window is separate from the main
        // window; capture full-screen so it's always included regardless of
        // window ordering.
        app.typeKey(",", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 1.0)

        let tabs = [
            ("iCloud Sync", "01-icloud"),
            ("General", "02-general"),
            ("Notifications", "03-notifications"),
            ("Trash", "04-trash"),
            ("Quick Capture", "05-quick-capture"),
            ("Crash Reporting", "06-crash-reporting"),
            ("Diagnostics", "07-diagnostics"),
            ("Advanced", "08-advanced"),
        ]
        for (label, slug) in tabs {
            clickPreferencesTab(app, label)
            Thread.sleep(forTimeInterval: 0.6)
            // The Settings window's title is the selected pane's name.
            captureScreenshot(app, named: "prefs-\(slug)-\(suffix)", windowTitle: label)
        }

        app.terminate()
    }

    // MARK: - Onboarding sheet

    @MainActor func testOnboardingLight() { captureOnboarding(.light) }
    @MainActor func testOnboardingDark()  { captureOnboarding(.dark) }

    @MainActor
    private func captureOnboarding(_ appearance: MacUITestHelpers.Appearance) {
        let app = MacUITestHelpers.launchSeeded(appearance, extra: ["--ui-test-force-onboarding"])
        let suffix = appearance.rawValue
        // The onboarding sheet presents over the main window; wait for its
        // hero title.
        let welcome = app.staticTexts["Welcome to Lillist"]
        XCTAssertTrue(welcome.waitForExistence(timeout: 30), "Onboarding sheet never appeared")
        Thread.sleep(forTimeInterval: 0.6)
        captureScreenshot(app, named: "08-onboarding-\(suffix)")
        app.terminate()
    }

    // MARK: - Quick-capture panel

    @MainActor func testQuickCaptureLight() { captureQuickCapture(.light) }
    @MainActor func testQuickCaptureDark()  { captureQuickCapture(.dark) }

    @MainActor
    private func captureQuickCapture(_ appearance: MacUITestHelpers.Appearance) {
        let app = MacUITestHelpers.launchSeeded(appearance, extra: ["--ui-test-show-quick-capture"])
        let suffix = appearance.rawValue
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30),
                      "Main window never appeared")
        // The panel is a floating nonactivating NSPanel not surfaced in
        // `app.windows`; full-screen is the only reliable capture.
        Thread.sleep(forTimeInterval: 1.5)
        captureFullScreen(named: "09-quick-capture-\(suffix)")
        app.terminate()
    }
}
