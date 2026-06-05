import Testing
import Foundation
import LillistCore
@testable import LillistUI

@Suite("RecurrenceSummaryFormatter")
struct RecurrenceSummaryFormatterTests {
    private let en = Locale(identifier: "en")

    @Test("Never repeats")
    func never() {
        let text = RecurrenceSummaryFormatter.string(for: .never, locale: en)
        #expect(text == "Doesn't repeat")
    }

    @Test("Calendar, interval 1, every frequency reads singular")
    func everyUnitSingular() {
        #expect(RecurrenceSummaryFormatter.string(
            for: .calendar(.daily, interval: 1), locale: en) == "Every day")
        #expect(RecurrenceSummaryFormatter.string(
            for: .calendar(.weekly, interval: 1), locale: en) == "Every week")
        #expect(RecurrenceSummaryFormatter.string(
            for: .calendar(.monthly, interval: 1), locale: en) == "Every month")
        #expect(RecurrenceSummaryFormatter.string(
            for: .calendar(.yearly, interval: 1), locale: en) == "Every year")
    }

    @Test("Calendar, interval N reads plural")
    func everyNUnits() {
        #expect(RecurrenceSummaryFormatter.string(
            for: .calendar(.daily, interval: 2), locale: en) == "Every 2 days")
        #expect(RecurrenceSummaryFormatter.string(
            for: .calendar(.monthly, interval: 3), locale: en) == "Every 3 months")
        #expect(RecurrenceSummaryFormatter.string(
            for: .calendar(.weekly, interval: 4), locale: en) == "Every 4 weeks")
        #expect(RecurrenceSummaryFormatter.string(
            for: .calendar(.yearly, interval: 5), locale: en) == "Every 5 years")
    }

    @Test("After completion, 1 day reads singular")
    func afterCompletionSingular() {
        #expect(RecurrenceSummaryFormatter.string(
            for: .afterCompletion(days: 1), locale: en) == "Repeats 1 day after completion")
    }

    @Test("After completion, N days reads plural")
    func afterCompletionPlural() {
        #expect(RecurrenceSummaryFormatter.string(
            for: .afterCompletion(days: 7), locale: en) == "Repeats 7 days after completion")
    }
}
