import CoreGraphics

/// Pure settle decision for a released `SwipeableRow` drag: given where the row
/// came to rest and how hard it was flung, decide whether to commit an action,
/// hold a side open (revealed), or snap closed.
///
/// Extracted from `SwipeableRow.settle(predictedTranslation:)` so the policy is
/// unit-testable in isolation (the gesture itself is not), mirroring
/// `DragAxisArbiter`. The ordering is load-bearing — trailing is checked before
/// leading, and full-swipe before open — so it matches the historical behavior
/// exactly; the only added rule is the per-side `allowsFullSwipe` gate, which
/// lets a side (e.g. Delete) opt out of swipe-to-trigger and reveal-then-tap
/// instead.
enum SwipeSettleArbiter {
    enum Outcome: Equatable {
        case commitLeading
        case commitTrailing
        case openLeading
        case openTrailing
        case close
    }

    /// - Parameters:
    ///   - offset: Current (rubber-banded) row offset. Positive reveals the
    ///     leading action, negative reveals the trailing action.
    ///   - predictedTranslation: The gesture's projected end translation
    ///     (UIKit's raw, *non*-rubber-banded fling projection).
    ///   - actionWidth: Resting reveal width of a held-open action.
    ///   - fullSwipeThreshold: Displacement past which a release commits the
    ///     action outright (when full-swipe is allowed).
    ///   - hasLeading / hasTrailing: Whether an action exists on that side.
    ///   - leadingAllowsFullSwipe / trailingAllowsFullSwipe: Whether that
    ///     side may commit on a full-swipe/fling. When `false`, a hard pull or
    ///     fling reveals (holds open) instead of committing.
    static func outcome(
        offset: CGFloat,
        predictedTranslation: CGFloat,
        actionWidth: CGFloat,
        fullSwipeThreshold: CGFloat,
        hasLeading: Bool,
        leadingAllowsFullSwipe: Bool,
        hasTrailing: Bool,
        trailingAllowsFullSwipe: Bool
    ) -> Outcome {
        // Full-swipe: a strong fling or a long pull commits the action — but
        // only when that side allows it.
        if hasTrailing, trailingAllowsFullSwipe,
           offset <= -fullSwipeThreshold || predictedTranslation <= -fullSwipeThreshold * 1.4 {
            return .commitTrailing
        }
        if hasLeading, leadingAllowsFullSwipe,
           offset >= fullSwipeThreshold || predictedTranslation >= fullSwipeThreshold * 1.4 {
            return .commitLeading
        }
        // Otherwise snap open (held) or closed.
        if offset <= -actionWidth / 2, hasTrailing {
            return .openTrailing
        }
        if offset >= actionWidth / 2, hasLeading {
            return .openLeading
        }
        return .close
    }
}
