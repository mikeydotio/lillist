// Cross-platform: shared by the iOS app and the macOS main window.
import Foundation

/// Flat projection of a `TaskNode` tree, paired with its render depth
/// and the parent context needed to constrain drag-reorder.
public struct FlatTaskRow: Identifiable, Hashable, Sendable {
    public let node: TaskNode
    public let depth: Int
    public let parentID: UUID?
    public let hasChildren: Bool

    public var id: UUID { node.id }

    public init(node: TaskNode, depth: Int, parentID: UUID?, hasChildren: Bool) {
        self.node = node
        self.depth = depth
        self.parentID = parentID
        self.hasChildren = hasChildren
    }

    /// True when this row's true parent (`node.record.parentID`) exists but
    /// isn't this row's DISPLAY parent (`parentID`) — i.e. `TaskTree.build`
    /// promoted it to root because its real parent isn't in the current
    /// result set (LIL-97: a filter/search match whose parent doesn't also
    /// match, or a parent excluded by the active view). The app-side twin
    /// of the widget's orphan detection (`WidgetSnapshotBuilder`'s missing-
    /// parent collection feeding `showsParentMarker`, `WidgetRowPlan.swift`).
    public var isOrphan: Bool {
        parentID == nil && node.record.parentID != nil
    }
}

public enum TreeFlattener {
    /// Walk the tree depth-first, emitting one row per node. Subtrees
    /// whose roots are in `collapsed` are skipped (their parent still
    /// appears, but no descendants are emitted).
    public static func flatten(
        _ roots: [TaskNode],
        collapsed: Set<UUID> = []
    ) -> [FlatTaskRow] {
        var out: [FlatTaskRow] = []
        out.reserveCapacity(roots.count * 2)

        func walk(_ node: TaskNode, depth: Int, parentID: UUID?) {
            out.append(FlatTaskRow(
                node: node,
                depth: depth,
                parentID: parentID,
                hasChildren: !node.children.isEmpty
            ))
            if collapsed.contains(node.id) { return }
            for child in node.children {
                walk(child, depth: depth + 1, parentID: node.id)
            }
        }

        for root in roots { walk(root, depth: 0, parentID: nil) }
        return out
    }
}
