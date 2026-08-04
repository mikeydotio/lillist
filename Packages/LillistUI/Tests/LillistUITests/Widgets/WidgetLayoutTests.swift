import Testing
@testable import LillistUI

/// `LIL-95`: the widget-scale indent unit used for nesting. `.systemSmall`
/// renders `WidgetStatusDonutView` instead of a `WidgetLayout` card
/// (`LIL-96`), so `WidgetLayout` only covers medium/large/extraLarge now.
@Suite("WidgetLayout")
struct WidgetLayoutTests {
    @Test("indent per level is the widget-scale token, not the app's coarser drag-outline indent")
    func indentIsWidgetScale() {
        for layout in WidgetLayout.allCases {
            #expect(layout.indentPerLevel == LillistSpacing.m)
        }
    }
}
