import SwiftUI
import AppKit

/// Plan 10 fallback (macOS): `LillistUI` exposes `TagTint(hex:)` but no
/// direct `Color(hex:)` or `Color.toHex()`. Settings panes use these
/// helpers to round-trip the user-chosen default tag tint through the
/// `defaultTagTintHex` preference string.
extension Color {
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
    /// Goes through `NSColor` to extract components, since `Color`
    /// doesn't expose its underlying RGB directly. Returns nil if the
    /// color can't be converted to the sRGB color space (unlikely for
    /// user-pickable colors but technically possible for system colors).
    func toHex() -> String? {
        let ns = NSColor(self).usingColorSpace(.sRGB)
        guard let ns else { return nil }
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
