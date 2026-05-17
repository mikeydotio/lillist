import SwiftUI

/// WCAG 2.x contrast helpers used by `TagTint` and snapshot tests.
public enum ContrastMath {
    /// Relative luminance for sRGB channels in [0,1]. 4.5:1 ratio is the
    /// AA threshold for body text.
    public static func relativeLuminance(red r: Double, green g: Double, blue b: Double) -> Double {
        func channel(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    public static func wcagRatio(_ l1: Double, _ l2: Double) -> Double {
        let lighter = max(l1, l2), darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// HSB → RGB; inverse of `TagTint.rgbToHSB`.
    public static func hsbToRGB(hue: Double, saturation: Double, brightness: Double) -> (Double, Double, Double) {
        if saturation == 0 { return (brightness, brightness, brightness) }
        let h = hue * 6
        let i = floor(h)
        let f = h - i
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * f)
        let t = brightness * (1 - saturation * (1 - f))
        switch Int(i) % 6 {
        case 0: return (brightness, t, p)
        case 1: return (q, brightness, p)
        case 2: return (p, brightness, t)
        case 3: return (p, q, brightness)
        case 4: return (t, p, brightness)
        case 5: return (brightness, p, q)
        default: return (brightness, brightness, brightness)
        }
    }
}
