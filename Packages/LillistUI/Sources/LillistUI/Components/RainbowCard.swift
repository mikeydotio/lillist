import SwiftUI

/// The shared card chrome for repeating content rows (task rows,
/// journal rows, popover rows): `card` surface, continuous 12 pt
/// corners, hairline border, and an optional status-colored accent
/// stripe down the leading edge.
///
/// Rainbow Glass treatment: content rows are **flat** (`.xs`), separated
/// from the workspace by surface value + the hairline border, not a drop
/// shadow — depth in the glass era comes from the floating control layer
/// above, not per-row shadows. Higher elevations (`.sm`+) keep their
/// shadow for genuinely-floating one-off surfaces (sheets, popovers,
/// the drag phantom).
///
/// Done rows fade to 0.62 opacity — completed work settles into the
/// workspace.
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
            switch elevation {
            case .xs:
                // Flat content: surface value + hairline border separate
                // the row from the workspace (Rainbow Glass content rule).
                chrome
            default:
                // Genuinely-floating one-off surfaces keep their shadow.
                chrome.rainbowShadow(elevation)
            }
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
