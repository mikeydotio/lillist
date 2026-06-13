import XCTest
import SwiftUI
@testable import LillistUI
import LillistCore

/// Pins the Rainbow Logic status → hue mapping. Changing a status hue
/// is a product decision (update the design system doc), not a
/// refactor side-effect — this test makes the swap a conscious act.
final class StatusPaletteTests: XCTestCase {

    func testStatusColorMapping() {
        assertSameResolved(StatusPalette.color(for: .todo), LillistColor.textFaint)
        assertSameResolved(StatusPalette.color(for: .started), RainbowPalette.focusBlue.base)
        assertSameResolved(StatusPalette.color(for: .blocked), RainbowPalette.actionOrange.base)
        assertSameResolved(StatusPalette.color(for: .closed), RainbowPalette.growthGreen.base)
    }

    func testStatusInkMapping() {
        assertSameResolved(StatusPalette.ink(for: .todo), LillistColor.textMuted)
        assertSameResolved(StatusPalette.ink(for: .started), RainbowPalette.focusBlue.ink)
        assertSameResolved(StatusPalette.ink(for: .blocked), RainbowPalette.actionOrange.ink)
        assertSameResolved(StatusPalette.ink(for: .closed), RainbowPalette.growthGreen.ink)
    }

    private func assertSameResolved(
        _ a: Color, _ b: Color,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for dark in [false, true] {
            XCTAssertEqual(
                RainbowPaletteTests.resolve(a, dark: dark),
                RainbowPaletteTests.resolve(b, dark: dark),
                "scheme: \(dark ? "dark" : "light")",
                file: file, line: line
            )
        }
    }
}
