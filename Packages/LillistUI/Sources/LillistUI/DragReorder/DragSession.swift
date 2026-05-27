import CoreGraphics
import Foundation

/// Snapshot of the active drag. The controller publishes a new
/// instance each time the cursor moves or the resolved target
/// changes; SwiftUI consumes it to position the phantom and the
/// drop indicator.
public struct DragSession: Equatable, Sendable {
    public let draggedID: UUID
    public let originalHeight: CGFloat
    public var cursorY: CGFloat
    public var target: DragTarget

    public init(
        draggedID: UUID,
        originalHeight: CGFloat,
        cursorY: CGFloat,
        target: DragTarget
    ) {
        self.draggedID = draggedID
        self.originalHeight = originalHeight
        self.cursorY = cursorY
        self.target = target
    }
}
