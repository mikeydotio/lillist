import Testing
import LillistCore
@testable import LillistUI

@Suite("Quick Capture date suggestions")
struct QuickCaptureDateSuggestionsTests {
    @Test("Default suggestions are the canonical four")
    func defaultSuggestions() {
        #expect(QuickCaptureDateSuggestions.default == ["today", "tomorrow", "+3d", "+1w"])
    }

    @Test("Every default suggestion resolves through RelativeDate.parse")
    func everyDefaultSuggestionResolves() throws {
        for token in QuickCaptureDateSuggestions.default {
            #expect(throws: Never.self) {
                _ = try RelativeDate.parse(token)
            }
        }
    }
}
