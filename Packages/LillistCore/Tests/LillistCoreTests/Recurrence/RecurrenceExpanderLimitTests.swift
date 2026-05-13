import Testing
import Foundation
@testable import LillistCore

@Suite("RecurrenceExpander limits")
struct RecurrenceExpanderLimitTests {
    @Test("count=0 yields no occurrences")
    func countZero() {
        let rule = RecurrenceRule.CalendarRule(freq: .daily, interval: 1, count: 0)
        let dates = RecurrenceExpander.nextOccurrences(
            after: Date(),
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 10
        )
        #expect(dates.isEmpty)
    }

    @Test("until before first computed occurrence yields no occurrences")
    func untilBeforeFirst() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 1)
        let until = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 1)
        let rule = RecurrenceRule.CalendarRule(freq: .daily, interval: 1, until: until)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 10
        )
        #expect(dates.isEmpty)
    }

    @Test("count smaller than requested batch caps results")
    func countCaps() {
        let rule = RecurrenceRule.CalendarRule(freq: .daily, interval: 1, count: 3)
        let dates = RecurrenceExpander.nextOccurrences(
            after: Date(),
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 100
        )
        #expect(dates.count == 3)
    }

    @Test("until on the same instant as a computed occurrence includes it")
    func untilInclusiveOfMatchingInstant() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 1, hour: 9)
        let until = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 3, hour: 9)
        let rule = RecurrenceRule.CalendarRule(freq: .daily, interval: 1, until: until)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 10
        )
        #expect(dates.count == 2)
    }

    @Test("count interacts with until — whichever is tighter wins")
    func countAndUntil() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 1)
        let until = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 4)
        let rule = RecurrenceRule.CalendarRule(freq: .daily, interval: 1, count: 10, until: until)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 100
        )
        #expect(dates.count == 3)
    }
}
