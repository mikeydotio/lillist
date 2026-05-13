import Testing
import Foundation
@testable import LillistCore

@Suite("RecurrenceExpander yearly")
struct RecurrenceExpanderYearlyTests {
    @Test("Yearly interval=1 repeats month-day across years")
    func plainYearly() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 3, day: 15)
        let rule = RecurrenceRule.CalendarRule(freq: .yearly, interval: 1)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 3
        )
        let years = dates.map { RecurrenceTestCalendar.pacific.component(.year, from: $0) }
        #expect(years == [2027, 2028, 2029])
    }

    @Test("Yearly Feb 29 seed skips non-leap years")
    func feb29SkipsNonLeapYears() {
        let seed = RecurrenceTestCalendar.date(year: 2024, month: 2, day: 29)
        let rule = RecurrenceRule.CalendarRule(freq: .yearly, interval: 1)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 2
        )
        let years = dates.map { RecurrenceTestCalendar.pacific.component(.year, from: $0) }
        let months = dates.map { RecurrenceTestCalendar.pacific.component(.month, from: $0) }
        let days = dates.map { RecurrenceTestCalendar.pacific.component(.day, from: $0) }
        #expect(years == [2028, 2032])
        #expect(months == [2, 2])
        #expect(days == [29, 29])
    }
}
