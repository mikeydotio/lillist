#if os(macOS)
import XCTest
@testable import LillistUI

@MainActor
final class AnnouncementsTests: XCTestCase {
    /// Smoke: posting an announcement does not crash and does not block.
    /// (Verifying that AX actually heard the announcement requires a UI
    /// test with an AT enabled — out of scope for unit tests.)
    func test_post_does_not_throw() {
        AccessibilityAnnouncements.post("Sync complete")
        AccessibilityAnnouncements.post("Sync error: Network unavailable", priority: .high)
    }
}
#endif
