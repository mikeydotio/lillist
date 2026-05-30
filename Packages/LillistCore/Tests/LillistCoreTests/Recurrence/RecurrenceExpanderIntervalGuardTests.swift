import Testing
import Foundation
@testable import LillistCore

@Suite("RecurrenceExpander interval guard (defense-in-depth)")
struct RecurrenceExpanderIntervalGuardTests {
    private let seed = RecurrenceTestCalendar.date(year: 2026, month: 1, day: 15, hour: 9)
    private let calendar = RecurrenceTestCalendar.pacific

    /// Forces `interval` to `invalid` after construction (bypassing the
    /// `CalendarRule` boundary) and asserts the expander treats it as `1` —
    /// the same finite, non-empty result as a canonical interval=1 rule.
    private func expectTreatedAsOne(
        freq: RecurrenceRule.Frequency,
        invalid: Int,
        byDay: [Weekday]? = nil,
        bySetPos: [Int]? = nil
    ) {
        var rule = RecurrenceRule.CalendarRule(
            freq: freq,
            interval: 1,
            byDay: byDay,
            bySetPos: bySetPos
        )
        rule.interval = invalid // defeat the boundary

        let canonical = RecurrenceExpander.nextOccurrences(
            after: seed, rule: { var r = rule; r.interval = 1; return r }(),
            calendar: calendar, count: 3
        )
        let guarded = RecurrenceExpander.nextOccurrences(
            after: seed, rule: rule, calendar: calendar, count: 3
        )
        #expect(guarded.isEmpty == false)
        #expect(guarded == canonical)
    }

    @Test("daily interval 0 does not loop-trap and behaves as interval 1")
    func dailyZero() { expectTreatedAsOne(freq: .daily, invalid: 0) }

    @Test("daily interval -1 does not walk backwards forever")
    func dailyNegative() { expectTreatedAsOne(freq: .daily, invalid: -1) }

    @Test("weekly (no byDay) interval 0 does not loop-trap")
    func weeklyZeroNoByDay() { expectTreatedAsOne(freq: .weekly, invalid: 0) }

    @Test("weekly (with byDay wrap) interval 0 does not loop-trap")
    func weeklyZeroWithByDay() {
        expectTreatedAsOne(freq: .weekly, invalid: 0, byDay: [.monday])
    }

    @Test("weekly interval -1 with byDay wrap is finite")
    func weeklyNegativeWithByDay() {
        expectTreatedAsOne(freq: .weekly, invalid: -1, byDay: [.monday])
    }

    @Test("monthly interval 0 does not divide-by-zero crash")
    func monthlyZero() { expectTreatedAsOne(freq: .monthly, invalid: 0) }

    @Test("monthly interval -1 does not crash")
    func monthlyNegative() { expectTreatedAsOne(freq: .monthly, invalid: -1) }

    @Test("monthly by-set-pos interval 0 does not divide-by-zero crash")
    func monthlyBySetPosZero() {
        expectTreatedAsOne(freq: .monthly, invalid: 0, byDay: [.monday], bySetPos: [1])
    }

    @Test("yearly interval 0 does not loop-trap")
    func yearlyZero() { expectTreatedAsOne(freq: .yearly, invalid: 0) }

    @Test("yearly interval -1 is finite")
    func yearlyNegative() { expectTreatedAsOne(freq: .yearly, invalid: -1) }
}
