import Testing
import Foundation
@testable import LillistCore

@Suite("RecurrenceExpander DST")
struct RecurrenceExpanderDSTTests {
    @Test("Daily across spring-forward preserves 09:00 wall clock")
    func dailyAcrossSpringForward() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 3, day: 6, hour: 9)
        let rule = RecurrenceRule.CalendarRule(freq: .daily, interval: 1)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 4
        )
        for d in dates {
            #expect(RecurrenceTestCalendar.pacific.component(.hour, from: d) == 9)
            #expect(RecurrenceTestCalendar.pacific.component(.minute, from: d) == 0)
        }
    }

    @Test("Daily across fall-back preserves 09:00 wall clock")
    func dailyAcrossFallBack() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 10, day: 30, hour: 9)
        let rule = RecurrenceRule.CalendarRule(freq: .daily, interval: 1)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 4
        )
        for d in dates {
            #expect(RecurrenceTestCalendar.pacific.component(.hour, from: d) == 9)
            #expect(RecurrenceTestCalendar.pacific.component(.minute, from: d) == 0)
        }
    }

    @Test("Weekly across spring-forward preserves wall clock")
    func weeklyAcrossSpringForward() {
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 3, day: 1, hour: 14, minute: 30)
        let rule = RecurrenceRule.CalendarRule(freq: .weekly, interval: 1)
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed,
            rule: rule,
            calendar: RecurrenceTestCalendar.pacific,
            count: 3
        )
        for d in dates {
            #expect(RecurrenceTestCalendar.pacific.component(.hour, from: d) == 14)
            #expect(RecurrenceTestCalendar.pacific.component(.minute, from: d) == 30)
        }
    }
}
