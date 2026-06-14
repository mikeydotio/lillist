import SwiftUI

/// Rainbow Logic elevation: soft two-layer drop shadows that make
/// raised surfaces read as physical, pressable objects, plus colored
/// glows for filled controls.
///
/// Levels and their layer values are specced in
/// `docs/plans/2026-06-12-rainbow-logic-design-system.md`. Two rules
/// from that spec are load-bearing:
///
/// 1. **Repeating list rows never exceed `.xs`.** Larger blur radii in
///    reused list cells are a scroll-performance hazard; cards
///    separate from the workspace by surface value, not shadow drama.
/// 2. Apply `compositingGroup()` (done inside the modifier) so the
///    shadow renders once for the composed card instead of once per
///    subview.
public enum LillistElevation: Sendable {
    /// List rows and chips (the hard cap for repeating cells).
    case xs
    /// Hover lift, active sidebar chip.
    case sm
    /// Standalone cards.
    case card
    /// Toasts and floating bars.
    case lift
    /// Drag phantom, modal surfaces.
    case pop

    /// (radius, y, opacity) for the two stacked shadow layers.
    var layers: ((CGFloat, CGFloat, Double), (CGFloat, CGFloat, Double)) {
        switch self {
        case .xs:   ((2, 1, 0.05), (1, 1, 0.04))
        case .sm:   ((3, 1, 0.06), (8, 4, 0.05))
        case .card: ((2, 1, 0.04), (16, 6, 0.07))
        case .lift: ((6, 2, 0.06), (32, 14, 0.13))
        case .pop:  ((18, 8, 0.10), (60, 24, 0.18))
        }
    }
}

extension View {
    /// Two-layer soft drop shadow at the given elevation. Shadow ink is
    /// charcoal (`#1B1C22`) in light mode and slightly quieter in dark
    /// mode, where surface-value separation does most of the work.
    public func rainbowShadow(_ level: LillistElevation) -> some View {
        let (a, b) = level.layers
        return compositingGroup()
            .shadow(color: shadowInk(a.2), radius: a.0, y: a.1)
            .shadow(color: shadowInk(b.2), radius: b.0, y: b.1)
    }

}

/// Shadow ink at the given light-scheme opacity; dark scheme renders
/// at 90% of it.
private func shadowInk(_ opacity: Double) -> Color {
    RainbowPalette.dynamic(
        light: 0x1B1C22, dark: 0x000000,
        lightAlpha: opacity, darkAlpha: opacity * 0.9
    )
}

extension ShapeStyle where Self == AnyShapeStyle {
    /// Inset-well fill for sunken fields (search bars, text inputs):
    /// `LillistColor.sunken` with the spec's two inner shadows. Use as
    /// the `fill` of the well's shape.
    public static var rainbowWell: AnyShapeStyle {
        AnyShapeStyle(
            LillistColor.sunken
                .shadow(.inner(color: .black.opacity(0.09), radius: 2, y: 1))
                .shadow(.inner(color: .black.opacity(0.05), radius: 0.5, y: 0.5))
        )
    }
}

