import Foundation

/// Resolved drop intent for a given cursor location.
///
/// - `between` — the dragged row will land between two siblings of
///   `parentID`. Either anchor may be `nil` (start or end of the
///   sibling group). Routes to `TaskStore.reorder(id:after:before:)`.
/// - `onto` — the dragged row will become a child of `targetID`,
///   appended to the end. Routes to
///   `TaskStore.reparent(id:newParent:)`.
/// - `rejected` — the cursor resolves to a target that would create a
///   cycle (drop onto self or own descendant). The UI shows a red
///   border on the phantom; release cancels.
/// - `none` — cursor is outside any drop region or in a disabled zone
///   for the current sort mode. No indicator is drawn.
public enum DragTarget: Equatable, Sendable {
    case between(beforeID: UUID?, afterID: UUID?, parentID: UUID?)
    case onto(targetID: UUID)
    case rejected
    case none
}
