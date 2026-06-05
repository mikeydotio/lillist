import Foundation

/// The store mutation a resolved drag-drop should perform, expressed as a
/// LillistCore-agnostic value type so the pure mapping lives in LillistUI
/// and both app targets dispatch it to `TaskStore`.
///
/// - `reorder` — `TaskStore.reorder(id:after:before:)` (the dragged ID is
///   supplied by the dispatching app, not carried here).
/// - `reparent` — `TaskStore.reparent(id:newParent:)`.
/// - `noop` — nothing to do (`.rejected` / `.none` targets).
public enum DragMutation: Equatable, Sendable {
    case reorder(after: UUID?, before: UUID?)
    case reparent(newParent: UUID?)
    case noop
}

/// Pure mapping from a resolved `DragTarget` (plus the controller's visible
/// `flatRows`) to a `DragMutation`. Single source of truth shared by macOS
/// `TaskListView.applyDrop` and iOS `TasksView.applyDrop`.
public enum DragDropResolver {
    /// - `.between` routes straight to a `reorder` using the contract's
    ///   `beforeID`/`afterID`.
    /// - `.onto` with at least one visible child of the target drops the
    ///   dragged row as the *first* child (reorder before the first child),
    ///   per the "Smart: where the cursor was" semantic; otherwise the
    ///   target is collapsed or a leaf and the dragged row is appended via
    ///   reparent.
    /// - `.rejected` / `.none` are no-ops.
    public static func resolve(
        target: DragTarget,
        flatRows: [DragReorderRow]
    ) -> DragMutation {
        switch target {
        case .between(let beforeID, let afterID, _):
            return .reorder(after: afterID, before: beforeID)
        case .onto(let parentID):
            if let firstChild = flatRows.first(where: { $0.parentID == parentID }) {
                return .reorder(after: nil, before: firstChild.id)
            } else {
                return .reparent(newParent: parentID)
            }
        case .rejected, .none:
            return .noop
        }
    }
}
