import XCTest
import LillistUI

/// The empty-title gate lives inside `QuickCaptureDialogHost.submit()`
/// — the new Spotlight-style dialog has no Save button to disable, so
/// the gate that used to live on `.disabled(trimmedTitleIsEmpty)`
/// moved into `submit()` itself (Plan 22). This file pins the
/// predicate: if a future change drops the guard, the integration
/// path can create empty-title tasks.
///
/// The iOS test bundle is standalone (no test host) and can't
/// `@testable import Lillist_iOS`. Drift between this mirror and the
/// production predicate inside `QuickCaptureDialogHost.submit()` is
/// the failure mode this test catches.
final class QuickCaptureDialogGuardTests: XCTestCase {
    private func trimmedTitleIsEmpty(_ raw: String) -> Bool {
        QuickCaptureParser.parse(raw).title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    func test_empty_string_is_empty() {
        XCTAssertTrue(trimmedTitleIsEmpty(""))
    }

    func test_only_whitespace_is_empty() {
        XCTAssertTrue(trimmedTitleIsEmpty("   "))
    }

    func test_only_tags_is_empty() {
        XCTAssertTrue(trimmedTitleIsEmpty("#errands #shopping"))
    }

    func test_plain_title_is_not_empty() {
        XCTAssertFalse(trimmedTitleIsEmpty("Buy milk"))
    }

    func test_title_with_tag_is_not_empty() {
        XCTAssertFalse(trimmedTitleIsEmpty("Buy milk #errands"))
    }
}
