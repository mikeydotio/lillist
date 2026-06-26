import XCTest
import CoreGraphics
@testable import LillistUI

/// Pins the `SwipeableRow` release-settle contract: a full-swipe/fling commits
/// an action only when that side allows it, otherwise the row reveals (holds
/// open) or snaps closed. The `allowsFullSwipe: false` path is the
/// reveal-then-tap guard that stops accidental swipe-to-delete.
final class SwipeSettleArbiterTests: XCTestCase {
    // The real constants from `SwipeableRow`.
    private let actionWidth: CGFloat = 84
    private let fullSwipeThreshold: CGFloat = 170

    /// Wraps the arbiter with the test fixtures and only the per-case knobs.
    private func outcome(
        offset: CGFloat,
        predicted: CGFloat,
        hasLeading: Bool = true,
        leadingFull: Bool = true,
        hasTrailing: Bool = true,
        trailingFull: Bool = true
    ) -> SwipeSettleArbiter.Outcome {
        SwipeSettleArbiter.outcome(
            offset: offset,
            predictedTranslation: predicted,
            actionWidth: actionWidth,
            fullSwipeThreshold: fullSwipeThreshold,
            hasLeading: hasLeading,
            leadingAllowsFullSwipe: leadingFull,
            hasTrailing: hasTrailing,
            trailingAllowsFullSwipe: trailingFull
        )
    }

    // MARK: - Trailing full-swipe OFF (the Delete guard)

    func test_trailingFullSwipeOff_hardPull_reveals() {
        // The reported bug: a long left-pull no longer deletes — it reveals.
        XCTAssertEqual(outcome(offset: -371, predicted: -371, trailingFull: false), .openTrailing)
    }

    func test_trailingFullSwipeOff_fastFling_reveals() {
        // The actual culprit: the non-rubber-banded fling projection used to
        // commit Delete with a tiny actual offset. Now it reveals.
        XCTAssertEqual(outcome(offset: -50, predicted: -300, trailingFull: false), .openTrailing)
    }

    // MARK: - Trailing full-swipe ON (default still commits)

    func test_trailingFullSwipeOn_hardPull_commits() {
        XCTAssertEqual(outcome(offset: -371, predicted: -371), .commitTrailing)
    }

    func test_trailingFullSwipeOn_fastFling_commits() {
        XCTAssertEqual(outcome(offset: -50, predicted: -300), .commitTrailing)
    }

    // MARK: - Leading full-swipe ON ("Mark open" keeps its shortcut)

    func test_leadingFullSwipeOn_hardPull_commits() {
        XCTAssertEqual(outcome(offset: 371, predicted: 371), .commitLeading)
    }

    func test_leadingFullSwipeOn_fastFling_commits() {
        XCTAssertEqual(outcome(offset: 40, predicted: 300), .commitLeading)
    }

    // MARK: - Boundary inclusivity

    func test_trailingCommitThreshold_isInclusive() {
        // `<= -threshold` is inclusive at exactly the threshold.
        XCTAssertEqual(outcome(offset: -170, predicted: 0), .commitTrailing)
        // Just under the threshold (and past half-width) reveals instead.
        XCTAssertEqual(outcome(offset: -169.9, predicted: 0), .openTrailing)
    }

    func test_flingThreshold_isInclusive() {
        // fling threshold = fullSwipeThreshold * 1.4 = 238, checked `<=`.
        XCTAssertEqual(outcome(offset: 0, predicted: -238), .commitTrailing)
        // Just under, with a resting offset, no commit and no reveal → close.
        XCTAssertEqual(outcome(offset: 0, predicted: -237.9), .close)
    }

    func test_openThreshold_isInclusive() {
        // `<= -actionWidth/2` (= -42) is inclusive at exactly half-width.
        XCTAssertEqual(outcome(offset: -42, predicted: 0, trailingFull: false), .openTrailing)
        XCTAssertEqual(outcome(offset: -41.9, predicted: 0, trailingFull: false), .close)
        // Symmetric leading reveal.
        XCTAssertEqual(outcome(offset: 42, predicted: 0, leadingFull: false), .openLeading)
        XCTAssertEqual(outcome(offset: 41.9, predicted: 0, leadingFull: false), .close)
    }

    // MARK: - No action present / weak swipe

    func test_noTrailingAction_neverRevealsOrCommits() {
        // A large negative pull with no trailing action just closes.
        XCTAssertEqual(outcome(offset: -371, predicted: -371, hasTrailing: false), .close)
    }

    func test_weakSwipe_closes() {
        XCTAssertEqual(outcome(offset: -20, predicted: -20), .close)
    }
}
