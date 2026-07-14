import Testing
import Foundation
@testable import LillistUI

/// `DueLineFormatter` renders the compact schedule line on the detail card.
/// All cases pin a fixed `now`, a GMT Gregorian calendar, and the `en_US`
/// locale so wording and date/time rendering are fully deterministic.
@Suite("DueLineFormatter")
struct DueLineFormatterTests {

    private let locale = Locale(identifier: "en_US")

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "GMT")!
        c.locale = locale
        return c
    }

    /// 2026-07-14 09:00 GMT — the reference "today" for every relative case.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 9, minute: 0))!
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func format(
        deadline: Date? = nil,
        deadlineHasTime: Bool = false,
        start: Date? = nil,
        startHasTime: Bool = false,
        recurrence: RecurrenceSummary = .never
    ) -> String {
        let raw = DueLineFormatter.string(
            deadline: deadline,
            deadlineHasTime: deadlineHasTime,
            start: start,
            startHasTime: startHasTime,
            recurrence: recurrence,
            now: now,
            calendar: calendar,
            locale: locale
        )
        // `Date.FormatStyle` separates the time from AM/PM with a narrow
        // no-break space (U+202F); normalize the exotic spaces to a plain
        // space so the expectations stay readable and OS-version-stable.
        return raw
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    @Test("no dates → placeholder")
    func noDates() {
        #expect(format() == "No due date")
    }

    @Test("deadline today, no time")
    func todayNoTime() {
        #expect(format(deadline: date(2026, 7, 14)) == "Due today")
    }

    @Test("deadline tomorrow with a whole-hour time drops the minutes")
    func tomorrowWholeHour() {
        #expect(format(deadline: date(2026, 7, 15, 17, 0), deadlineHasTime: true)
            == "Due tomorrow at 5 PM")
    }

    @Test("deadline tomorrow with a non-zero minute keeps the minutes")
    func tomorrowWithMinutes() {
        #expect(format(deadline: date(2026, 7, 15, 17, 30), deadlineHasTime: true)
            == "Due tomorrow at 5:30 PM")
    }

    @Test("deadline yesterday, no time")
    func yesterday() {
        #expect(format(deadline: date(2026, 7, 13)) == "Due yesterday")
    }

    @Test("hasTime=false ignores any time component")
    func hasTimeFalseIgnoresTime() {
        #expect(format(deadline: date(2026, 7, 15, 17, 30), deadlineHasTime: false)
            == "Due tomorrow")
    }

    @Test("far date in the same year renders absolutely, no year")
    func absoluteSameYear() {
        #expect(format(deadline: date(2026, 8, 23)) == "Due Aug 23")
    }

    @Test("date in a different year includes the year")
    func absoluteCrossYear() {
        #expect(format(deadline: date(2027, 1, 5)) == "Due Jan 5, 2027")
    }

    @Test("recurrence appends a parenthetical suffix")
    func recurrenceSuffix() {
        #expect(format(deadline: date(2026, 7, 14), recurrence: .calendar(.monthly, interval: 1))
            == "Due today (Every month)")
    }

    @Test("recurring with time and absolute date")
    func recurringWithTime() {
        #expect(format(
            deadline: date(2026, 8, 1, 17, 0),
            deadlineHasTime: true,
            recurrence: .calendar(.weekly, interval: 2)
        ) == "Due Aug 1 at 5 PM (Every 2 weeks)")
    }

    @Test("no deadline falls back to the start date with a Starts lead-in")
    func startFallback() {
        #expect(format(start: date(2026, 7, 15, 9, 0), startHasTime: true)
            == "Starts tomorrow at 9 AM")
    }

    @Test("deadline takes precedence over start")
    func deadlineBeatsStart() {
        #expect(format(deadline: date(2026, 7, 14), start: date(2026, 7, 20))
            == "Due today")
    }
}
