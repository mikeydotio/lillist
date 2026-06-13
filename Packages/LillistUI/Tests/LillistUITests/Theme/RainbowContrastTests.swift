import XCTest
import SwiftUI
@testable import LillistUI
import LillistCore

/// WCAG AA sweep for the Rainbow Logic palette. The design system's
/// hard rule — "`base` is never text; text on soft/card uses `ink`" —
/// only holds if every (ink, soft) and (ink, card) pair clears 4.5:1
/// in both schemes. This test is the authority that gated the
/// ink-darkening deviations recorded in `RainbowPalette`.
final class RainbowContrastTests: XCTestCase {

    private static let hues: [(name: String, hue: RainbowPalette.Functional)] = [
        ("actionOrange", RainbowPalette.actionOrange),
        ("growthGreen",  RainbowPalette.growthGreen),
        ("focusBlue",    RainbowPalette.focusBlue),
        ("scriptPurple", RainbowPalette.scriptPurple),
        ("cautionAmber", RainbowPalette.cautionAmber),
    ]

    func testInkOnSoftMeetsAA() {
        for (name, hue) in Self.hues {
            for dark in [false, true] {
                let ratio = Self.ratio(hue.ink, on: hue.soft, dark: dark)
                XCTAssertGreaterThanOrEqual(
                    ratio, 4.5,
                    "\(name).ink on .soft (\(dark ? "dark" : "light")) = \(String(format: "%.2f", ratio))"
                )
            }
        }
    }

    func testInkOnCardMeetsAA() {
        for (name, hue) in Self.hues {
            for dark in [false, true] {
                let ratio = Self.ratio(hue.ink, on: LillistColor.card, dark: dark)
                XCTAssertGreaterThanOrEqual(
                    ratio, 4.5,
                    "\(name).ink on card (\(dark ? "dark" : "light")) = \(String(format: "%.2f", ratio))"
                )
            }
        }
    }

    /// Status inks are what task rows render as text/glyph accents on
    /// cards (e.g. the overdue due-date); they must read on `card` in
    /// both schemes.
    func testStatusInkOnCardMeetsAA() {
        for status in Status.allCases {
            for dark in [false, true] {
                let ratio = Self.ratio(StatusPalette.ink(for: status), on: LillistColor.card, dark: dark)
                XCTAssertGreaterThanOrEqual(
                    ratio, 4.5,
                    "ink(\(status)) on card (\(dark ? "dark" : "light")) = \(String(format: "%.2f", ratio))"
                )
            }
        }
    }

    /// Body text must read on every standard surface.
    func testBodyTextOnSurfacesMeetsAA() {
        let surfaces: [(String, Color)] = [
            ("workspace", LillistColor.workspace),
            ("card", LillistColor.card),
            ("sunken", LillistColor.sunken),
            ("lavender", LillistColor.lavender),
        ]
        for (name, surface) in surfaces {
            for dark in [false, true] {
                let ratio = Self.ratio(LillistColor.textBody, on: surface, dark: dark)
                XCTAssertGreaterThanOrEqual(
                    ratio, 4.5,
                    "textBody on \(name) (\(dark ? "dark" : "light")) = \(String(format: "%.2f", ratio))"
                )
            }
        }
    }

    // MARK: Helpers

    private static func ratio(_ fg: Color, on bg: Color, dark: Bool) -> Double {
        let f = RainbowPaletteTests.resolveComponents(fg, dark: dark)
        let b = RainbowPaletteTests.resolveComponents(bg, dark: dark)
        let lf = ContrastMath.relativeLuminance(red: f.0, green: f.1, blue: f.2)
        let lb = ContrastMath.relativeLuminance(red: b.0, green: b.1, blue: b.2)
        return ContrastMath.wcagRatio(lf, lb)
    }
}
