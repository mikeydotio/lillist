import XCTest

/// Shared launch / capture plumbing for the macOS screenshot UI tests.
///
/// Every launch rides the `--ui-test-*` seams in `LillistApp`: a reset to a
/// known-clean LocalOnly store (no iCloud account needed), gates bypassed,
/// and deterministic demo content seeded. A pinned appearance keeps light /
/// dark captures independent of the host Mac's system setting.
enum MacUITestHelpers {

    enum Appearance: String {
        case light, dark
        var launchArgument: String {
            switch self {
            case .light: return "--ui-test-appearance-light"
            case .dark:  return "--ui-test-appearance-dark"
            }
        }
    }

    /// Launch the real `Lillist-macOS` app: clean store, bypassed gates,
    /// seeded demo data, pinned appearance, plus any extra seam arguments.
    @MainActor
    static func launchSeeded(_ appearance: Appearance, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "--ui-test-reset-store",
            "--ui-test-bypass-gates",
            "--ui-test-seed-demo",
            appearance.launchArgument,
        ] + extra
        app.launch()
        return app
    }
}

extension XCTestCase {

    /// Screenshot a specific app window and attach it with a stable name,
    /// kept even when the test passes. Always captures a *window* (never the
    /// whole screen) so a frontmost Xcode — when the suite is run from the
    /// IDE — can't bleed into the shot. `xcrun xcresulttool export
    /// attachments` pulls these out of the result bundle as PNGs + a
    /// name→file manifest.
    ///
    /// - Parameter windowTitle: when set, captures `app.windows[title]`
    ///   (e.g. the Settings window, whose title is the selected pane name);
    ///   otherwise the main window via `firstMatch`.
    @MainActor
    func captureScreenshot(
        _ app: XCUIApplication,
        named name: String,
        windowTitle: String? = nil
    ) {
        let window: XCUIElement
        if let windowTitle, app.windows[windowTitle].exists {
            window = app.windows[windowTitle]
        } else {
            window = app.windows.firstMatch
        }
        let shot = window.exists ? window.screenshot() : XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Screenshot the whole main display. The only reliable way to capture
    /// the floating, nonactivating quick-capture `NSPanel` and the task-editor
    /// panel — XCUITest does not surface nonactivating panels in `app.windows`.
    /// Run headless (over SSH) the panel sits frontmost on the desktop.
    @MainActor
    func captureFullScreen(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Screenshot every open app window, suffixing each with its index. Used
    /// for surfaces hosted in a secondary window whose title is unknown — the
    /// floating quick-capture `NSPanel` (titleVisibility hidden) and the task
    /// editor panel. One of the resulting shots is the target; the others are
    /// the main window behind it.
    @MainActor
    func captureAllWindows(_ app: XCUIApplication, prefix: String) {
        let windows = app.windows.allElementsBoundByIndex
        for (index, window) in windows.enumerated() where window.exists {
            let attachment = XCTAttachment(screenshot: window.screenshot())
            attachment.name = "\(prefix)-win\(index)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    /// Click a macOS sidebar row by its visible title. Sidebar rows expose
    /// their label as a static text inside the outline; try the common
    /// element kinds and click the first that resolves. Best-effort — a
    /// miss leaves the current source shown (still a valid capture).
    @MainActor
    @discardableResult
    func clickSidebarRow(_ app: XCUIApplication, _ title: String, timeout: TimeInterval = 4) -> Bool {
        let candidates: [XCUIElement] = [
            app.outlines.staticTexts[title],
            app.tables.staticTexts[title],
            app.cells.staticTexts[title],
            app.staticTexts[title],
            app.buttons[title],
        ]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for element in candidates where element.exists && element.isHittable {
                element.click()
                return true
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }

    /// Click a Preferences tab by its label. The Settings window is a
    /// self-sizing TabView whose toolbar collapses extra tabs behind a ">>"
    /// overflow chevron once 8 panes no longer fit — so a direct hit is tried
    /// first, then the toolbar overflow menu. Best-effort.
    @MainActor
    @discardableResult
    func clickPreferencesTab(_ app: XCUIApplication, _ label: String, timeout: TimeInterval = 4) -> Bool {
        // 1) Direct: the tab is visible in the toolbar.
        let direct = app.buttons[label]
        if direct.waitForExistence(timeout: 1.5), direct.isHittable {
            direct.click()
            return true
        }
        // 2) Overflow: click the toolbar ">>" chevron, then the menu item.
        let overflowCandidates: [XCUIElement] = [
            app.buttons["NSToolbarMoreItem"],
            app.toolbars.firstMatch.buttons.allElementsBoundByIndex.last ?? app.buttons.firstMatch,
        ]
        for chevron in overflowCandidates where chevron.exists && chevron.isHittable {
            chevron.click()
            let item = app.menuItems[label]
            if item.waitForExistence(timeout: 2), item.isHittable {
                item.click()
                return true
            }
        }
        return false
    }
}
