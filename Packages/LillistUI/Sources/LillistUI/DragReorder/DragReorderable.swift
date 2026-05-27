import SwiftUI
#if os(iOS)
import UIKit
#endif

extension View {
    /// Attaches the drag-reorder gesture and geometry reporter to a
    /// row. iOS requires a long-press first to disambiguate from
    /// scroll; macOS uses a plain `DragGesture` (mouse-down + slop).
    public func dragReorderable(
        id: UUID,
        controller: DragController
    ) -> some View {
        modifier(DragReorderableModifier(id: id, controller: controller))
    }
}

struct DragReorderableModifier: ViewModifier {
    let id: UUID
    @ObservedObject var controller: DragController

    func body(content: Content) -> some View {
        content
            .reportRowGeometry(id: id)
            .gesture(platformGesture)
    }

    #if os(iOS)
    private var platformGesture: some Gesture {
        let drag = DragGesture(
            minimumDistance: 0,
            coordinateSpace: .named(DragCoordinateSpace.name)
        )
        return LongPressGesture(
            minimumDuration: LillistDragTokens.longPressDuration,
            maximumDistance: LillistDragTokens.longPressMaxDistance
        )
        .sequenced(before: drag)
        .onChanged { (value: SequenceGesture<LongPressGesture, DragGesture>.Value) in
            switch value {
            case .first:
                // Long-press in progress, drag has not started.
                break
            case .second(_, let drag?):
                if case .idle = controller.state {
                    guard let frame = controller.geometry[id] else { break }
                    controller.beginDrag(
                        rowID: id,
                        originalHeight: frame.height,
                        cursorY: drag.location.y
                    )
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                controller.updateCursor(y: drag.location.y)
                let resolved = controller.resolveTarget(
                    forDraggedID: id,
                    atY: drag.location.y
                )
                let previous = currentTarget()
                if resolved != previous {
                    controller.setResolvedTarget(resolved)
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            default:
                break
            }
        }
        .onEnded { _ in
            controller.endDrag()
        }
    }
    #else
    private var platformGesture: some Gesture {
        DragGesture(
            minimumDistance: 4,
            coordinateSpace: .named(DragCoordinateSpace.name)
        )
        .onChanged { drag in
            if case .idle = controller.state {
                guard let frame = controller.geometry[id] else { return }
                controller.beginDrag(
                    rowID: id,
                    originalHeight: frame.height,
                    cursorY: drag.location.y
                )
                NSHapticFeedbackManager.defaultPerformer.perform(
                    .alignment, performanceTime: .now
                )
            }
            controller.updateCursor(y: drag.location.y)
            let resolved = controller.resolveTarget(
                forDraggedID: id,
                atY: drag.location.y
            )
            if resolved != currentTarget() {
                controller.setResolvedTarget(resolved)
            }
        }
        .onEnded { _ in
            controller.endDrag()
        }
    }
    #endif

    private func currentTarget() -> DragTarget {
        if case .dragging(let s) = controller.state { return s.target }
        return .none
    }
}
