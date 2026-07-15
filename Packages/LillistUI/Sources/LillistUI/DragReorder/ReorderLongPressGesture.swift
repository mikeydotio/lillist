#if os(iOS)
import SwiftUI
import UIKit

/// UIKit-bridged long-press recognizer that drives row drag-reorder on
/// iOS, replacing the SwiftUI `LongPressGesture.sequenced(before:
/// DragGesture)` composition that starved the `List`'s scroll pan
/// (issue #12): a SwiftUI drag-family gesture on `List` row content
/// claims the touch stream even while failing or yielding, so the
/// scroll never begins. Bridging to `UILongPressGestureRecognizer`
/// moves arbitration into UIKit, the only layer with a documented
/// contract:
///
/// - Movement past `allowableMovement` before `minimumPressDuration`
///   elapses fails the long-press, and the scroll pan takes the touch —
///   vertical drags scroll the list.
/// - Once the long-press begins, it owns the touch exclusively
///   (`shouldRecognizeSimultaneouslyWith → false`), and the scroll pan
///   cannot start — the drag drives the reorder.
///
/// Translation is anchored in **window space**, captured at `.began`.
/// Window-space deltas equal named-coordinate-space deltas only while
/// the row's container does not move mid-drag — an invariant that holds
/// because the recognizer blocks scrolling for the drag's lifetime and
/// no edge auto-scroll exists. If auto-scroll is ever built, this
/// anchor must move to a scroll-tracking conversion.
struct ReorderLongPressGesture: UIGestureRecognizerRepresentable {
    /// Fired once when the press matures (`.began`) — the "lift".
    var onBegan: @MainActor () -> Void
    /// Fired on every `.changed` event with the finger's translation
    /// (window space) since `.began`.
    var onChanged: @MainActor (CGSize) -> Void
    /// Fired when the touch lifts (`.ended`) or the system cancels the
    /// recognizer (`.cancelled`) — the drop, in both cases.
    var onEnded: @MainActor () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = LillistDragTokens.longPressDuration
        recognizer.allowableMovement = LillistDragTokens.longPressMaxDistance
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: UILongPressGestureRecognizer,
        context: Context
    ) {
        switch recognizer.state {
        case .began:
            context.coordinator.anchorInWindow = recognizer.location(in: nil)
            onBegan()
        case .changed:
            guard let anchor = context.coordinator.anchorInWindow else { return }
            let location = recognizer.location(in: nil)
            onChanged(CGSize(
                width: location.x - anchor.x,
                height: location.y - anchor.y
            ))
        case .ended, .cancelled:
            context.coordinator.anchorInWindow = nil
            onEnded()
        default:
            break
        }
    }

    /// Delegate encoding this side of the arbitration contract: never
    /// recognize alongside another recognizer, so a begun long-press
    /// blocks the scroll pan (and vice versa). Also stores the
    /// window-space anchor captured at `.began`.
    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Finger location in window coordinates at `.began`; `nil`
        /// outside an active press.
        var anchorInWindow: CGPoint?

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }
    }
}
#endif
