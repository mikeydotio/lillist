import Foundation

/// What the controller needs to know about sort. Sibling-reorder
/// (between-row drops) only makes sense in personalized sort, since
/// other sorts override the user's manual position.
public enum DragSortMode: Sendable {
    case personalized
    case sortedByOther
}
