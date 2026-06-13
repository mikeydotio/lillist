import XCTest
import SwiftUI
@testable import LillistUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Pins every Rainbow Logic semantic color to its exact per-scheme hex
/// from `docs/plans/2026-06-12-rainbow-logic-design-system.md`. A
/// failing case here means the palette drifted from the design system —
/// change the doc deliberately or fix the regression.
final class RainbowPaletteTests: XCTestCase {

    // MARK: Semantic surfaces

    func testSurfaces() {
        assertHex(LillistColor.workspace, light: 0xEEF0F6, dark: 0x14151A)
        assertHex(LillistColor.card,      light: 0xFFFFFF, dark: 0x1F2128)
        assertHex(LillistColor.raised,    light: 0xFFFFFF, dark: 0x262833)
        assertHex(LillistColor.sunken,    light: 0xF2F3F8, dark: 0x191A20)
        assertHex(LillistColor.lavender,  light: 0xF1ECFB, dark: 0x2A2438)
    }

    func testText() {
        assertHex(LillistColor.textStrong, light: 0x1B1C22, dark: 0xF4F5F9)
        assertHex(LillistColor.textBody,   light: 0x3C3F49, dark: 0xC9CCD6)
        assertHex(LillistColor.textMuted,  light: 0x71757F, dark: 0x9A9EA9)
        assertHex(LillistColor.textFaint,  light: 0x969AA6, dark: 0x70747F)
    }

    func testBorders() {
        assertHex(LillistColor.borderSoft,   light: 0xDFE1E9, dark: 0x3A3D47)
        assertHex(LillistColor.borderHair,   light: 0xE9EBF1, dark: 0x2B2D36)
        assertHex(LillistColor.borderStrong, light: 0xC0C3CD, dark: 0x4A4E59)
    }

    // MARK: Functional hues

    func testActionOrange() {
        let hue = RainbowPalette.actionOrange
        assertHex(hue.base, light: 0xFF7A1A, dark: 0xFF8A3B)
        assertHex(hue.soft, light: 0xFFEAD7, dark: 0x42312B)
        assertHex(hue.ink,  light: 0xB34C09, dark: 0xFFB068)
        assertHex(hue.deep, light: 0xE5650C, dark: 0xE5650C)
    }

    func testGrowthGreen() {
        let hue = RainbowPalette.growthGreen
        assertHex(hue.base, light: 0x2FB457, dark: 0x46C26A)
        assertHex(hue.soft, light: 0xD9F3E0, dark: 0x253A32)
        assertHex(hue.ink,  light: 0x197B3B, dark: 0x79DDA0)
        assertHex(hue.deep, light: 0x25A04C, dark: 0x25A04C)
    }

    func testFocusBlue() {
        let hue = RainbowPalette.focusBlue
        assertHex(hue.base, light: 0x2E90FA, dark: 0x4D9FFB)
        assertHex(hue.soft, light: 0xDBEAFE, dark: 0x263549)
        assertHex(hue.ink,  light: 0x1467CA, dark: 0x7FB6FF)
        assertHex(hue.deep, light: 0x1E7FE6, dark: 0x1E7FE6)
    }

    func testScriptPurple() {
        let hue = RainbowPalette.scriptPurple
        assertHex(hue.base, light: 0x8B45E8, dark: 0x9D63EE)
        assertHex(hue.soft, light: 0xEADBFB, dark: 0x352C4B)
        assertHex(hue.ink,  light: 0x6A28C0, dark: 0xC09BF5)
        assertHex(hue.deep, light: 0x7A35DA, dark: 0x7A35DA)
    }

    func testCautionAmber() {
        let hue = RainbowPalette.cautionAmber
        assertHex(hue.base, light: 0xF2A60D, dark: 0xF5B53A)
        assertHex(hue.soft, light: 0xFCF0D4, dark: 0x41382A)
        assertHex(hue.ink,  light: 0x8F6500, dark: 0xFFD37A)
        assertHex(hue.deep, light: 0xD98F06, dark: 0xD98F06)
    }

    // MARK: Spectrum (scheme-invariant)

    func testSpectrumStops() {
        let expected: [UInt32] = [0x8B45E8, 0x2E90FA, 0x1FC3E0, 0x34C25A, 0xB6D63A, 0xFF7A1A]
        XCTAssertEqual(RainbowPalette.Spectrum.stops.count, expected.count)
        for (color, hex) in zip(RainbowPalette.Spectrum.stops, expected) {
            // Invariant across schemes:
            XCTAssertEqual(Self.resolve(color, dark: false), hex, "light \(String(hex, radix: 16))")
            XCTAssertEqual(Self.resolve(color, dark: true), hex, "dark \(String(hex, radix: 16))")
        }
    }

    // MARK: Resolution helpers

    private func assertHex(
        _ color: Color, light: UInt32, dark: UInt32,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(
            Self.resolve(color, dark: false), light,
            "light: expected #\(String(light, radix: 16).uppercased())",
            file: file, line: line
        )
        XCTAssertEqual(
            Self.resolve(color, dark: true), dark,
            "dark: expected #\(String(dark, radix: 16).uppercased())",
            file: file, line: line
        )
    }

    /// Resolve a SwiftUI `Color` to `0xRRGGBB` under the given scheme.
    static func resolve(_ color: Color, dark: Bool) -> UInt32 {
        let (r, g, b) = resolveComponents(color, dark: dark)
        func byte(_ v: CGFloat) -> UInt32 { UInt32((v * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }

    /// Resolve to raw sRGB components for contrast math.
    static func resolveComponents(_ color: Color, dark: Bool) -> (CGFloat, CGFloat, CGFloat) {
        #if canImport(UIKit)
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        let resolved = UIColor(color).resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, &g, &b, &a)
        return (r, g, b)
        #elseif canImport(AppKit)
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        var components: (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
        appearance.performAsCurrentDrawingAppearance {
            let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .black
            components = (resolved.redComponent, resolved.greenComponent, resolved.blueComponent)
        }
        return components
        #endif
    }
}
