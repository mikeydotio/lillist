import CoreGraphics

/// Pure deceleration projection for a released pan: where the content
/// would come to rest if it kept moving at the release velocity and
/// decayed at a scroll-view-style deceleration rate.
///
/// Extracted so the policy is unit-testable in isolation (the UIKit
/// gesture itself is not), mirroring `SwipeSettleArbiter`. The bridged
/// `HorizontalSwipePanGesture` feeds this into
/// `SwipeableRow.settle(predictedTranslation:)`, reproducing the fling
/// projection the SwiftUI `DragGesture.predictedEndTranslation` used to
/// supply.
enum SwipePanProjection {
    /// The standard deceleration projection
    /// (WWDC18 "Designing Fluid Interfaces"):
    ///
    ///     predicted = translation + (velocity / 1000) × rate / (1 − rate)
    ///
    /// - Parameters:
    ///   - translation: Accumulated translation at release, in points.
    ///   - velocityPerSecond: Release velocity in points **per second**
    ///     (UIKit's `velocity(in:)` unit); `/ 1000` converts to
    ///     points-per-millisecond, the unit the decay series is summed in.
    ///   - decelerationRate: Per-millisecond velocity retention. Defaults
    ///     to `0.998` (`UIScrollView.DecelerationRate.normal`).
    ///     **Precondition: `0 < decelerationRate < 1`** — at 1 the decay
    ///     series diverges (division by zero) and above 1 the projection's
    ///     sign inverts.
    /// - Returns: The projected end translation, in points.
    static func predictedTranslation(
        translation: CGFloat,
        velocityPerSecond: CGFloat,
        decelerationRate: CGFloat = 0.998
    ) -> CGFloat {
        precondition(
            decelerationRate > 0 && decelerationRate < 1,
            "decelerationRate must be in (0, 1); got \(decelerationRate)"
        )
        return translation + (velocityPerSecond / 1000) * decelerationRate / (1 - decelerationRate)
    }
}
