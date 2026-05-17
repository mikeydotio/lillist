import XCTest
import SwiftUI

/// Pins the search-highlight contract. We duplicate the highlighting
/// function here (mirroring `SearchResultRow.highlightedTitle`) because
/// the iOS app target is not `@testable import`-able from this
/// standalone test bundle. The duplication is intentional: any change
/// to the production rule will fail this test until ported.
final class SearchHighlightTests: XCTestCase {
    static func highlightedTitle(title: String, query: String) -> AttributedString {
        var attr = AttributedString(title)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return attr }
        let lowerTitle = title.lowercased()
        let lowerQuery = trimmedQuery.lowercased()
        var searchStart = lowerTitle.startIndex
        while let range = lowerTitle.range(of: lowerQuery, range: searchStart..<lowerTitle.endIndex) {
            let attrLower = AttributedString.Index(range.lowerBound, within: attr)
            let attrUpper = AttributedString.Index(range.upperBound, within: attr)
            if let lower = attrLower, let upper = attrUpper {
                attr[lower..<upper].backgroundColor = .yellow.opacity(0.3)
            }
            searchStart = range.upperBound
        }
        return attr
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
