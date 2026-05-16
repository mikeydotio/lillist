import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Cross-platform hex round-trip for SwiftUI `Color`. Used by
/// Preferences UI to round-trip the `defaultTagTintHex` preference
/// string.
///
/// **Distinct from `TagTint.init?(hex:)`** (`Packages/LillistUI/Sources/
/// LillistUI/Theme/TagTint.swift:19-30`), which constructs a `TagTint`
/// value with dark-mode desaturation logic for tag chips. `Color(hex:)`
/// here produces a raw SwiftUI `Color` for use anywhere a `Color` is
/// expected (notably `ColorPicker` bindings in Preferences). Both forms
/// are needed; do not collapse them.
public extension Color {
    /// Parse a 6-digit hex RGB string into a `Color`. Accepts an
    /// optional leading `#`. Three-digit shorthand (`#FA0`) is expanded.
    /// Returns nil if the string can't be parsed.
    init?(hex: String?) {
        guard let hex else { return nil }
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 {
            s = s.map { "\($0)\($0)" }.joined()
        }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self = Color(
            red:   Double((v >> 16) & 0xFF) / 255.0,
            green: Double((v >>  8) & 0xFF) / 255.0,
            blue:  Double( v        & 0xFF) / 255.0
        )
    }

    /// Render a `Color` as a 6-digit hex RGB string (with leading `#`).
    /// Returns nil if the color can't be reduced to sRGB components.
    func toHex() -> String? {
        #if canImport(AppKit)
        let ns = NSColor(self).usingColorSpace(.sRGB)
        guard let ns else { return nil }
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
        #elseif canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        let ri = Int((r * 255).rounded())
        let gi = Int((g * 255).rounded())
        let bi = Int((b * 255).rounded())
        return String(format: "#%02X%02X%02X", ri, gi, bi)
        #else
        return nil
        #endif
    }
}
