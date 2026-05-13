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
}
