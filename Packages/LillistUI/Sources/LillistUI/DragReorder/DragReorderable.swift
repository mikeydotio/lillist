import SwiftUI
#if os(iOS)
import UIKit
#endif

extension View {
    /// Attaches the drag-reorder gesture and geometry reporter to a
    /// row. iOS requires a long-press first to disambiguate from
    /// scroll; macOS uses a plain `DragGesture` (mouse-down + slop).
    ///
    /// ⚠️ Never lay this over interactive controls (buttons, menus):
    /// the long-press sequence eats their quick taps — that shipped as
    /// the dead status-circle regression (engineering-notes
    /// 2026-06-12). For rows with embedded controls, keep
    /// `.reportRowGeometry(id:)` on the full row and attach
    /// `.dragReorderGesture(id:controller:)` to the inert region only.
    public func dragReorderable(
        id: UUID,
        controller: DragController
    ) -> some View {
        reportRowGeometry(id: id)
            .modifier(DragReorderGestureModifier(id: id, controller: controller))
    }

    /// Gesture-only variant of `dragReorderable(id:controller:)`: no
    /// geometry reporting. Attach to the non-interactive region of a
    /// row whose full frame is reported separately via
    /// `.reportRowGeometry(id:)`.
    public func dragReorderGesture(
        id: UUID,
        controller: DragController
    ) -> some View {
        modifier(DragReorderGestureModifier(id: id, controller: controller))
    }
}

struct DragReorderGestureModifier: ViewModifier {
    let id: UUID
    @ObservedObject var controller: DragController
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var overrideReduceMotion

    func body(content: Content) -> some View {
        content
            .gesture(platformGesture)
    }

    /// Effective reduce-motion: app-level override beats the system
    /// setting. When `true` the lift/settle animations collapse to
    /// instant transitions (settleDuration → 0).
    private var reduceMotion: Bool {
        overrideReduceMotion ?? systemReduceMotion
    }

    private var settleDuration: TimeInterval {
        reduceMotion ? 0 : LillistDragTokens.settleDuration
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
                    // Anchor on the row's natural midY (a reliable value
                    // in the named coordinate space). Don't use
                    // `drag.location.y` — at the first `.second` event
                    // of the sequenced gesture it can be reported in an
                    // unexpected coordinate space, causing the phantom
                    // to snap to the viewport top.
                    controller.beginDrag(
                        rowID: id,
                        originalHeight: frame.height,
                        cursorY: frame.midY
                    )
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                // Track motion via translation — the coordinate-space-
                // invariant delta from drag start — applied on top of
                // the captured anchor.
                let cursorY = currentCursorY(translation: drag.translation.height)
                controller.updateCursor(translation: drag.translation.height)
                let resolved = controller.resolveTarget(
                    forDraggedID: id,
                    atY: cursorY
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
            controller.endDrag(settleDuration: settleDuration)
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
                    cursorY: frame.midY
                )
                NSHapticFeedbackManager.defaultPerformer.perform(
                    .alignment, performanceTime: .now
                )
            }
            let cursorY = currentCursorY(translation: drag.translation.height)
            controller.updateCursor(translation: drag.translation.height)
            let resolved = controller.resolveTarget(
                forDraggedID: id,
                atY: cursorY
            )
            if resolved != currentTarget() {
                controller.setResolvedTarget(resolved)
            }
        }
        .onEnded { _ in
            controller.endDrag(settleDuration: settleDuration)
        }
    }
    #endif

    /// Compute the cursor Y the resolver should see for a given
    /// translation — `initialCursorY + translation`. Falls back to
    /// the row's current geometry frame if the controller hasn't yet
    /// transitioned to `.dragging` (shouldn't happen in practice, but
    /// keeps the resolver call total).
    private func currentCursorY(translation: CGFloat) -> CGFloat {
        if case .dragging(let session) = controller.state {
            return session.initialCursorY + translation
        }
        return (controller.geometry[id]?.midY ?? 0) + translation
    }

    private func currentTarget() -> DragTarget {
        if case .dragging(let s) = controller.state { return s.target }
        return .none
    }
}
