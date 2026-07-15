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
/// - Once the long-press begins, the scroll pan cannot also act on the
///   touch: neither recognizer opts into simultaneous recognition (the
///   coordinator declines it from this side; see the delegate note),
///   so UIKit's default mutual exclusivity applies and the drag drives
///   the reorder.
///
/// Cancellation is distinct from release: `.ended` (finger lifts) is
/// the drop, while `.cancelled` (incoming call, app switch, system
/// edge gesture) must abort the drag without committing anything —
/// hence the separate `onEnded` / `onCancelled` callbacks.
///
/// Translation is anchored in **window space**, captured at `.began`,
/// and tracked from the recognizer's **first touch** (not the multi-
/// touch centroid, which would jump if a second finger lands mid-drag).
/// Window-space deltas equal named-coordinate-space deltas only while
/// the row's container does not move mid-drag — an invariant that holds
/// because the recognizer blocks scrolling for the drag's lifetime and
/// no edge auto-scroll exists (issue #19). If auto-scroll is ever
/// built, this anchor must move to a scroll-tracking conversion.
struct ReorderLongPressGesture: UIGestureRecognizerRepresentable {
    /// Fired once when the press matures (`.began`) — the "lift".
    var onBegan: @MainActor () -> Void
    /// Fired on every `.changed` event with the finger's translation
    /// (window space) since `.began`.
    var onChanged: @MainActor (CGSize) -> Void
    /// Fired when the touch lifts deliberately (`.ended`) — the drop.
    var onEnded: @MainActor () -> Void
    /// Fired when the system cancels the recognizer (`.cancelled`) —
    /// the drag must be aborted, never committed.
    var onCancelled: @MainActor () -> Void

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
            context.coordinator.anchorInWindow = Self.trackedLocation(of: recognizer)
            onBegan()
        case .changed:
            guard let anchor = context.coordinator.anchorInWindow else { return }
            let location = Self.trackedLocation(of: recognizer)
            onChanged(CGSize(
                width: location.x - anchor.x,
                height: location.y - anchor.y
            ))
        case .ended:
            context.coordinator.anchorInWindow = nil
            onEnded()
        case .cancelled, .failed:
            context.coordinator.anchorInWindow = nil
            onCancelled()
        default:
            break
        }
    }

    /// The window-space location of the recognizer's first touch. The
    /// plain `location(in:)` is the centroid of *all* tracked touches,
    /// which lurches if a second finger lands mid-drag; pinning to
    /// touch 0 keeps the translation continuous.
    private static func trackedLocation(
        of recognizer: UILongPressGestureRecognizer
    ) -> CGPoint {
        recognizer.numberOfTouches > 0
            ? recognizer.location(ofTouch: 0, in: nil)
            : recognizer.location(in: nil)
    }

    /// Delegate for the arbitration contract. Declining simultaneous
    /// recognition here matches UIKit's default and — because the
    /// List's scroll pan does not opt in either — the two recognizers
    /// stay mutually exclusive. Note the limit: `false` from this side
    /// does not *veto* simultaneity; a recognizer whose own delegate
    /// returns `true` could still recognize alongside. Also stores the
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
