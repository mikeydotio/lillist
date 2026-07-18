import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Raw Rainbow Logic color values and the dynamic-color factory.
///
/// This is the *data* layer of the design system
/// (`docs/plans/2026-06-12-rainbow-logic-design-system.md`): hex
/// constants for both schemes plus the machinery that turns a
/// (light, dark) pair into a trait-resolving SwiftUI `Color`.
/// Components never touch this directly — they consume the semantic
/// API in `LillistColor` and the functional hues below.
///
/// Colors are code-defined rather than asset-catalog entries so that
/// `RainbowPaletteTests` can resolve and pin every value per scheme,
/// and so one Swift source serves both apps and both extensions
/// without per-target catalog duplication.
public enum RainbowPalette {

    // MARK: Dynamic factory

    /// A scheme-resolving color built from raw hex values. `light` and
    /// `dark` are `0xRRGGBB`; alphas default to opaque. The resolved
    /// platform color switches with the system appearance.
    public static func dynamic(
        light: UInt32, dark: UInt32,
        lightAlpha: Double = 1, darkAlpha: Double = 1
    ) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
        #elseif canImport(AppKit)
        return Color(nsColor: dynamicNSColor(
            light: light, dark: dark, lightAlpha: lightAlpha, darkAlpha: darkAlpha
        ))
        #endif
    }

    #if canImport(AppKit)
    /// The AppKit primitive behind `dynamic(...)`: a name-based dynamic
    /// `NSColor` that re-resolves against `NSAppearance.current` at draw time.
    ///
    /// AppKit-backed views that can't take a SwiftUI `Color` — e.g. the macOS
    /// notes `NSTextView` (`MacNotesTextView`) — need a real `NSColor` for
    /// `textColor`/`insertionPointColor`/drawn placeholders. Routing through
    /// `NSColor(someSwiftUIColor)` would collapse the (light, dark) pair to a
    /// static snapshot of the *current* appearance, so those views would stop
    /// tracking light/dark. This keeps the dynamic behaviour intact.
    static func dynamicNSColor(
        light: UInt32, dark: UInt32,
        lightAlpha: Double = 1, darkAlpha: Double = 1
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(hex: dark, alpha: darkAlpha)
                : NSColor(hex: light, alpha: lightAlpha)
        }
    }
    #endif

    // MARK: Rainbow spectrum (scheme-invariant)

    /// The six spectrum stops from the app icon, top→bottom. The full
    /// gradient is reserved for headers, heroes, and success moments —
    /// see `RainbowGradient`.
    public enum Spectrum {
        public static let purple = solid(0x8B45E8)
        public static let blue   = solid(0x2E90FA)
        public static let cyan   = solid(0x1FC3E0)
        public static let green  = solid(0x34C25A)
        public static let lime   = solid(0xB6D63A)
        public static let orange = solid(0xFF7A1A)

        /// Ordered stops for gradient construction and confetti.
        public static let stops: [Color] = [purple, blue, cyan, green, lime, orange]

        /// Scheme-invariant opaque sRGB color from `0xRRGGBB`.
        private static func solid(_ hex: UInt32) -> Color {
            Color(
                red:   Double((hex >> 16) & 0xFF) / 255,
                green: Double((hex >>  8) & 0xFF) / 255,
                blue:  Double( hex        & 0xFF) / 255
            )
        }
    }

    // MARK: Functional hues

    /// One functional hue: `base` for object fills, `soft` for tint
    /// surfaces, `ink` for text/glyphs on soft or card, `deep` for
    /// pressed/error emphasis. **`base` is never used as a text
    /// color** — that's what `ink` is for; `RainbowContrastTests`
    /// enforces ≥ 4.5:1 for every (ink, soft) and (ink, card) pair in
    /// both schemes.
    public struct Functional: Sendable {
        public let base: Color
        public let soft: Color
        public let ink: Color
        public let deep: Color

        public init(base: Color, soft: Color, ink: Color, deep: Color) {
            self.base = base
            self.soft = soft
            self.ink = ink
            self.deep = deep
        }
    }

    /// Urgent / immediate / blocked / error. Light ink darkened from
    /// the exported `#C2530A` to clear WCAG AA on its soft surface.
    public static let actionOrange = Functional(
        base: dynamic(light: 0xFF7A1A, dark: 0xFF8A3B),
        soft: dynamic(light: 0xFFEAD7, dark: 0x42312B),
        ink:  dynamic(light: 0xB34C09, dark: 0xFFB068),
        deep: dynamic(light: 0xE5650C, dark: 0xE5650C)
    )

    /// Routine / recurring / done. Light ink darkened from the
    /// exported `#1B8540` to clear WCAG AA on its soft surface.
    public static let growthGreen = Functional(
        base: dynamic(light: 0x2FB457, dark: 0x46C26A),
        soft: dynamic(light: 0xD9F3E0, dark: 0x253A32),
        ink:  dynamic(light: 0x197B3B, dark: 0x79DDA0),
        deep: dynamic(light: 0x25A04C, dark: 0x25A04C)
    )

    /// Work / focus / in-progress. Light ink darkened from the
    /// exported `#1568CC` to clear WCAG AA on its soft surface.
    public static let focusBlue = Functional(
        base: dynamic(light: 0x2E90FA, dark: 0x4D9FFB),
        soft: dynamic(light: 0xDBEAFE, dark: 0x263549),
        ink:  dynamic(light: 0x1467CA, dark: 0x7FB6FF),
        deep: dynamic(light: 0x1E7FE6, dark: 0x1E7FE6)
    )

    /// System / brand / signature accents.
    public static let scriptPurple = Functional(
        base: dynamic(light: 0x8B45E8, dark: 0x9D63EE),
        soft: dynamic(light: 0xEADBFB, dark: 0x352C4B),
        ink:  dynamic(light: 0x6A28C0, dark: 0xC09BF5),
        deep: dynamic(light: 0x7A35DA, dark: 0x7A35DA)
    )

    /// Stale / paused warnings. A Lillist extension to the exported
    /// system (which has no yellow); follows the same grammar and the
    /// same contrast gates.
    public static let cautionAmber = Functional(
        base: dynamic(light: 0xF2A60D, dark: 0xF5B53A),
        soft: dynamic(light: 0xFCF0D4, dark: 0x41382A),
        ink:  dynamic(light: 0x8F6500, dark: 0xFFD37A),
        deep: dynamic(light: 0xD98F06, dark: 0xD98F06)
    )
}

// MARK: - Platform hex initializers

#if canImport(UIKit)
extension UIColor {
    /// Opaque-by-default sRGB color from `0xRRGGBB`.
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red:   CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >>  8) & 0xFF) / 255,
            blue:  CGFloat( hex        & 0xFF) / 255,
            alpha: alpha
        )
    }
}
#elseif canImport(AppKit)
extension NSColor {
    /// Opaque-by-default sRGB color from `0xRRGGBB`.
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green:   CGFloat((hex >>  8) & 0xFF) / 255,
            blue:    CGFloat( hex        & 0xFF) / 255,
            alpha:   alpha
        )
    }
}
#endif
