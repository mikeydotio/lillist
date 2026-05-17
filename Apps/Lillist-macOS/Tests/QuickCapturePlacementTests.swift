import XCTest
import AppKit

final class QuickCapturePlacementTests: XCTestCase {
    func test_origin_centersHorizontally_thirdFromTop() {
        // 1920×1080 screen with 25pt menu bar at the top:
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let visible = NSRect(x: 0, y: 0, width: 1920, height: 1055)
        let panel  = NSSize(width: 560, height: 140)

        let origin = QuickCapturePlacementMath.placementOrigin(
            screenFrame: screen,
            visibleFrame: visible,
            panelSize: panel
        )

        // Horizontal: centered → (1920 - 560) / 2 = 680
        XCTAssertEqual(origin.x, 680, accuracy: 0.5)
        // Vertical: ~1/3 from the top of the visible frame; AppKit's
        // coordinate space has origin at bottom-left, so the panel's
        // origin.y = visible.maxY - (visible.height / 3) - panel.height.
        let expectedY = visible.maxY - (visible.height / 3) - panel.height
        XCTAssertEqual(origin.y, expectedY, accuracy: 0.5)
    }

    func test_origin_offsetSecondaryScreen() {
        // 1440×900 secondary screen positioned to the right of a 2560
        // primary, with a 25pt menu bar.
        let screen = NSRect(x: 2560, y: 0, width: 1440, height: 900)
        let visible = NSRect(x: 2560, y: 0, width: 1440, height: 875)
        let panel  = NSSize(width: 560, height: 140)

        let origin = QuickCapturePlacementMath.placementOrigin(
            screenFrame: screen,
            visibleFrame: visible,
            panelSize: panel
        )

        XCTAssertEqual(origin.x, 2560 + (1440 - 560) / 2, accuracy: 0.5)
    }
}
