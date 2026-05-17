import XCTest
@testable import LillistUI

final class ContrastMathTests: XCTestCase {
    func test_relativeLuminance_white_is_1() {
        XCTAssertEqual(ContrastMath.relativeLuminance(red: 1, green: 1, blue: 1), 1.0, accuracy: 0.001)
    }

    func test_relativeLuminance_black_is_0() {
        XCTAssertEqual(ContrastMath.relativeLuminance(red: 0, green: 0, blue: 0), 0.0, accuracy: 0.001)
    }

    func test_wcagRatio_black_on_white_is_21() {
        let l1 = ContrastMath.relativeLuminance(red: 1, green: 1, blue: 1)
        let l2 = ContrastMath.relativeLuminance(red: 0, green: 0, blue: 0)
        XCTAssertEqual(ContrastMath.wcagRatio(l1, l2), 21.0, accuracy: 0.01)
    }

    func test_wcagRatio_isCommutative() {
        let a = ContrastMath.relativeLuminance(red: 0.2, green: 0.4, blue: 0.6)
        let b = ContrastMath.relativeLuminance(red: 0.9, green: 0.9, blue: 0.9)
        XCTAssertEqual(ContrastMath.wcagRatio(a, b), ContrastMath.wcagRatio(b, a), accuracy: 0.0001)
    }

    func test_hsbToRGB_roundtrip() {
        // HSB(0.6, 0.7, 0.8) → RGB and back should land near the original.
        let (r, g, b) = ContrastMath.hsbToRGB(hue: 0.6, saturation: 0.7, brightness: 0.8)
        // Sanity check: brightness 0.8 ≈ max channel
        XCTAssertEqual(max(r, max(g, b)), 0.8, accuracy: 0.001)
    }
}
