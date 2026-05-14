import CoreGraphics

/// Where in a target row a drag landed, per design Section 7.
public enum DropPosition: Equatable, Sendable {
    case before   // drop above this row → reorder (insert as previous sibling)
    case onto     // drop on this row → reparent (becomes a child)
    case after    // drop below this row → reorder (insert as next sibling)

    /// Classify a y-coordinate within the row's local space.
    /// Top 25% = before, middle 50% = onto, bottom 25% = after.
    public static func classify(yInRow: CGFloat, rowHeight: CGFloat) -> DropPosition {
        let topBand    = rowHeight * 0.25
        let bottomBand = rowHeight * 0.75
        if yInRow < topBand    { return .before }
        if yInRow > bottomBand { return .after }
        return .onto
    }
}
