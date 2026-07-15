import XCTest

/// Reproduction for GitHub issue #12 (RCA `ios-list-scroll-blocked-when`):
/// the iOS tasks list (`TasksScreen`'s `List`) cannot be scrolled when a
/// vertical drag starts on row content — only the thin listRowInsets
/// margins (6 pt leading / 12 pt trailing) and inter-row gaps scroll.
/// Suspected cause: the row label's sequenced long-press+drag reorder
/// gesture (`DragReorderable`) and/or the card-wide
/// `.simultaneousGesture(DragGesture(minimumDistance: 10))`
/// (`SwipeableRow`) starving the List's scroll pan recognizer.
///
/// Diagnostic signal: after a vertical drag, a fully visible mid-viewport
/// anchor row must either leave the accessibility hierarchy (List cells
/// recycle offscreen) or move up by ≥ 60 pt. On the defective build the
/// two row-body tests fail with "List did not scroll — …"; the
/// trailing-margin control test passes (the reporter confirms margins
/// still scroll), proving the assertion mechanics are sound.
///
/// Deliberately self-contained: launch/capture plumbing is duplicated
/// from `UITestHelpers` (per RCA scope rules — no shared-file edits) so
/// this file alone is the executable definition of "fixed".
@MainActor
final class ListScrollUITests: XCTestCase {

    // MARK: - One-time seeding

    /// Whether this test process has already reset + seeded the store.
    /// Static so the ~20 Quick Capture round-trips happen once per run;
    /// every test then just relaunches the existing store (scroll
    /// position resets to top on each launch, keeping tests independent).
    private static var hasSeeded = false

    /// Enough rows to guarantee viewport overflow on an iPhone-class
    /// simulator (~14 rows visible).
    private static let seedCount = 20

    private static func seedTitle(_ index: Int) -> String {
        String(format: "Scroll seed %02d", index)
    }

    /// First call: fresh store, seed `seedCount` tasks via Quick Capture,
    /// relaunch (the unfiltered list does not reload after in-session
    /// captures). Subsequent calls: relaunch the existing store.
    private static func seededApp() -> XCUIApplication {
        if !hasSeeded {
            let fresh = launch(arguments: ["--ui-test-reset-store", "--ui-test-bypass-gates"])
            for index in 1...seedCount {
                createTask(titled: seedTitle(index), in: fresh)
            }
            fresh.terminate()
            hasSeeded = true
        }
        let app = launch(arguments: ["--ui-test-bypass-gates"])

        // Seed verification (setup, not the defect): the relaunched list
        // must show enough rows to overflow the viewport.
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if app.cells.count >= 10 { return app }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTFail(
            "Setup failure (not the defect): expected >= 10 seeded rows " +
            "after relaunch, found \(app.cells.count)"
        )
        return app
    }

    /// Duplicated from `UITestHelpers.launchFresh/launchExisting` +
    /// `dismissOnboardingIfPresent` (defensive Skip poll).
    private static func launch(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += arguments
        app.launch()
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if app.buttons["TasksSettingsButton"].exists { return app }
            let skip = app.buttons["Skip for now"]
            if skip.exists {
                skip.tap()
                return app
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return app
    }

    /// Duplicated from `UITestHelpers.createTask`, with a fixed title.
    private static func createTask(titled title: String, in app: XCUIApplication) {
        let fab = app.buttons["TasksQuickCaptureFAB"]
        let emptyState = app.buttons["TasksEmptyStateCaptureButton"]
        var opened = false
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if emptyState.exists { emptyState.tap(); opened = true; break }
            if fab.exists { fab.tap(); opened = true; break }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertTrue(
            opened,
            "Setup failure (not the defect): no Quick Capture entry point for '\(title)'"
        )

        let field = app.textFields["QuickCaptureField"]
        XCTAssertTrue(
            field.waitForExistence(timeout: 5),
            "Setup failure (not the defect): QuickCaptureField missing for '\(title)'"
        )
        field.tap()
        field.typeText(title)
        // The dialog has no Save button; Return submits.
        app.typeText("\n")
        let dismissDeadline = Date().addingTimeInterval(5)
        while Date() < dismissDeadline, field.exists {
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertFalse(
            field.exists,
            "Setup failure (not the defect): Quick Capture did not dismiss after '\(title)'"
        )
    }

    // MARK: - Anchor + assertion plumbing

    private struct Anchor {
        let title: String
        let cell: XCUIElement
        let startMinY: CGFloat
    }

    /// A seeded row that is fully visible in the middle of the viewport
    /// (30–65 % of window height) — safe to drag on and guaranteed to
    /// move (or recycle out of the hierarchy) if the list scrolls.
    private func midViewportAnchor(in app: XCUIApplication) throws -> Anchor {
        let windowHeight = app.windows.firstMatch.frame.height
        let band = (windowHeight * 0.30)...(windowHeight * 0.65)
        for index in 1...Self.seedCount {
            let title = Self.seedTitle(index)
            let cell = app.cells
                .containing(NSPredicate(format: "label CONTAINS[c] %@", title))
                .firstMatch
            guard cell.exists, cell.isHittable else { continue }
            let frame = cell.frame
            if band.contains(frame.minY), band.contains(frame.maxY) {
                return Anchor(title: title, cell: cell, startMinY: frame.minY)
            }
        }
        struct AnchorNotFound: Error, CustomStringConvertible {
            let description =
                "Setup failure (not the defect): no fully visible mid-viewport anchor row"
        }
        throw AnchorNotFound()
    }

    /// The diagnostic-signal assertion: after `drag(anchor)` runs, the
    /// anchor must leave the hierarchy (cell recycled offscreen) or its
    /// frame.minY must drop by ≥ 60 pt. Polls up to 3 s so flick
    /// deceleration and slow synthesized drags have time to settle —
    /// stabilizing conditions, never the assertion. The resolved anchor
    /// is handed to the closure so a drag can start on the anchor cell
    /// itself without re-resolving (and without any silent-skip path
    /// that could fail the assertion for the wrong reason).
    private func assertListScrolls(
        in app: XCUIApplication,
        after drag: (Anchor) -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let anchor = try midViewportAnchor(in: app)

        drag(anchor)

        let requiredMovement: CGFloat = 60
        let deadline = Date().addingTimeInterval(3)
        var lastY = anchor.startMinY
        while Date() < deadline {
            let query = app.cells
                .containing(NSPredicate(format: "label CONTAINS[c] %@", anchor.title))
                .firstMatch
            if !query.exists { return }  // recycled offscreen — the list scrolled
            lastY = query.frame.minY
            if anchor.startMinY - lastY >= requiredMovement { return }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTFail(
            "List did not scroll — anchor '\(anchor.title)' still at y=\(lastY) " +
            "(moved \(anchor.startMinY - lastY)pt, needed >= \(requiredMovement)pt)",
            file: file,
            line: line
        )
    }

    // MARK: - Tests

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// A fast flick starting on the row's text label (well clear of the
    /// leading 44 pt status circle and the trailing inset) must scroll
    /// the list. EXPECTED on the defective build: FAILS (issue #12).
    func test_flickOnRowBody_doesScroll() throws {
        let app = Self.seededApp()
        try assertListScrolls(in: app, after: { anchor in
            // The flick starts on the anchor's own label region: dx 0.6 /
            // dy 0.5 of the cell, driven with a fast synthesized drag so
            // the touch carries flick velocity.
            let start = anchor.cell.coordinate(
                withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)
            )
            let end = start.withOffset(CGVector(dx: 0, dy: -300))
            start.press(
                forDuration: 0.02,
                thenDragTo: end,
                withVelocity: .fast,
                thenHoldForDuration: 0
            )
        })
    }

    /// A slow deliberate drag starting on the same label coordinate must
    /// also scroll (content tracks the finger). Press stays well under
    /// the 0.3 s reorder long-press gate, and motion starts immediately,
    /// so this can never legitimately become a reorder.
    /// EXPECTED on the defective build: FAILS (issue #12).
    func test_slowDragOnRowBody_doesScroll() throws {
        let app = Self.seededApp()
        try assertListScrolls(in: app, after: { anchor in
            let start = anchor.cell.coordinate(
                withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)
            )
            let end = start.withOffset(CGVector(dx: 0, dy: -300))
            start.press(
                forDuration: 0.05,
                thenDragTo: end,
                withVelocity: .slow,
                thenHoldForDuration: 0
            )
        })
    }

    /// Control arm: the same drag starting in the trailing listRowInsets
    /// margin (dx 0.985 of the window — inside the 12 pt trailing inset,
    /// outside every row card) must scroll. The reporter confirms margins
    /// scroll on the defective build, so this test passing proves the
    /// anchor/assertion mechanics; if THIS fails, the mechanics are
    /// broken — never weaken the assertion to force the other arms red.
    func test_dragInTrailingMargin_doesScroll() throws {
        let app = Self.seededApp()
        let window = app.windows.firstMatch
        try assertListScrolls(in: app, after: { _ in
            let start = window.coordinate(
                withNormalizedOffset: CGVector(dx: 0.985, dy: 0.55)
            )
            let end = window.coordinate(
                withNormalizedOffset: CGVector(dx: 0.985, dy: 0.20)
            )
            start.press(forDuration: 0.05, thenDragTo: end)
        })
    }
}
