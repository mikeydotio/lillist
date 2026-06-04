import Foundation

/// Math for gap-based fractional ordering of sibling rows.
///
/// Each row has a `position: Double`. To insert between two neighbors,
/// we pick the midpoint of their positions. This lets us reorder without
/// renumbering — at the cost of needing periodic compaction when neighbors
/// grow close enough that further bisection underflows.
public enum FractionalPosition {
    /// The position for a new row between `after` and `before`.
    /// Nil neighbors mean "at the corresponding end" or "list is empty."
    public static func position(after: Double?, before: Double?) -> Double {
        switch (after, before) {
        case (nil, nil):
            return 1.0
        case (let a?, nil):
            return a + 1.0
        case (nil, let b?):
            return b - 1.0
        case (let a?, let b?):
            return (a + b) / 2.0
        }
    }

    /// True when the gap between neighbors is too small to safely bisect further.
    /// Triggers compaction.
    public static func gapIsTooSmall(after: Double, before: Double) -> Bool {
        before - after <= after.ulp * 4
    }

    /// True when two real (non-nil) anchors are equal or inverted, i.e. the
    /// caller asked to drop a row into a degenerate gap. Single source of
    /// truth for the reorder anchor-validation guard in both stores.
    /// A nil anchor means "the corresponding list end," which is never
    /// out of order.
    public static func anchorsAreOutOfOrder(after: Double?, before: Double?) -> Bool {
        guard let a = after, let b = before else { return false }
        return a >= b
    }

    /// True when the midpoint between `after` and `before` would underflow —
    /// i.e. both neighbors are real and `gapIsTooSmall`. Head/tail inserts
    /// (a nil neighbor) place at `±1.0` and never collide, so they return
    /// `false`. When `true`, the caller must recompact siblings before
    /// recomputing the target position.
    public static func needsCompaction(after: Double?, before: Double?) -> Bool {
        guard let a = after, let b = before else { return false }
        return gapIsTooSmall(after: a, before: b)
    }
}
