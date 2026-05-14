#if os(iOS)
import XCTest
import SwiftUI
@testable import LillistUI

final class SizeClassRouterTests: XCTestCase {
    func test_regular_returns_split() {
        XCTAssertEqual(SizeClassRouter.layout(for: .regular), .split)
    }

    func test_compact_returns_tab() {
        XCTAssertEqual(SizeClassRouter.layout(for: .compact), .tab)
    }

    func test_nil_returns_tab_conservative_default() {
        XCTAssertEqual(SizeClassRouter.layout(for: nil), .tab)
    }
}
#endif
