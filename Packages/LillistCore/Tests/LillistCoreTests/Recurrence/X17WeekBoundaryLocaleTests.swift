import Testing
import Foundation
@testable import LillistCore

/// X17: `weeklyStep` used to compute same-week-vs-next-week using
/// `Weekday.calendarComponent`'s raw Sunday=1...Saturday=7 numbering
/// directly — silently assuming every week starts on Sunday, regardless of
/// `calendar.firstWeekday`. A biweekly Saturday/Sunday rule under a
/// Monday-first calendar treated SA/SU as split across two different
/// Sunday-first weeks rather than adjacent days in the same Monday-first
/// week, firing one week early. Parameterized across three `firstWeekday`
/// values per the review's "no locale-parameterized recurrence tests" gap.
@Suite("X17 — weekly byDay respects calendar.firstWeekday")
struct X17WeekBoundaryLocaleTests {
    /// `firstWeekday` values under test: Sunday-first (en_US-style),
    /// Monday-first (most of Europe; also Lillist's own UI weekday
    /// ordering), Saturday-first (e.g. some Arabic-locale calendars).
    private static let firstWeekdays = [1, 2, 7]

    @Test(
        "Biweekly SA/SU from a Sunday seed lands on the correct week-grouped pair, for every firstWeekday",
        arguments: firstWeekdays
    )
    func biweeklySaturdaySundayRespectsWeekBoundary(firstWeekday: Int) {
        let calendar = RecurrenceTestCalendar.calendar(firstWeekday: firstWeekday)
        // Sunday, Jan 4 2026 — chosen so Jan 3 (the day before) is a
        // Saturday, matching the review's "biweekly SA/SU" scenario.
        let seed = RecurrenceTestCalendar.date(in: calendar, year: 2026, month: 1, day: 4)
        let rule = RecurrenceRule.CalendarRule(
            freq: .weekly,
            interval: 2,
            byDay: [.saturday, .sunday]
        )
        let dates = RecurrenceExpander.nextOccurrences(after: seed, rule: rule, calendar: calendar, count: 2)
        let days = dates.map { calendar.component(.day, from: $0) }

        switch firstWeekday {
        case 1:
            // Sunday-first: the week containing Jan4(Sun) is [Dec28-Jan3]
            // wait — Jan4 itself starts a NEW Sunday-first week [Jan4-Jan10].
            // The immediate next SA (Jan10) is in that SAME week as the
            // seed, so it fires without an extra biweekly skip; the
            // following SU (two weeks later) is Jan18.
            #expect(days == [10, 18], "Sunday-first: expected [10, 18], got \(days)")
        case 2:
            // Monday-first: the week containing Jan4(Sun) is [Dec29-Jan4]
            // (Mon...Sun) — SA(Jan3) and SU(Jan4) are the LAST two days of
            // THAT week, both already elapsed. The next occurrence is the
            // SA/SU pair one full biweekly cycle later: week [Jan12-Jan18],
            // whose SA/SU are Jan17/Jan18.
            #expect(days == [17, 18], "Monday-first: expected [17, 18], got \(days)")
        case 7:
            // Saturday-first: the week containing Jan4(Sun) is [Jan3-Jan9]
            // (Sat...Fri) — SA(Jan3) and SU(Jan4=seed) are the FIRST two
            // days of THAT week, both already elapsed (like Monday-first,
            // SA/SU sit adjacent within one week, just at the opposite
            // end). The next pair is one full biweekly cycle later: week
            // [Jan17-Jan23], whose SA/SU are Jan17/Jan18 — same result as
            // Monday-first, since both keep SA/SU un-split.
            #expect(days == [17, 18], "Saturday-first: expected [17, 18], got \(days)")
        default:
            Issue.record("untested firstWeekday \(firstWeekday)")
        }
    }

    @Test("Monday-first: SA immediately following the seed SU fires in the SAME week, not the wraparound branch")
    func mondayFirstSameWeekHop() {
        let calendar = RecurrenceTestCalendar.calendar(firstWeekday: 2)
        // Saturday, Jan 3 2026 — the FIRST occurrence in a Monday-first
        // week that also contains Sunday Jan 4.
        let seed = RecurrenceTestCalendar.date(in: calendar, year: 2026, month: 1, day: 3)
        let rule = RecurrenceRule.CalendarRule(freq: .weekly, interval: 2, byDay: [.saturday, .sunday])
        let dates = RecurrenceExpander.nextOccurrences(after: seed, rule: rule, calendar: calendar, count: 1)
        let days = dates.map { calendar.component(.day, from: $0) }
        #expect(days == [4], "SU (Jan4) should fire the very next day, within the SAME Monday-first week as SA (Jan3) — got \(days)")
    }

    // MARK: - Existing suites must be unaffected (hand-derivation cross-check)

    @Test("Existing TU/TH biweekly expectations (firstWeekday=2) are unaffected by the fix")
    func nonBoundaryStraddlingPairsAreInvariant() {
        // Mirrors RecurrenceExpanderWeeklyTests.tthBiweekly exactly — TU/TH
        // never straddle any firstWeekday boundary, so this must keep
        // passing identically after the X17 fix.
        let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 6)
        let rule = RecurrenceRule.CalendarRule(freq: .weekly, interval: 2, byDay: [.tuesday, .thursday])
        let dates = RecurrenceExpander.nextOccurrences(
            after: seed, rule: rule, calendar: RecurrenceTestCalendar.pacific, count: 4
        )
        let formatter = DateFormatter()
        formatter.calendar = RecurrenceTestCalendar.pacific
        formatter.timeZone = RecurrenceTestCalendar.pacific.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let days = dates.map(formatter.string(from:))
        #expect(days == ["2026-01-08", "2026-01-20", "2026-01-22", "2026-02-03"])
    }
}
