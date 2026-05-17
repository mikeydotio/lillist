import XCTest
@testable import LillistUI

@MainActor
final class SidebarRowViewA11yTests: XCTestCase {
    /// `SidebarRowView`'s `.accessibilityElement(children: .combine)` must
    /// precede `.accessibilityLabel(...)` in the body chain so the row's
    /// combined accessibility element receives the explicit label (rather
    /// than the consumer-applied `.tag(SidebarSelection.…)` masking it).
    /// This test pins the ordering by reading the source.
    func test_rowExposesAccessibilityLabel_whenComposedWithTag() throws {
        let path = "\(#filePath)"
            .replacingOccurrences(
                of: "Tests/LillistUITests/Components/SidebarRowViewA11yTests.swift",
                with: "Sources/LillistUI/Components/SidebarRowView.swift")
        let source = try String(contentsOfFile: path, encoding: .utf8)

        // The body's `.accessibilityElement(children: .combine)` and its
        // `.accessibilityLabel(badge.map { ... })` modifiers each appear
        // exactly once in the file, so we can search the whole source.
        // The `badge.map` discriminator scopes to the body-level call (the
        // badgeView helper's own `.accessibilityLabel(...)` calls use a
        // different shape).
        let combinePos = source.range(of: ".accessibilityElement(children: .combine)")?.lowerBound
        let labelPos = source.range(of: ".accessibilityLabel(badge.map")?.lowerBound

        XCTAssertNotNil(combinePos, ".accessibilityElement(children: .combine) must be present in SidebarRowView.")
        XCTAssertNotNil(labelPos, ".accessibilityLabel(badge.map ...) must be present in SidebarRowView.")
        XCTAssertLessThan(combinePos!, labelPos!,
                          ".accessibilityElement must precede .accessibilityLabel so the combined element receives the explicit label.")
    }
}
