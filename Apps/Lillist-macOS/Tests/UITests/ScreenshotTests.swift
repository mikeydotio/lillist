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
///
/// NOTE: the main-window tour below targets the shared iOS single-column
/// UI (the macOS split view / sidebar was retired). macOS UITests are not
/// run in CI — they need a signed Mac with an iCloud account and must be
/// verified by Mikey on-device.
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

        // The single-column task list, populated from the seeded demo
        // content. No source selection — the sidebar was retired when the
        // window adopted the shared iOS UI; navigation is via the filter
        // header below.
        captureScreenshot(app, named: "01-tasks-list-\(suffix)")

        // Expand the filter header (search well + quick-filter chips), then
        // show the "Done" view, which surfaces the seeded closed task.
        let filterToggle = app.buttons["TasksFilterToggle"]
        if filterToggle.waitForExistence(timeout: 5) {
            filterToggle.click()
            Thread.sleep(forTimeInterval: 0.5)
            captureScreenshot(app, named: "02-filter-header-\(suffix)")
            let done = app.buttons["Done"]
            if done.waitForExistence(timeout: 3), done.isHittable {
                done.click()
                Thread.sleep(forTimeInterval: 0.6)
                captureScreenshot(app, named: "03-filter-done-\(suffix)")
                done.click()              // clear the chip
            }
            filterToggle.click()           // collapse the header
        }

        // Open the unified task editor on an existing row. The editor is now
        // an in-window overlay (the docked detail column / floating NSPanel
        // for in-app edits was replaced), so a window screenshot captures it.
        // The row opens on a tap of its title text.
        let row = app.staticTexts["Draft Q3 roadmap"]
        if row.waitForExistence(timeout: 8), row.isHittable {
            row.click()
            Thread.sleep(forTimeInterval: 1.0)
            captureScreenshot(app, named: "04-task-editor-\(suffix)")
            app.typeKey(.escape, modifierFlags: [])
            Thread.sleep(forTimeInterval: 0.4)
        }

        // Open quick capture via the bottom-trailing FAB (the same in-window
        // overlay, in new-capture mode).
        let fab = app.buttons["TasksQuickCaptureFAB"]
        if fab.waitForExistence(timeout: 5), fab.isHittable {
            fab.click()
            Thread.sleep(forTimeInterval: 1.0)
            captureScreenshot(app, named: "05-quick-capture-\(suffix)")
            app.typeKey(.escape, modifierFlags: [])
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
