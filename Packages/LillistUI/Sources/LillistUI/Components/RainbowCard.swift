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
/// How a `rainbowCard`'s border is drawn. `hairline` is the resting state; the
/// other two are transient drag-reorder cues (see `DragOverlay`):
/// - `rainbow` — the lifted drag ghost's own border, recolored with the
///   conic halo gradient (replaces the separate overlay border that used to
///   float around the phantom).
/// - `dropTargetParent` — a gentle focus-blue border on the cell the dragged
///   row will nest under, shown for the drag's duration.
public enum CardBorderTreatment: Equatable, Sendable {
    case hairline
    case rainbow
    case dropTargetParent
}

public struct RainbowCardModifier: ViewModifier {
    var accent: Color?
    var isDone: Bool
    var elevation: LillistElevation
    var border: CardBorderTreatment

    @Environment(\.accessibilityShouldIncreaseContrast) private var systemIncreaseContrast
    @Environment(\.increaseContrastOverride) private var overrideIncreaseContrast

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: LillistRadius.m, style: .continuous)
    }

    public func body(content: Content) -> some View {
        let increaseContrast = overrideIncreaseContrast ?? systemIncreaseContrast
        let chrome = content
            .background(shape.fill(LillistColor.card))
            .overlay(borderOverlay(increaseContrast: increaseContrast))
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

    @ViewBuilder
    private func borderOverlay(increaseContrast: Bool) -> some View {
        switch border {
        case .hairline:
            shape.strokeBorder(
                increaseContrast ? LillistColor.borderStrong : LillistColor.borderHair,
                lineWidth: 1
            )
        case .rainbow:
            shape.strokeBorder(RainbowGradient.halo, lineWidth: 1.5)
        case .dropTargetParent:
            shape.strokeBorder(
                LillistDragTokens.indicatorColor.opacity(0.7),
                lineWidth: 2
            )
        }
    }
}

extension View {
    /// Apply the Rainbow Logic card chrome. See `RainbowCardModifier`.
    public func rainbowCard(
        accent: Color? = nil,
        isDone: Bool = false,
        elevation: LillistElevation = .xs,
        border: CardBorderTreatment = .hairline
    ) -> some View {
        modifier(RainbowCardModifier(
            accent: accent, isDone: isDone, elevation: elevation, border: border
        ))
    }
}
