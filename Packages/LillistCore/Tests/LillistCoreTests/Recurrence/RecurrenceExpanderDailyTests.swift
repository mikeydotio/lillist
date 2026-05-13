import Testing
import Foundation
@testable import LillistCore

@Suite("RecurrenceExpander daily")
struct RecurrenceExpanderDailyTests {
    @Test("Daily interval=1 produces consecutive days")
    func dailyEveryDay() throws {
        let rule = RecurrenceRule.CalendarRule(freq: .daily, interval: 1)
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 1, hour: 9)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 3
        )
        #expect(dates == [
            RecurrenceTestCalendar.date(year: 2026, month: 1, day: 2, hour: 9),
            RecurrenceTestCalendar.date(year: 2026, month: 1, day: 3, hour: 9),
            RecurrenceTestCalendar.date(year: 2026, month: 1, day: 4, hour: 9)
        ])
    }

    @Test("Daily interval=3 skips two days each step")
    func dailyEveryThirdDay() throws {
        let rule = RecurrenceRule.CalendarRule(freq: .daily, interval: 3)
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 6, day: 1, hour: 14)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 4
        )
        #expect(dates.map { RecurrenceTestCalendar.pacific.component(.day, from: $0) } == [4, 7, 10, 13])
    }

    @Test("Daily count=2 yields exactly 2 occurrences even when callers ask for more")
    func dailyCountCap() throws {
        let rule = RecurrenceRule.CalendarRule(freq: .daily, interval: 1, count: 2)
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 1)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 10
        )
        #expect(dates.count == 2)
    }

    @Test("Daily until cuts off the stream")
    func dailyUntilCutoff() throws {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 1)
        let until = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 3, hour: 23, minute: 59)
        let rule = RecurrenceRule.CalendarRule(freq: .daily, interval: 1, until: until)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 10
        )
        #expect(dates.count == 2)
    }
}
