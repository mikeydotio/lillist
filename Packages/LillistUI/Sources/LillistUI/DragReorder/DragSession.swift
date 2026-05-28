import CoreGraphics
import Foundation

/// Snapshot of the active drag. The controller publishes a new
/// instance each time the cursor moves or the resolved target
/// changes; SwiftUI consumes it to position the phantom and the
/// drop indicator.
///
/// `initialCursorY` is captured once at drag begin (typically the
/// source row's `frame.midY` in the named coordinate space) and acts
/// as a stable anchor: the current `cursorY` is `initialCursorY +
/// translation`, where translation comes from the gesture. The anchor
/// is also the settle target when a drop is rejected — the phantom
/// returns to the source row's original position.
public struct DragSession: Equatable, Sendable {
    public let draggedID: UUID
    public let originalHeight: CGFloat
    public let initialCursorY: CGFloat
    public var cursorY: CGFloat
    public var target: DragTarget

    public init(
        draggedID: UUID,
        originalHeight: CGFloat,
        initialCursorY: CGFloat,
        cursorY: CGFloat,
        target: DragTarget
    ) {
        self.draggedID = draggedID
        self.originalHeight = originalHeight
        self.initialCursorY = initialCursorY
        self.cursorY = cursorY
        self.target = target
    }
}
