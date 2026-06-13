import SwiftUI

/// The signature rainbow gradients. **Reserved surfaces only**: the
/// full spectrum appears on headers, hero moments, success states
/// (migration progress, onboarding CTA), and the confetti burst —
/// never as ambient decoration. Everyday color comes from the
/// functional hues on `RainbowPalette`.
public enum RainbowGradient {
    /// Vertical spectrum, purple → orange — matches the app icon's
    /// braces. Use for icon-scale accents and masked empty-state art.
    public static let vertical = LinearGradient(
        colors: RainbowPalette.Spectrum.stops,
        startPoint: .top, endPoint: .bottom
    )

    /// Near-horizontal spectrum for headline text and header bars
    /// (the web system's 95° run).
    public static let horizontal = LinearGradient(
        stops: [
            .init(color: RainbowPalette.Spectrum.purple, location: 0.00),
            .init(color: RainbowPalette.Spectrum.blue,   location: 0.28),
            .init(color: RainbowPalette.Spectrum.cyan,   location: 0.46),
            .init(color: RainbowPalette.Spectrum.green,  location: 0.64),
            .init(color: RainbowPalette.Spectrum.lime,   location: 0.80),
            .init(color: RainbowPalette.Spectrum.orange, location: 1.00),
        ],
        startPoint: .leading, endPoint: .trailing
    )

    /// Conic halo for hover/drag-lift edges. Stroke it around a shape
    /// border; never persistent, never on static content.
    public static let halo = AngularGradient(
        colors: RainbowPalette.Spectrum.stops + [RainbowPalette.Spectrum.purple],
        center: .center,
        angle: .degrees(210)
    )
}
