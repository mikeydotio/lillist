#if os(iOS)
import XCTest
import SwiftUI
import UIKit
@testable import LillistUI

final class QuickCaptureFieldTests: XCTestCase {
    func test_tag_and_date_tokens_roundtrip_into_a_result() {
        let result = QuickCaptureParser.parse("Buy milk #errands ^tomorrow")
        XCTAssertEqual(result.title, "Buy milk")
        XCTAssertEqual(result.tags, ["errands"])
        XCTAssertEqual(result.dateToken, "tomorrow")
    }

    func test_multiple_tags_parse() {
        let result = QuickCaptureParser.parse("Fix bug #ios #urgent")
        XCTAssertEqual(result.title, "Fix bug")
        XCTAssertEqual(result.tags, ["ios", "urgent"])
        XCTAssertNil(result.dateToken)
    }

    @MainActor
    func test_token_chips_view_handles_empty_parse() {
        let parsed = QuickCaptureParser.parse("")
        let view = QuickCaptureTokenChips(parsed: parsed)
        let host = UIHostingController(rootView: view)
        host.view.layoutIfNeeded()
        // EmptyView collapses to zero size; just confirm no crash and bound is non-negative.
        XCTAssertGreaterThanOrEqual(host.view.bounds.height, 0)
    }
}
#endif
