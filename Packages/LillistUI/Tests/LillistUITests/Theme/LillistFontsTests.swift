import XCTest
@testable import LillistUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Registration coverage for the bundled Plus Jakarta Sans faces.
final class LillistFontsTests: XCTestCase {

    func testRegistrationSucceeds() {
        XCTAssertTrue(
            LillistFonts.registerIfNeeded(),
            "Plus Jakarta Sans failed to register from the LillistUI resource bundle"
        )
    }

    func testRegistrationIsIdempotent() {
        XCTAssertTrue(LillistFonts.registerIfNeeded())
        XCTAssertTrue(LillistFonts.registerIfNeeded(), "second call must not regress")
    }

    func testEveryBundledWeightResolves() {
        LillistFonts.registerIfNeeded()
        for weight in LillistFonts.weights {
            let name = "\(LillistFonts.familyStem)-\(weight)"
            XCTAssertTrue(LillistFonts.faceIsUsable(name), "\(name) did not resolve to a real face")
        }
    }

    func testUnknownFaceIsNotUsable() {
        XCTAssertFalse(LillistFonts.faceIsUsable("PlusJakartaSans-Nonexistent"))
    }

    func testFontFilesAreBundled() {
        for weight in LillistFonts.weights {
            XCTAssertNotNil(
                Bundle.module.url(forResource: "\(LillistFonts.familyStem)-\(weight)", withExtension: "ttf"),
                "\(weight).ttf missing from resources"
            )
        }
        XCTAssertNotNil(
            Bundle.module.url(forResource: "OFL", withExtension: "txt"),
            "font license must ship alongside the faces"
        )
    }
}
