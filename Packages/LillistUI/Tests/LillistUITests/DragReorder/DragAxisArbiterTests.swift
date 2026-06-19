import XCTest
import CoreGraphics
@testable import LillistUI

/// Pins the macOS reorder-vs-swipe arbitration contract: only vertical drags
/// reorder, horizontal drags yield to the swipe, and ambiguous (diagonal /
/// tie) drags favour reorder. The gesture relies on these exact boundaries.
final class DragAxisArbiterTests: XCTestCase {
    private let commit: CGFloat = 8

    func test_belowCommitDistance_isUndecided() {
        // Largest component still under the threshold → no commitment yet.
        XCTAssertNil(DragAxisArbiter.axis(forTranslation: CGSize(width: 5, height: 7), commitDistance: commit))
        XCTAssertNil(DragAxisArbiter.axis(forTranslation: .zero, commitDistance: commit))
    }

    func test_verticalDominant_commitsVertical() {
        XCTAssertEqual(DragAxisArbiter.axis(forTranslation: CGSize(width: 2, height: 20), commitDistance: commit), .vertical)
        // Sign-independent: an upward drag commits the same way.
        XCTAssertEqual(DragAxisArbiter.axis(forTranslation: CGSize(width: -2, height: -20), commitDistance: commit), .vertical)
    }

    func test_horizontalDominant_commitsHorizontal() {
        XCTAssertEqual(DragAxisArbiter.axis(forTranslation: CGSize(width: 30, height: 4), commitDistance: commit), .horizontal)
        XCTAssertEqual(DragAxisArbiter.axis(forTranslation: CGSize(width: -30, height: 4), commitDistance: commit), .horizontal)
    }

    func test_tieFavoursVertical() {
        // dx == dy past the threshold → reorder (the row's primary gesture) wins.
        XCTAssertEqual(DragAxisArbiter.axis(forTranslation: CGSize(width: 10, height: 10), commitDistance: commit), .vertical)
    }

    func test_exactlyAtCommitDistance_commits() {
        // The boundary is inclusive (>=), so a drag exactly at the threshold commits.
        XCTAssertEqual(DragAxisArbiter.axis(forTranslation: CGSize(width: 8, height: 0), commitDistance: commit), .horizontal)
        XCTAssertEqual(DragAxisArbiter.axis(forTranslation: CGSize(width: 0, height: 8), commitDistance: commit), .vertical)
    }
}
