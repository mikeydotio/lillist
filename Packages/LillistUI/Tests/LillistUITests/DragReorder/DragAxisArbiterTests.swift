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

    // MARK: - macOS swipe consolidation (issue #18)

    /// `SwipeableRow`'s macOS branch now derives its axis from this arbiter at
    /// `macSwipeAxisCommitDistance` instead of an inlined `dx > dy` rule.
    /// This grid pins that the arbiter reproduces the *exact* historical
    /// inline decision, so routing the swipe through the shared arbiter is
    /// provably behavior-preserving. (The real-input confirmation is the
    /// macOS `MacSwipeUITests` harness; this is the pure-logic proof, which
    /// runs on any host.)
    func test_matchesHistoricalInlineSwipeRule_acrossTranslationGrid() {
        let swipeCommit = LillistDragTokens.macSwipeAxisCommitDistance

        // The exact rule SwipeableRow's macOS `swipeGesture` used before the
        // consolidation: undecided until max(|dx|,|dy|) >= 10, then
        // `dx > dy ? .horizontal : .vertical`.
        func legacyInlineAxis(_ t: CGSize) -> DragAxisArbiter.Axis? {
            let dx = abs(t.width)
            let dy = abs(t.height)
            guard max(dx, dy) >= swipeCommit else { return nil }
            return dx > dy ? .horizontal : .vertical
        }

        for w in stride(from: -30.0, through: 30.0, by: 1.0) {
            for h in stride(from: -30.0, through: 30.0, by: 1.0) {
                let translation = CGSize(width: w, height: h)
                XCTAssertEqual(
                    DragAxisArbiter.axis(forTranslation: translation, commitDistance: swipeCommit),
                    legacyInlineAxis(translation),
                    "Arbiter diverged from the legacy inline swipe rule at \(translation)"
                )
            }
        }
    }

    /// The swipe commit distance must sit past the reorder commit so a
    /// near-vertical drag commits to reorder first — the staggering that keeps
    /// the two macOS row gestures mutually exclusive.
    func test_swipeCommitDistance_isPastReorderCommit() {
        XCTAssertGreaterThan(
            LillistDragTokens.macSwipeAxisCommitDistance,
            LillistDragTokens.macReorderAxisCommitDistance
        )
    }
}
