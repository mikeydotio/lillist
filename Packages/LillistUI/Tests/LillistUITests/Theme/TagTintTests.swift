import Testing
import SwiftUI
@testable import LillistUI

@Suite("TagTint")
struct TagTintTests {
    @Test("Parses #RRGGBB and #RGB hex strings")
    func parsesHex() {
        #expect(TagTint(hex: "#FF0000") != nil)
        #expect(TagTint(hex: "#F00") != nil)
        #expect(TagTint(hex: "garbage") == nil)
    }

    @Test("Desaturates in dark mode")
    func desaturates() {
        let tint = TagTint(hex: "#3366FF")!
        let dark = tint.resolved(in: .dark)
        let light = tint.resolved(in: .light)
        #expect(dark.saturation < light.saturation)
    }
}
