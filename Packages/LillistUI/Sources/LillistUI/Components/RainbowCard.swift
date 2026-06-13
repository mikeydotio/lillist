import SwiftUI

/// The shared tactile-card chrome for repeating content rows (task
/// rows, journal rows, popover rows): `card` surface, continuous
/// 12 pt corners, hairline border, soft shadow, and an optional
/// status-colored accent stripe down the leading edge.
///
/// Done rows fade to 0.62 opacity and drop their shadow — completed
/// work settles into the workspace instead of floating above it.
///
/// Elevation defaults to `.xs` and should stay there for anything
/// rendered inside a `List`/`ForEach` (the design system's hard perf
/// rule); pass a higher level only for one-off surfaces.
public struct RainbowCardModifier: ViewModifier {
    var accent: Color?
    var isDone: Bool
    var elevation: LillistElevation

    @Environment(\.accessibilityShouldIncreaseContrast) private var systemIncreaseContrast
    @Environment(\.increaseContrastOverride) private var overrideIncreaseContrast

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: LillistRadius.m, style: .continuous)
    }

    public func body(content: Content) -> some View {
        let increaseContrast = overrideIncreaseContrast ?? systemIncreaseContrast
        let chrome = content
            .background(shape.fill(LillistColor.card))
            .overlay(shape.strokeBorder(
                increaseContrast ? LillistColor.borderStrong : LillistColor.borderHair,
                lineWidth: 1
            ))
            .overlay(alignment: .leading) {
                if let accent {
                    Capsule()
                        .fill(accent)
                        .frame(width: 3)
                        .padding(.vertical, 8)
                        .padding(.leading, 4)
                        .opacity(0.9)
                        .allowsHitTesting(false)
                }
            }

        if isDone {
            chrome.opacity(0.62)
        } else {
            chrome.rainbowShadow(elevation)
        }
    }
}

extension View {
    /// Apply the Rainbow Logic card chrome. See `RainbowCardModifier`.
    public func rainbowCard(
        accent: Color? = nil,
        isDone: Bool = false,
        elevation: LillistElevation = .xs
    ) -> some View {
        modifier(RainbowCardModifier(accent: accent, isDone: isDone, elevation: elevation))
    }
}
