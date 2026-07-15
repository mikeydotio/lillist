#if os(iOS)
import SwiftUI
import UIKit

/// UIKit-bridged pan recognizer that drives `SwipeableRow`'s horizontal
/// action reveal on iOS, replacing the SwiftUI
/// `DragGesture(minimumDistance: 10)` that starved the `List`'s scroll
/// pan (issue #12): a SwiftUI drag-family gesture on `List` row content
/// claims the touch stream even when its handler yields vertical
/// motion, so the scroll never begins. Bridging to
/// `UIPanGestureRecognizer` moves arbitration into UIKit:
///
/// - `gestureRecognizerShouldBegin` **declines** any touch that is not
///   predominantly horizontal (|dx| > |dy|; velocity tiebreak when the
///   translation is still ≈ 0), leaving vertical touches for the
///   scroll pan to claim.
/// - Once begun, the pan owns the touch exclusively
///   (`shouldRecognizeSimultaneouslyWith → false`).
/// - `isEnabled = false` hard-disables the recognizer (an in-flight pan
///   is cancelled); `SwipeableRow` mirrors `!isReorderActive` here so a
///   reorder drag can never trip a swipe action.
struct HorizontalSwipePanGesture: UIGestureRecognizerRepresentable {
    /// Mirrored onto the recognizer on every update; disabling cancels
    /// an in-flight pan (`onEnded` then fires with the raw translation).
    var isEnabled: Bool
    /// Fired at `.began`, before the first `onChanged`. The horizontal
    /// commitment already happened in `gestureRecognizerShouldBegin`.
    var onBegan: @MainActor () -> Void
    /// Fired at `.began` and every `.changed` with the accumulated
    /// horizontal translation in points (touch-down origin, so the
    /// first value already includes the begin-hysteresis travel —
    /// matching the replaced `DragGesture.translation` semantics).
    var onChanged: @MainActor (CGFloat) -> Void
    /// Fired at `.ended` with the **predicted** end translation
    /// (`SwipePanProjection` over translation + velocity), and at
    /// `.cancelled` with the raw translation (a cancelled pan carries
    /// no fling intent, so no projection).
    var onEnded: @MainActor (CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        recognizer.isEnabled = isEnabled
        return recognizer
    }

    func updateUIGestureRecognizer(
        _ recognizer: UIPanGestureRecognizer,
        context: Context
    ) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: UIPanGestureRecognizer,
        context: Context
    ) {
        switch recognizer.state {
        case .began:
            onBegan()
            onChanged(recognizer.translation(in: recognizer.view).x)
        case .changed:
            onChanged(recognizer.translation(in: recognizer.view).x)
        case .ended:
            onEnded(SwipePanProjection.predictedTranslation(
                translation: recognizer.translation(in: recognizer.view).x,
                velocityPerSecond: recognizer.velocity(in: recognizer.view).x
            ))
        case .cancelled:
            onEnded(recognizer.translation(in: recognizer.view).x)
        default:
            break
        }
    }

    /// Delegate encoding the arbitration contract: begin only for
    /// predominantly horizontal touches, never recognize alongside
    /// another recognizer.
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Below this much accumulated movement (points) the translation
        /// direction is noise; fall back to the velocity direction.
        private static let translationNoiseFloor: CGFloat = 1

        func gestureRecognizerShouldBegin(
            _ gestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else {
                return true
            }
            let translation = pan.translation(in: pan.view)
            guard max(abs(translation.x), abs(translation.y)) >= Self.translationNoiseFloor
            else {
                let velocity = pan.velocity(in: pan.view)
                return abs(velocity.x) > abs(velocity.y)
            }
            // Ties go to the scroll: only a strictly-horizontal majority
            // claims the touch.
            return abs(translation.x) > abs(translation.y)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }
    }
}
#endif
