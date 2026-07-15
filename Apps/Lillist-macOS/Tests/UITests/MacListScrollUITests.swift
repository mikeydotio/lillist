import XCTest

/// macOS analogue of the iOS `ListScrollUITests` (issue #12) and the
/// evidence half of issue #18.
///
/// On iOS a finger pan is ambiguous (scroll vs. drag) and a row
/// `DragGesture` wrongly claimed it at touch-down, starving the `List`'s
/// scroll pan — the #12 defect. On macOS the two are *different event
/// streams*: scrolling is scroll-wheel / two-finger-trackpad events routed
/// to the enclosing `NSScrollView`, while a row `DragGesture` fires only on
/// mouse-button-down + move. This suite proves that distinction holds — a
/// scroll-wheel event delivered *over row content* still scrolls the list,
/// unblocked by the macOS reorder/swipe `DragGesture`s (`DragReorderable` /
/// `SwipeableRow`). If a future macOS gesture change ever intercepts
/// scroll-wheel input the way iOS drag-family gestures intercepted the
/// touch, this goes red.
///
/// macOS UITests are not run in CI (they need a signed Mac with a window
/// server); this is the standing regression guard for a manual run.
@MainActor
final class MacListScrollUITests: XCTestCase {

    /// Enough rows to overflow the main window on any reasonable display, so
    /// a mid-viewport anchor can move (or recycle) when the list scrolls.
    private static let seedCount = 24

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// A scroll-wheel gesture originating over a row's own body must scroll
    /// the list. The macOS analogue of the issue-#12 witness.
    func test_scrollWheelFromRowBody_scrollsList() throws {
        let app = MacUITestHelpers.launchGestureSeeded(count: Self.seedCount)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30),
                      "Main window never appeared")

        let anchor = try midViewportAnchor(in: app)

        // Scroll-wheel input delivered at the anchor row's location. On the
        // correct macOS event model this scrolls the enclosing List; if a row
        // gesture ever swallowed scroll-wheel input, the anchor would not move.
        anchor.element.scroll(byDeltaX: 0, deltaY: -300)

        XCTAssertTrue(
            didAnchorMove(anchor, in: app, minimum: 60),
            "Scroll-wheel over row body did not scroll the list — anchor " +
            "'\(anchor.title)' stayed put; a row gesture is swallowing " +
            "scroll-wheel input (macOS regression of the issue-#12 class)."
        )
    }

    // MARK: - Anchor plumbing

    private struct Anchor {
        let title: String
        let element: XCUIElement
        let startMinY: CGFloat
    }

    /// A seeded row fully visible in the middle band of the window (30–65 %
    /// of height) — safe to scroll over and guaranteed to move or recycle if
    /// the list scrolls.
    private func midViewportAnchor(in app: XCUIApplication) throws -> Anchor {
        let window = app.windows.firstMatch
        // Give the list a moment to populate before reading frames.
        _ = MacUITestHelpers.rowElement(in: app, containing: MacUITestHelpers.seedTitle(1))
            .waitForExistence(timeout: 10)

        let frame = window.frame
        let band = (frame.minY + frame.height * 0.30)...(frame.minY + frame.height * 0.65)
        for index in 1...Self.seedCount {
            let title = MacUITestHelpers.seedTitle(index)
            let element = MacUITestHelpers.rowElement(in: app, containing: title)
            guard element.exists, element.isHittable else { continue }
            let rowFrame = element.frame
            if band.contains(rowFrame.minY), band.contains(rowFrame.maxY) {
                return Anchor(title: title, element: element, startMinY: rowFrame.minY)
            }
        }
        struct AnchorNotFound: Error, CustomStringConvertible {
            let description =
                "Setup failure (not the defect): no fully visible mid-viewport anchor row"
        }
        throw AnchorNotFound()
    }

    /// Poll up to 3 s for the anchor to leave the hierarchy (recycled
    /// offscreen) or shift by ≥ `minimum` pt in either direction. Stabilizing
    /// conditions, never the assertion.
    private func didAnchorMove(
        _ anchor: Anchor,
        in app: XCUIApplication,
        minimum: CGFloat
    ) -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            let query = MacUITestHelpers.rowElement(in: app, containing: anchor.title)
            if !query.exists { return true }  // recycled offscreen — it scrolled
            if abs(anchor.startMinY - query.frame.minY) >= minimum { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }
}
