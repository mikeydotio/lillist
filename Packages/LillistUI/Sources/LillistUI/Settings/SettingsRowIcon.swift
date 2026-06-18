#if os(iOS)
import SwiftUI

/// A colored rounded-rect tile holding a white SF Symbol, used as the
/// leading icon of a Settings landing-screen row.
///
/// This is the iOS-Settings row-icon idiom (≈29×29 pt, continuous-radius
/// tile) adapted to Rainbow Logic: the `tint` is meant to be a single
/// `RainbowPalette` *functional* hue used consistently per Settings
/// category, so the color acts as a **wayfinding** signal rather than
/// decoration — satisfying the house rule "color is functional, never
/// decorative." Row text stays an ink/semantic color; only the tile is
/// hued. The glyph is `accessibilityHidden` because the row's text label
/// already carries the accessible name.
public struct SettingsRowIcon: View {
    private let systemImage: String
    private let tint: Color

    public init(systemImage: String, tint: Color) {
        self.systemImage = systemImage
        self.tint = tint
    }

    public var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(
                tint,
                in: RoundedRectangle(cornerRadius: LillistRadius.s, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}
#endif
