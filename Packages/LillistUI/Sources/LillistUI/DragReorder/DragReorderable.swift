import SwiftUI
#if os(iOS)
import UIKit
#endif

extension View {
    /// Attaches the drag-reorder gesture and geometry reporter to a
    /// row. iOS bridges to a UIKit `UILongPressGestureRecognizer`
    /// (`ReorderLongPressGesture`) so arbitration with the `List`'s
    /// scroll pan happens at the UIKit layer — early movement fails the
    /// long-press and the scroll pan takes the touch; once the press
    /// matures, the recognizer owns the touch exclusively and drives
    /// the reorder. (A SwiftUI long-press+drag composition here claimed
    /// the touch stream even while failing, blocking the scroll —
    /// issue #12.) macOS uses a plain `DragGesture` (mouse-down + slop).
    ///
    /// ⚠️ Never lay this over a control with an intrinsic gesture
    /// (`Button`, `Menu`, `NavigationLink`): the control's recognizer
    /// either eats the long-press (dead reorder) or has its quick taps
    /// eaten by it (dead control) — both shipped as regressions
    /// (engineering-notes 2026-06-12 / 2026-06-17). For rows with
    /// embedded controls, keep `.reportRowGeometry(id:)` on the full row,
    /// attach `.dragReorderGesture(id:controller:)` to the inert region
    /// only, and open/activate via `.onTapGesture` (not a `Button`).
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

    #if os(macOS)
    /// Which axis the current macOS drag committed to (`nil` = undecided).
    /// macOS has no long-press gate, so the reorder gesture and the horizontal
    /// swipe (`SwipeableRow`) both see a bare `DragGesture`; committing to an
    /// axis keeps them mutually exclusive — only `.vertical` drives a reorder.
    /// Decision logic lives in `DragAxisArbiter` (unit-tested).
    @State private var committedAxis: DragAxisArbiter.Axis?
    #endif

    func body(content: Content) -> some View {
        // iOS attaches via the `UIGestureRecognizerRepresentable` overload of
        // `.gesture(_:)` (the representable is not itself a `Gesture`, so it
        // can't flow through the shared `some Gesture` property).
        #if os(iOS)
        content
            .gesture(reorderGesture)
        #else
        content
            .gesture(platformGesture)
        #endif
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
    private var reorderGesture: ReorderLongPressGesture {
        ReorderLongPressGesture(
            onBegan: {
                if case .idle = controller.state {
                    guard let frame = controller.geometry[id] else { return }
                    // Anchor on the row's natural midY — a reliable value
                    // in the named coordinate space; the recognizer's
                    // window-space translation is applied on top of it.
                    controller.beginDrag(
                        rowID: id,
                        originalHeight: frame.height,
                        cursorY: frame.midY
                    )
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            },
            onChanged: { translation in
                // Only a drag that actually began drives the controller;
                // resolving against an idle/settling session would spam
                // selection haptics with no-op target updates.
                guard case .dragging = controller.state else { return }
                let cursorY = currentCursorY(translation: translation.height)
                controller.updateCursor(translation: translation.height)
                // Horizontal translation picks the drop depth (indent/outdent).
                let resolved = controller.resolveTarget(
                    forDraggedID: id,
                    atY: cursorY,
                    horizontalTranslation: translation.width
                )
                let previous = currentTarget()
                if resolved != previous {
                    controller.setResolvedTarget(resolved)
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            },
            onEnded: {
                controller.endDrag(settleDuration: settleDuration)
            }
        )
    }
    #else
    private var platformGesture: some Gesture {
        DragGesture(
            minimumDistance: 4,
            coordinateSpace: .named(DragCoordinateSpace.name)
        )
        .onChanged { drag in
            // Axis arbitration with the horizontal swipe gesture
            // (`SwipeableRow`): commit to an axis on first real movement and
            // only let *vertical* drags drive a reorder. A horizontal drag is
            // yielded to the swipe, which owns the reveal of the row actions.
            if committedAxis == nil {
                committedAxis = DragAxisArbiter.axis(
                    forTranslation: drag.translation,
                    commitDistance: LillistDragTokens.macReorderAxisCommitDistance
                )
                guard committedAxis != nil else { return }
            }
            guard committedAxis == .vertical else { return }   // horizontal → swipe owns it

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
            // Axis is already committed to vertical here, so the horizontal
            // component is free to pick the drop depth (indent/outdent).
            let resolved = controller.resolveTarget(
                forDraggedID: id,
                atY: cursorY,
                horizontalTranslation: drag.translation.width
            )
            if resolved != currentTarget() {
                controller.setResolvedTarget(resolved)
            }
        }
        .onEnded { _ in
            // Only settle a reorder we actually began (a vertical drag);
            // a yielded horizontal drag never touched the controller.
            let didReorder = committedAxis == .vertical
            committedAxis = nil
            if didReorder {
                controller.endDrag(settleDuration: settleDuration)
            }
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
