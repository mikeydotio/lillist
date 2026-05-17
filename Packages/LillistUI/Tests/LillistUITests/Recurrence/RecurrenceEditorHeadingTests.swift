import XCTest
@testable import LillistUI

@MainActor
final class RecurrenceEditorHeadingTests: XCTestCase {
    /// Every Section in RecurrenceEditorView must wrap its title in
    /// Text(...).accessibilityAddTraits(.isHeader) so the VoiceOver
    /// heading rotor surfaces them consistently across iOS and macOS.
    func test_everySection_marksHeaderTrait() throws {
        let path = "\(#filePath)"
            .replacingOccurrences(of: "Tests/LillistUITests/Recurrence/RecurrenceEditorHeadingTests.swift",
                                  with: "Sources/LillistUI/Recurrence/RecurrenceEditorView.swift")
        let source = try String(contentsOfFile: path, encoding: .utf8)

        let plainSectionTitles = ["\"Frequency\"", "\"On days\"",
                                   "\"On days of month\"", "\"Limit\"",
                                   "\"Repeat after\""]

        for title in plainSectionTitles {
            XCTAssertFalse(
                source.contains("Section(\(title))"),
                "Section(\(title)) must be Section(header: Text(\(title)).accessibilityAddTraits(.isHeader))"
            )
            XCTAssertTrue(
                source.contains("Text(\(title)).accessibilityAddTraits(.isHeader)"),
                "Section(\(title)) must wrap its title in Text(...).accessibilityAddTraits(.isHeader)"
            )
        }
    }
}
