import XCTest
@testable import LillistUI
import SwiftUI

/// Pins the Rainbow Logic sync-indicator mapping (see
/// `docs/plans/2026-06-12-rainbow-logic-design-system.md`): green for
/// fresh, amber for caution (stale/paused), blue for in-flight, deep
/// orange for error — orange stays reserved for urgent/error. Colors
/// are compared by per-scheme resolution (the palette colors are
/// dynamic providers, so `description` equality no longer works).
final class SyncPaletteTests: XCTestCase {
    func test_idle_with_nil_lastSync_uses_neutral_border() {
        XCTAssertEqual(SyncIndicator.idle(lastSync: nil).systemImage, "checkmark")
        assertSameResolved(SyncIndicator.idle(lastSync: nil).color, LillistColor.borderStrong)
    }

    func test_idle_recent_is_growth_green() {
        let recent = Date().addingTimeInterval(-30)  // within recencyWindow
        assertSameResolved(SyncIndicator.idle(lastSync: recent).color, RainbowPalette.growthGreen.base)
    }

    func test_idle_stale_is_caution_amber() {
        let stale = Date().addingTimeInterval(-120)  // outside recencyWindow
        assertSameResolved(SyncIndicator.idle(lastSync: stale).color, RainbowPalette.cautionAmber.base)
    }

    func test_inProgress_is_focus_blue_with_arrow_glyph() {
        assertSameResolved(SyncIndicator.inProgress.color, RainbowPalette.focusBlue.base)
        XCTAssertEqual(SyncIndicator.inProgress.systemImage, "arrow.triangle.2.circlepath")
    }

    func test_error_is_deep_orange_with_warning_glyph() {
        let err = SyncIndicator.error(message: "boom", lastSuccess: nil)
        assertSameResolved(err.color, RainbowPalette.actionOrange.deep)
        XCTAssertEqual(err.systemImage, "exclamationmark.triangle.fill")
    }

    func test_paused_is_amber_ink_with_slash_glyph() {
        let paused = SyncIndicator.paused(reason: .noNetwork)
        assertSameResolved(paused.color, RainbowPalette.cautionAmber.ink)
        XCTAssertEqual(paused.systemImage, "icloud.slash")
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
