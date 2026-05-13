import Testing
import Foundation
@testable import LillistCore

@Suite("RecurrenceExpander weekly")
struct RecurrenceExpanderWeeklyTests {
    @Test("Weekly with no byDay repeats the seed's weekday")
    func plainWeekly() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 5, hour: 9)
        let rule = RecurrenceRule.CalendarRule(freq: .weekly, interval: 1)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 3
        )
        let weekdays = dates.map { RecurrenceTestCalendar.pacific.component(.weekday, from: $0) }
        #expect(weekdays == [Weekday.monday.calendarComponent,
                              Weekday.monday.calendarComponent,
                              Weekday.monday.calendarComponent])
        let days = dates.map { RecurrenceTestCalendar.pacific.component(.day, from: $0) }
        #expect(days == [12, 19, 26])
    }

    @Test("Weekly interval=2 jumps two weeks")
    func biweekly() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 5)
        let rule = RecurrenceRule.CalendarRule(freq: .weekly, interval: 2)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 2
        )
        let days = dates.map { RecurrenceTestCalendar.pacific.component(.day, from: $0) }
        #expect(days == [19, 2])
    }

    @Test("Weekly byDay=[MO,WE,FR] fires on each day in order")
    func mwfPattern() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 5, hour: 9)
        let rule = RecurrenceRule.CalendarRule(
            freq: .weekly,
            interval: 1,
            byDay: [.monday, .wednesday, .friday]
        )
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 5
        )
        let days = dates.map { RecurrenceTestCalendar.pacific.component(.day, from: $0) }
        #expect(days == [7, 9, 12, 14, 16])
    }

    @Test("Weekly byDay=[TU,TH] interval=2 only fires Tue/Thu in alternating weeks")
    func tthBiweekly() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 6)
        let rule = RecurrenceRule.CalendarRule(
            freq: .weekly,
            interval: 2,
            byDay: [.tuesday, .thursday]
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
        let days = dates.map(formatter.string(from:))
        #expect(days == ["2026-01-08", "2026-01-20", "2026-01-22", "2026-02-03"])
    }

    @Test("Weekly preserves seed's wall-clock hour")
    func preservesTime() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 5, hour: 14, minute: 30)
        let rule = RecurrenceRule.CalendarRule(freq: .weekly, interval: 1)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 2
        )
        for d in dates {
            #expect(RecurrenceTestCalendar.pacific.component(.hour, from: d) == 14)
            #expect(RecurrenceTestCalendar.pacific.component(.minute, from: d) == 30)
        }
    }
}
