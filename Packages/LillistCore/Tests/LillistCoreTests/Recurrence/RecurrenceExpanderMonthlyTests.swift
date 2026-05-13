import Testing
import Foundation
@testable import LillistCore

@Suite("RecurrenceExpander monthly")
struct RecurrenceExpanderMonthlyTests {
    @Test("Monthly interval=1 with no byMonthDay repeats seed day-of-month")
    func plainMonthly() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 15, hour: 9)
        let rule = RecurrenceRule.CalendarRule(freq: .monthly, interval: 1)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 3
        )
        let formatter = DateFormatter()
        formatter.calendar = RecurrenceTestCalendar.pacific
        formatter.timeZone = RecurrenceTestCalendar.pacific.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        #expect(dates.map(formatter.string(from:)) == ["2026-02-15", "2026-03-15", "2026-04-15"])
    }

    @Test("Monthly interval=3 fires every quarter")
    func quarterly() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 1)
        let rule = RecurrenceRule.CalendarRule(freq: .monthly, interval: 3)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 3
        )
        let months = dates.map { RecurrenceTestCalendar.pacific.component(.month, from: $0) }
        let years = dates.map { RecurrenceTestCalendar.pacific.component(.year, from: $0) }
        #expect(months == [4, 7, 10])
        #expect(years == [2026, 2026, 2026])
    }

    @Test("Monthly with byMonthDay=[1,15] fires twice each month")
    func multipleMonthDays() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 1)
        let rule = RecurrenceRule.CalendarRule(
            freq: .monthly,
            interval: 1,
            byMonthDay: [1, 15]
        )
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 4
        )
        let formatter = DateFormatter()
        formatter.calendar = RecurrenceTestCalendar.pacific
        formatter.timeZone = RecurrenceTestCalendar.pacific.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        #expect(dates.map(formatter.string(from:)) == [
            "2026-01-15", "2026-02-01", "2026-02-15", "2026-03-01"
        ])
    }

    @Test("Monthly byMonthDay=[15] interval=2 fires every other month on the 15th")
    func bimonthly() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 15)
        let rule = RecurrenceRule.CalendarRule(
            freq: .monthly,
            interval: 2,
            byMonthDay: [15]
        )
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 3
        )
        let months = dates.map { RecurrenceTestCalendar.pacific.component(.month, from: $0) }
        #expect(months == [3, 5, 7])
    }
}
