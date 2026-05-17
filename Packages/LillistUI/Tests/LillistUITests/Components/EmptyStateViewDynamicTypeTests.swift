import XCTest
@testable import LillistUI

@MainActor
final class EmptyStateViewDynamicTypeTests: XCTestCase {
    /// EmptyStateView's icon must scale with Dynamic Type via an
    /// explicit `@ScaledMetric` so the base size is pinned by this
    /// component, not by Apple's evolving `.largeTitle` metric.
    func test_iconSize_isScaledMetric() throws {
        let path = "\(#filePath)"
            .replacingOccurrences(of: "Tests/LillistUITests/Components/EmptyStateViewDynamicTypeTests.swift",
                                  with: "Sources/LillistUI/Components/EmptyStateView.swift")
        let source = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(
            source.contains("@ScaledMetric"),
            "EmptyStateView must use @ScaledMetric so its icon scales with Dynamic Type."
        )
        XCTAssertFalse(
            source.contains("LillistTypography.largeTitle.weight(.light)"),
            "EmptyStateView must not delegate the icon font to LillistTypography.largeTitle — pin the base size locally."
        )
    }
}
