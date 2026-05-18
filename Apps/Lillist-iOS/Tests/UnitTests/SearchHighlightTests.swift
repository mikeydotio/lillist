import XCTest
import SwiftUI
import LillistUI

/// Pins the search-highlight contract. Plan 20a Task 4d lifted the
/// `SearchResultRow` view (and its `highlightedTitle` helper) into
/// `LillistUI` as `SearchResultRowView`, so this test now exercises the
/// production code directly instead of duplicating the rule.
final class SearchHighlightTests: XCTestCase {
    static func highlightedTitle(title: String, query: String) -> AttributedString {
        SearchResultRowView.highlightedTitle(title: title, query: query)
    }

    func test_highlight_marks_matched_range() {
        let attr = Self.highlightedTitle(title: "Buy milk at the store", query: "milk")
        var highlightedSubstrings: [String] = []
        for run in attr.runs where run.backgroundColor != nil {
            highlightedSubstrings.append(String(attr.characters[run.range]))
        }
        XCTAssertEqual(highlightedSubstrings, ["milk"])
    }

    func test_highlight_case_insensitive_match() {
        let attr = Self.highlightedTitle(title: "Buy MILK now", query: "milk")
        let highlightedRun = attr.runs.first { $0.backgroundColor != nil }
        XCTAssertNotNil(highlightedRun)
        XCTAssertEqual(String(attr.characters[highlightedRun!.range]), "MILK")
    }

    func test_highlight_no_match_returns_plain() {
        let attr = Self.highlightedTitle(title: "Buy bread", query: "milk")
        let highlightedRuns = attr.runs.filter { $0.backgroundColor != nil }
        XCTAssertTrue(highlightedRuns.isEmpty)
    }

    func test_empty_query_returns_plain() {
        let attr = Self.highlightedTitle(title: "Buy milk", query: "")
        let highlightedRuns = attr.runs.filter { $0.backgroundColor != nil }
        XCTAssertTrue(highlightedRuns.isEmpty)
    }
}
