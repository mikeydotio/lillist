import Foundation

/// The store mutation a resolved drag-drop should perform, expressed as a
/// LillistCore-agnostic value type so the pure mapping lives in LillistUI
/// and both app targets dispatch it to `TaskStore`.
///
/// - `reorder` — `TaskStore.reorder(id:after:before:parent:)`. `parent` is the
///   authoritative target parent (`nil` = top level); the dispatching app wraps
///   it in `TaskStore.ReparentTarget.explicit`. The dragged ID is supplied by
///   the app, not carried here.
/// - `reparent` — `TaskStore.reparent(id:newParent:)` (append to the end of the
///   target parent's children).
/// - `noop` — nothing to do (`.rejected` / `.none` targets).
public enum DragMutation: Equatable, Sendable {
    case reorder(parent: UUID?, after: UUID?, before: UUID?)
    case reparent(newParent: UUID?)
    case noop
}

/// Pure mapping from a resolved `DragTarget` to a `DragMutation`. Single source
/// of truth shared by macOS `TaskListView.applyDrop` and iOS
/// `TasksView.applyDrop`.
public enum DragDropResolver {
    /// - `.between` with at least one sibling anchor routes to a `reorder`
    ///   carrying the authoritative `parentID` (so a de-parent to top level is
    ///   honored, not re-inferred from the anchors).
    /// - `.between` with **no** anchors (both `nil`) means the dragged row is the
    ///   only/first child of `parentID` — there is no sibling to position
    ///   against — so it routes to `reparent`, which appends to the end of the
    ///   target parent's children. This also covers nesting under a childless or
    ///   collapsed parent.
    /// - `.rejected` / `.none` are no-ops.
    public static func resolve(target: DragTarget) -> DragMutation {
        switch target {
        case .between(let beforeID, let afterID, let parentID):
            if beforeID == nil, afterID == nil {
                return .reparent(newParent: parentID)
            }
            return .reorder(parent: parentID, after: afterID, before: beforeID)
        case .rejected, .none:
            return .noop
        }
    }
}
