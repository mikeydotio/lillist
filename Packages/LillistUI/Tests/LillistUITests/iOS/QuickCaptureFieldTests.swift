#if os(iOS)
import XCTest
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
}
#endif
