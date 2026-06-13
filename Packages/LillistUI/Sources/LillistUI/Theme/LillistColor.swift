import SwiftUI

/// Semantic surface, text, and border colors — the only color API
/// components should reach for (alongside the functional hues on
/// `RainbowPalette` and the status/sync/tag palettes).
///
/// Values are the Rainbow Logic tables from
/// `docs/plans/2026-06-12-rainbow-logic-design-system.md`; dark-scheme
/// values are the derived extension documented there. Every value is
/// pinned per scheme by `RainbowPaletteTests`.
public enum LillistColor {

    // MARK: Surfaces

    /// Screen/list background — the soft cool-gray workspace.
    public static let workspace = RainbowPalette.dynamic(light: 0xEEF0F6, dark: 0x14151A)
    /// Task cards, form rows, sheets-on-workspace.
    public static let card = RainbowPalette.dynamic(light: 0xFFFFFF, dark: 0x1F2128)
    /// Popovers and the drag phantom — one step above `card`.
    public static let raised = RainbowPalette.dynamic(light: 0xFFFFFF, dark: 0x262833)
    /// Inset wells: search bars, text fields.
    public static let sunken = RainbowPalette.dynamic(light: 0xF2F3F8, dark: 0x191A20)
    /// The signature lavender used by hero/add-task surfaces.
    public static let lavender = RainbowPalette.dynamic(light: 0xF1ECFB, dark: 0x2A2438)

    // MARK: Text

    /// Titles and emphasized content.
    public static let textStrong = RainbowPalette.dynamic(light: 0x1B1C22, dark: 0xF4F5F9)
    /// Default body text.
    public static let textBody = RainbowPalette.dynamic(light: 0x3C3F49, dark: 0xC9CCD6)
    /// Secondary/meta text (due dates, counts, captions).
    public static let textMuted = RainbowPalette.dynamic(light: 0x71757F, dark: 0x9A9EA9)
    /// Tertiary text, placeholders, and the todo-status neutral.
    public static let textFaint = RainbowPalette.dynamic(light: 0x969AA6, dark: 0x70747F)

    // MARK: Borders

    /// Standard control borders.
    public static let borderSoft = RainbowPalette.dynamic(light: 0xDFE1E9, dark: 0x3A3D47)
    /// Card hairlines.
    public static let borderHair = RainbowPalette.dynamic(light: 0xE9EBF1, dark: 0x2B2D36)
    /// Borders under Increase Contrast.
    public static let borderStrong = RainbowPalette.dynamic(light: 0xC0C3CD, dark: 0x4A4E59)
}
