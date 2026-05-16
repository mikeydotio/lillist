import XCTest
@testable import LillistUI
import SwiftUI

final class SyncPaletteTests: XCTestCase {
    func test_idle_with_nil_lastSync_uses_secondary() {
        XCTAssertEqual(SyncIndicator.idle(lastSync: nil).systemImage, "checkmark")
        // Color equality is intentionally compared via description because
        // SwiftUI's Color does not synthesize Equatable beyond rendering;
        // .secondary stringifies stably.
        XCTAssertEqual(String(describing: SyncIndicator.idle(lastSync: nil).color),
                       String(describing: Color.secondary))
    }

    func test_idle_recent_is_green() {
        let recent = Date().addingTimeInterval(-30)  // within recencyWindow
        XCTAssertEqual(String(describing: SyncIndicator.idle(lastSync: recent).color),
                       String(describing: Color.green))
    }

    func test_idle_stale_is_yellow() {
        let stale = Date().addingTimeInterval(-120)  // outside recencyWindow
        XCTAssertEqual(String(describing: SyncIndicator.idle(lastSync: stale).color),
                       String(describing: Color.yellow))
    }

    func test_inProgress_is_blue_with_arrow_glyph() {
        XCTAssertEqual(String(describing: SyncIndicator.inProgress.color),
                       String(describing: Color.blue))
        XCTAssertEqual(SyncIndicator.inProgress.systemImage, "arrow.triangle.2.circlepath")
    }

    func test_error_is_red_with_warning_glyph() {
        let err = SyncIndicator.error(message: "boom", lastSuccess: nil)
        XCTAssertEqual(String(describing: err.color), String(describing: Color.red))
        XCTAssertEqual(err.systemImage, "exclamationmark.triangle.fill")
    }
}
