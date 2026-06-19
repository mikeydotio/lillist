import Foundation

/// Resolved drop intent for a given cursor location.
///
/// - `between` — the dragged row will land at `parentID`'s depth, between two
///   siblings of `parentID`. Either anchor may be `nil` (start or end of the
///   sibling group); both `nil` means the dragged row is the only/first child
///   of `parentID` (no siblings to anchor against). `parentID` is the
///   authoritative target parent the resolver chose from the cursor's vertical
///   gap and horizontal depth — `nil` is top level. Routes to
///   `TaskStore.reorder(id:after:before:parent:)` (or `reparent` when there are
///   no sibling anchors).
/// - `rejected` — the cursor resolves to a target that would create a
///   cycle (drop into the dragged row's own subtree). The UI shows a red
///   border on the phantom; release cancels.
/// - `none` — cursor is outside any drop region or in a disabled zone
///   for the current sort mode. No indicator is drawn.
public enum DragTarget: Equatable, Sendable {
    case between(beforeID: UUID?, afterID: UUID?, parentID: UUID?)
    case rejected
    case none
}
