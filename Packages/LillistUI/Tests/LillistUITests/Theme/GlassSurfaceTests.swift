import XCTest
import SwiftUI
@testable import LillistUI

/// Contract coverage for the `GlassSurface` seam's *functional-color*
/// invariants — the part of Rainbow Glass that is deterministic without
/// rendering. The rendered glass treatment (refraction, degradation
/// branches, dark-mode) is snapshot-test territory and is covered on the
/// signed Mac as each call-site adopts the seam.
///
/// These guard the house rule "color is functional, never decorative":
/// neutral chrome must never carry a tint, and a status-tinted surface
/// must carry exactly the functional hue it was handed so its color *is*
/// the signal.
final class GlassSurfaceTests: XCTestCase {

    private static let neutralSurfaces: [GlassSurface] = [.panel, .toast, .control, .card]

    // MARK: Tinting (the functional-color contract)

    func testNeutralSurfacesHaveNoTint() {
        for surface in Self.neutralSurfaces {
            XCTAssertNil(surface.tint, "\(surface) is non-semantic chrome and must be neutral glass")
        }
    }

    func testStatusTintedReturnsTheProvidedHue() {
        let hue = RainbowPalette.actionOrange.base
        guard let tint = GlassSurface.statusTinted(hue).tint else {
            return XCTFail("a status-tinted surface must expose its hue")
        }
        XCTAssertEqual(
            RainbowPaletteTests.resolve(tint, dark: false),
            RainbowPaletteTests.resolve(hue, dark: false)
        )
        XCTAssertEqual(
            RainbowPaletteTests.resolve(tint, dark: true),
            RainbowPaletteTests.resolve(hue, dark: true)
        )
    }

    // MARK: Pre-26 fallback (chrome stays material; fills stay solid)

    func testTintedFillsPreferSolidFallback() {
        // Tinted fills were never frosted chrome — on pre-26 (e.g. macOS
        // Sequoia) they must stay solid, not turn translucent.
        XCTAssertTrue(GlassSurface.statusTinted(RainbowPalette.focusBlue.base).prefersSolidFallback)
        XCTAssertTrue(GlassSurface.card.prefersSolidFallback)
        XCTAssertTrue(GlassSurface.control.prefersSolidFallback)
    }

    func testChromeUsesMaterialFallback() {
        // Panels and toasts were `.regularMaterial` — they keep that
        // frosted fallback below OS 26.
        XCTAssertFalse(GlassSurface.panel.prefersSolidFallback)
        XCTAssertFalse(GlassSurface.toast.prefersSolidFallback)
    }

    // MARK: Equatable (so co-visible grouping / diffing is reliable)

    func testEquatableDistinguishesRoles() {
        XCTAssertEqual(GlassSurface.panel, .panel)
        XCTAssertNotEqual(GlassSurface.panel, .toast)
        XCTAssertNotEqual(GlassSurface.control, .card)
    }

    func testStatusTintedEqualityFollowsTheHue() {
        let blue = RainbowPalette.focusBlue.base
        XCTAssertEqual(GlassSurface.statusTinted(blue), .statusTinted(blue))
    }
}
