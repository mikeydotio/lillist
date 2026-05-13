import Testing
import Foundation
@testable import LillistCore

@Suite("RecurrenceExpander bySetPos")
struct RecurrenceExpanderBySetPosTests {
    @Test("Monthly first Monday")
    func firstMondayOfMonth() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 1)
        let rule = RecurrenceRule.CalendarRule(
            freq: .monthly,
            interval: 1,
            byDay: [.monday],
            bySetPos: [1]
        )
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
        #expect(dates.map(formatter.string(from:)) == ["2026-01-05", "2026-02-02", "2026-03-02"])
    }

    @Test("Monthly last Friday")
    func lastFridayOfMonth() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 1)
        let rule = RecurrenceRule.CalendarRule(
            freq: .monthly,
            interval: 1,
            byDay: [.friday],
            bySetPos: [-1]
        )
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
        #expect(dates.map(formatter.string(from:)) == ["2026-01-30", "2026-02-27", "2026-03-27"])
    }

    @Test("Monthly first weekday")
    func firstWeekdayOfMonth() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 1)
        let rule = RecurrenceRule.CalendarRule(
            freq: .monthly,
            interval: 1,
            byDay: [.monday, .tuesday, .wednesday, .thursday, .friday],
            bySetPos: [1]
        )
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
        #expect(dates.map(formatter.string(from:)) == ["2026-02-02", "2026-03-02", "2026-04-01"])
    }
}
