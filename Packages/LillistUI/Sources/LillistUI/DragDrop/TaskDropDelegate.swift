import SwiftUI
import Foundation

/// SwiftUI drop delegate that maps drop location to a `DropPosition` and
/// dispatches to the appropriate handler. The owning view supplies handlers
/// that ultimately call `TaskStore.reorder` (for `.before`/`.after`) or
/// `TaskStore.reparent` (for `.onto`).
@MainActor
public struct TaskDropDelegate: DropDelegate {
    public let targetTaskID: UUID
    public let rowHeight: CGFloat
    public let onReorder: (_ dragged: UUID, _ before: Bool) -> Void
    public let onReparent: (_ dragged: UUID, _ newParent: UUID) -> Void

    public init(
        targetTaskID: UUID,
        rowHeight: CGFloat,
        onReorder: @escaping (UUID, Bool) -> Void,
        onReparent: @escaping (UUID, UUID) -> Void
    ) {
        self.targetTaskID = targetTaskID
        self.rowHeight = rowHeight
        self.onReorder = onReorder
        self.onReparent = onReparent
    }

    public func performDrop(info: DropInfo) -> Bool {
        let position = DropPosition.classify(yInRow: info.location.y, rowHeight: rowHeight)
        guard let provider = info.itemProviders(for: [.lillistTask]).first else { return false }
        _ = provider.loadTransferable(type: TaskDragPayload.self) { result in
            guard case .success(let payload) = result else { return }
            DispatchQueue.main.async {
                switch position {
                case .before:  self.onReorder(payload.taskID, true)
                case .after:   self.onReorder(payload.taskID, false)
                case .onto:    self.onReparent(payload.taskID, self.targetTaskID)
                }
            }
        }
        return true
    }
}
