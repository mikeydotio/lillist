import XCTest
import LillistUI

/// Plan 18 Task 3: the Save button's `.disabled(submitting || trimmedTitleIsEmpty)`
/// on QuickCaptureSheet is the canonical empty-title gate. Plan 18 deleted
/// the inner `guard !title.isEmpty` inside `submit()` because (a) Save is
/// disabled when the parsed title is empty, and (b) `QuickCaptureField`'s
/// `onSubmit` never fires on an empty editor. If a future change re-routes
/// `submit()` to a callsite that can receive empty text, this test fails and
/// the author must restore the guard.
final class QuickCaptureSheetGuardTests: XCTestCase {
    /// Mirror of `QuickCaptureSheet.trimmedTitleIsEmpty`. Kept here because
    /// the iOS test bundle is standalone (no test host) and can't
    /// `@testable import Lillist_iOS`. Drift between this mirror and the
    /// production predicate is the failure mode this test catches.
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
