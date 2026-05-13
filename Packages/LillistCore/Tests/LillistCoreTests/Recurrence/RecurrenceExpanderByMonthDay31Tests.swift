import Testing
import Foundation
@testable import LillistCore

@Suite("RecurrenceExpander byMonthDay=31")
struct RecurrenceExpanderByMonthDay31Tests {
    @Test("byMonthDay=31 skips months that don't have 31")
    func skipsShortMonths() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 31)
        let rule = RecurrenceRule.CalendarRule(
            freq: .monthly,
            interval: 1,
            byMonthDay: [31]
        )
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 5
        )
        let formatter = DateFormatter()
        formatter.calendar = RecurrenceTestCalendar.pacific
        formatter.timeZone = RecurrenceTestCalendar.pacific.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        #expect(dates.map(formatter.string(from:)) == [
            "2026-03-31", "2026-05-31", "2026-07-31", "2026-08-31", "2026-10-31"
        ])
    }

    @Test("byMonthDay=31 does NOT coerce to the 30th")
    func doesNotCoerceTo30() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 31)
        let rule = RecurrenceRule.CalendarRule(
            freq: .monthly,
            interval: 1,
            byMonthDay: [31]
        )
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 5
        )
        for d in dates {
            #expect(RecurrenceTestCalendar.pacific.component(.day, from: d) == 31)
        }
    }

    @Test("Plain monthly with seed on the 31st also skips short months")
    func plainMonthlySkipsShortMonths() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 31)
        let rule = RecurrenceRule.CalendarRule(freq: .monthly, interval: 1)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 3
        )
        let days = dates.map { RecurrenceTestCalendar.pacific.component(.day, from: $0) }
        #expect(days == [31, 31, 31])
        let months = dates.map { RecurrenceTestCalendar.pacific.component(.month, from: $0) }
        #expect(months == [3, 5, 7])
    }
}
