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

    // MARK: - Gesture-harness launches

    /// Deterministic seed title for `launchGestureSeeded` — matches the
    /// `--ui-test-seed-many` seam's `"Gesture seed %02d"` format in
    /// `LillistApp`.
    static func seedTitle(_ index: Int) -> String {
        String(format: "Gesture seed %02d", index)
    }

    /// Launch the real app for a gesture *behavioral* test: clean LocalOnly
    /// store, gates bypassed, and `count` plainly-titled root tasks seeded
    /// (the `--ui-test-seed-many` seam). Light appearance so the run is
    /// independent of the host Mac's system setting.
    @MainActor
    static func launchGestureSeeded(count: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "--ui-test-reset-store",
            "--ui-test-bypass-gates",
            "--ui-test-seed-many",
            "--ui-test-seed-count", String(count),
            Appearance.light.launchArgument,
        ]
        app.launch()
        return app
    }

    /// Relaunch the existing on-disk store (no reset, no reseed) so a suite
    /// can assert a mutation — reorder, delete — persisted. Gates stay
    /// bypassed; appearance pinned light.
    @MainActor
    static func launchExistingStore() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "--ui-test-bypass-gates",
            Appearance.light.launchArgument,
        ]
        app.launch()
        return app
    }

    // MARK: - Row location & order

    /// The first element (any type) whose accessibility label contains
    /// `text`. The row-title surface on macOS is a *combined* accessibility
    /// element (`children: .combine` + `.isButton` in `TasksScreen`) whose
    /// XCUITest classification (button vs. static text) is not stable, so
    /// rows are matched element-type-agnostically.
    @MainActor
    static func rowElement(in app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", text))
            .firstMatch
    }

    /// One sample of the listed titles' visual top-to-bottom order (sorted by
    /// each row's `frame.minY`), or `nil` while any listed row is missing or
    /// zero-height (mid-load / mid-animation).
    @MainActor
    static func visualOrder(in app: XCUIApplication, titles: [String]) -> [String]? {
        var pairs: [(title: String, minY: CGFloat)] = []
        for title in titles {
            let element = rowElement(in: app, containing: title)
            guard element.exists else { return nil }
            let frame = element.frame
            guard frame.height > 0 else { return nil }
            pairs.append((title, frame.minY))
        }
        return pairs.sorted { $0.minY < $1.minY }.map(\.title)
    }

    // MARK: - Synthesized input (macOS)

    /// A press-and-drag from `start` to `end` using the macOS click-drag
    /// primitive — the desktop analogue of the iOS `XCUICoordinate
    /// .press(forDuration:thenDragTo:)`. `holdDuration` is the mouse-down
    /// dwell before motion begins.
    @MainActor
    static func dragMouse(
        from start: XCUICoordinate,
        to end: XCUICoordinate,
        holdDuration: TimeInterval = 0.1
    ) {
        start.click(forDuration: holdDuration, thenDragTo: end)
    }

    /// True once `element` has left the accessibility hierarchy (polling).
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

extension XCTestCase {

    /// The listed titles' visual order once stable — two samples 0.3 s apart
    /// agree. Throws if it never stabilizes. A stabilizing condition for
    /// baselines and post-gesture settle reads, never an assertion. Mirrors
    /// the iOS `LongPressReorderUITests` order plumbing.
    @MainActor
    func waitForStableOrder(
        in app: XCUIApplication,
        titles: [String],
        timeout: TimeInterval = 12
    ) throws -> [String] {
        let deadline = Date().addingTimeInterval(timeout)
        var previous: [String]?
        while Date() < deadline {
            let current = MacUITestHelpers.visualOrder(in: app, titles: titles)
            if let current, let previous, current == previous { return current }
            previous = current
            Thread.sleep(forTimeInterval: 0.3)
        }
        struct OrderNotReadable: Error, CustomStringConvertible {
            let description =
                "Setup failure (not the defect): seeded rows never reached a " +
                "stable readable order"
        }
        throw OrderNotReadable()
    }

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

    /// Select a Preferences pane by clicking its sidebar row (issue #62: the
    /// Settings window is now a `NavigationSplitView` source-list sidebar,
    /// replacing the old self-sizing `TabView` whose toolbar collapsed extra
    /// tabs behind a ">>" overflow chevron once 8+ panes no longer fit).
    /// Matched element-type-agnostically — a sidebar row's XCUITest
    /// classification (outline row vs. static text) is not stable across
    /// macOS releases — mirroring `rowElement(in:containing:)` above.
    @MainActor
    @discardableResult
    func selectPreferencesPane(_ app: XCUIApplication, _ label: String, timeout: TimeInterval = 4) -> Bool {
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
        guard row.waitForExistence(timeout: timeout), row.isHittable else { return false }
        row.click()
        return true
    }
}
