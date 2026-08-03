import Testing
@testable import LillistUI

/// `LIL-95`: which card families may render a dimmed context row, and the
/// widget-scale indent unit used for nesting.
@Suite("WidgetLayout")
struct WidgetLayoutTests {
    @Test("only .small disallows context rows — its ~94pt title budget can't spare a row for a non-match")
    func onlySmallDisallowsContextRows() {
        #expect(WidgetLayout.small.allowsContextRows == false)
        #expect(WidgetLayout.medium.allowsContextRows == true)
        #expect(WidgetLayout.large.allowsContextRows == true)
        #expect(WidgetLayout.extraLarge.allowsContextRows == true)
    }

    @Test("indent per level is the widget-scale token, not the app's coarser drag-outline indent")
    func indentIsWidgetScale() {
        for layout in WidgetLayout.allCases {
            #expect(layout.indentPerLevel == LillistSpacing.m)
        }
    }
}
