import SwiftUI
import LillistCore

/// Rainbow Logic status palette: each status maps to a functional hue
/// whose *meaning* matches the state (see
/// `docs/plans/2026-06-12-rainbow-logic-design-system.md`).
///
/// | status  | hue                          |
/// |---------|------------------------------|
/// | todo    | neutral (`textFaint`)        |
/// | started | `focusBlue` (work/in-flight) |
/// | blocked | `actionOrange` (urgent)      |
/// | closed  | `growthGreen` (done)         |
///
/// Blocked moved red → action-orange with the Rainbow Logic adoption;
/// the Plan-17 contrast concern that originally bumped orange → red is
/// answered by the **ink axis**: text and glyphs use `ink(for:)`
/// (dark, AA-compliant), never the raw `base`. `StatusPaletteTests`
/// pins the mapping; `RainbowContrastTests` gates the ratios.
public enum StatusPalette {
    /// Object fill for the status: cube fill, accent stripe, pill dot.
    /// **Never use as a text color** — that's `ink(for:)`.
    public static func color(for status: Status) -> Color {
        switch status {
        case .todo:    return LillistColor.textFaint
        case .started: return RainbowPalette.focusBlue.base
        case .blocked: return RainbowPalette.actionOrange.base
        case .closed:  return RainbowPalette.growthGreen.base
        }
    }

    /// Text/glyph color for the status, legible on `soft` fills and on
    /// cards in both schemes.
    public static func ink(for status: Status) -> Color {
        switch status {
        case .todo:    return LillistColor.textMuted
        case .started: return RainbowPalette.focusBlue.ink
        case .blocked: return RainbowPalette.actionOrange.ink
        case .closed:  return RainbowPalette.growthGreen.ink
        }
    }

    /// Soft tint fill for backgrounds (capsules, badges, the blocked
    /// cube). Pass the increase-contrast flag from the environment
    /// (`accessibilityShouldIncreaseContrast` pattern) to lift the
    /// fill opacity.
    public static func fill(for status: Status, increaseContrast: Bool = false) -> some ShapeStyle {
        color(for: status).opacity(increaseContrast ? 0.30 : 0.16)
    }
}
