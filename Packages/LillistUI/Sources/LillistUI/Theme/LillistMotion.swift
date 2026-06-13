import SwiftUI

/// Rainbow Logic motion tokens. `squish` is the brand's overshoot
/// curve (`cubic-bezier(.34, 1.56, .64, 1)` — the y > 1 control point
/// is what produces the bounce); `easeOut` is the standard
/// deceleration for hovers and fades.
///
/// Route every *decorative* animation through the existing
/// `accessibleAnimation(_:value:)` modifier so Reduce Motion disables
/// it. Functional motion (drag lift/settle) keeps its own timing in
/// `LillistDragTokens`.
public enum LillistMotion {
    /// Press feedback, micro-interactions.
    public static let fast: TimeInterval = 0.12
    /// Default transitions: hover lift, fills, check snap-in.
    public static let base: TimeInterval = 0.20
    /// Larger reveals: sheets-adjacent flourishes, progress sweeps.
    public static let slow: TimeInterval = 0.36

    /// The signature squish-with-overshoot curve.
    public static func squish(_ duration: TimeInterval = base) -> Animation {
        .timingCurve(0.34, 1.56, 0.64, 1.0, duration: duration)
    }

    /// Standard decelerating ease-out.
    public static func easeOut(_ duration: TimeInterval = base) -> Animation {
        .timingCurve(0.22, 0.61, 0.36, 1.0, duration: duration)
    }
}
