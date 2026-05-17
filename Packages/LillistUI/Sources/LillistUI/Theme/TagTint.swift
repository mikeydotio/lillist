import SwiftUI

/// A tag tint color, with dark-mode desaturation per design Section 7.
public struct TagTint: Sendable, Equatable {
    public struct Resolved: Sendable, Equatable {
        public var hue: Double
        public var saturation: Double
        public var brightness: Double
        public var opacity: Double
        public var color: Color {
            Color(hue: hue, saturation: saturation, brightness: brightness, opacity: opacity)
        }
    }

    public var red: Double
    public var green: Double
    public var blue: Double

    public init?(hex: String?) {
        guard let hex else { return nil }
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 {
            s = s.map { "\($0)\($0)" }.joined()
        }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.red   = Double((v >> 16) & 0xFF) / 255.0
        self.green = Double((v >>  8) & 0xFF) / 255.0
        self.blue  = Double( v        & 0xFF) / 255.0
    }

    /// Resolve to the actual color used on screen, applying:
    ///   1. Dark-mode desaturation (cosmetic, design Section 7).
    ///   2. A WCAG contrast floor against the chip background
    ///      (`base.opacity(0.18)` per `TagChipView`). Bumps brightness
    ///      until the foreground/background ratio clears 4.5:1.
    public func resolved(in scheme: ColorScheme) -> Resolved {
        let (h, s, b) = Self.rgbToHSB(r: red, g: green, b: blue)
        var resolvedSaturation = s
        var resolvedBrightness = b
        if scheme == .dark {
            resolvedSaturation = s * 0.7
            resolvedBrightness = min(b * 1.05, 1.0)
        }
        let floorBrightness = Self.clampBrightnessForContrastFloor(
            hue: h,
            saturation: resolvedSaturation,
            brightness: resolvedBrightness,
            scheme: scheme
        )
        return Resolved(hue: h, saturation: resolvedSaturation, brightness: floorBrightness, opacity: 1.0)
    }

    /// Iterate brightness upward (light backgrounds: downward) until the
    /// foreground/background WCAG ratio clears 4.5:1, or we hit the bound.
    private static func clampBrightnessForContrastFloor(
        hue: Double,
        saturation: Double,
        brightness initial: Double,
        scheme: ColorScheme
    ) -> Double {
        // Approximate background: in dark mode, near-black; in light mode, near-white.
        let bgLum: Double = scheme == .dark ? 0.05 : 0.95
        let direction: Double = scheme == .dark ? 0.05 : -0.05
        var brightness = initial
        for _ in 0..<10 {
            let (r, g, b) = ContrastMath.hsbToRGB(hue: hue, saturation: saturation, brightness: brightness)
            let fgLum = ContrastMath.relativeLuminance(red: r, green: g, blue: b)
            if ContrastMath.wcagRatio(fgLum, bgLum) >= 4.5 {
                return brightness
            }
            brightness = max(0.0, min(1.0, brightness + direction))
        }
        return brightness
    }

    private static func rgbToHSB(r: Double, g: Double, b: Double) -> (Double, Double, Double) {
        let maxC = max(r, g, b), minC = min(r, g, b)
        let d = maxC - minC
        let brightness = maxC
        let saturation = maxC == 0 ? 0 : d / maxC
        var hue: Double = 0
        if d != 0 {
            if maxC == r { hue = (g - b) / d + (g < b ? 6 : 0) }
            else if maxC == g { hue = (b - r) / d + 2 }
            else { hue = (r - g) / d + 4 }
            hue /= 6
        }
        return (hue, saturation, brightness)
    }
}
