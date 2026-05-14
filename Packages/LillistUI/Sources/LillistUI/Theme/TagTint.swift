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

    public func resolved(in scheme: ColorScheme) -> Resolved {
        let (h, s, b) = Self.rgbToHSB(r: red, g: green, b: blue)
        if scheme == .dark {
            return Resolved(hue: h, saturation: s * 0.7, brightness: min(b * 1.05, 1.0), opacity: 1.0)
        }
        return Resolved(hue: h, saturation: s, brightness: b, opacity: 1.0)
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
