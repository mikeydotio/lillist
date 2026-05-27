import Foundation

/// Platform-agnostic row descriptor consumed by `DragController`. The
/// iOS screen converts its `[FlatTaskRow]` into `[DragReorderRow]`;
/// the macOS screen flattens its `OutlineGroup` tree the same way.
/// Decouples the controller from `FlatTaskRow` (iOS-only) and
/// `TaskOutlineNode` (macOS-only).
public struct DragReorderRow: Equatable, Sendable {
    public let id: UUID
    public let parentID: UUID?
    public let depth: Int

    public init(id: UUID, parentID: UUID?, depth: Int) {
        self.id = id
        self.parentID = parentID
        self.depth = depth
    }
}
