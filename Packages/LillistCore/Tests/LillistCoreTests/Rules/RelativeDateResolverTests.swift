import Testing
import Foundation
@testable import LillistCore

@Suite("RelativeDateResolver")
struct RelativeDateResolverTests {
    /// A fixed reference moment: 2026-05-12 (Tuesday) 14:30 UTC.
    static let now: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 12
        c.hour = 14; c.minute = 30; c.second = 0
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }()

    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 1 // Sunday
        return cal
    }

    @Test("today resolves to start of current day")
    func today() {
        let d = RelativeDateResolver.resolve(.today, now: Self.now, calendar: Self.calendar)
        let comps = Self.calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
        #expect(comps.year == 2026)
        #expect(comps.month == 5)
        #expect(comps.day == 12)
        #expect(comps.hour == 0)
        #expect(comps.minute == 0)
        #expect(comps.second == 0)
    }

    @Test("tomorrow is today + 1 day")
    func tomorrow() {
        let d = RelativeDateResolver.resolve(.tomorrow, now: Self.now, calendar: Self.calendar)
        let comps = Self.calendar.dateComponents([.year, .month, .day], from: d)
        #expect(comps.day == 13)
    }

    @Test("yesterday is today - 1 day")
    func yesterday() {
        let d = RelativeDateResolver.resolve(.yesterday, now: Self.now, calendar: Self.calendar)
        let comps = Self.calendar.dateComponents([.year, .month, .day], from: d)
        #expect(comps.day == 11)
    }

    @Test("daysFromNow(7) is today + 7 days")
    func plus7d() {
        let d = RelativeDateResolver.resolve(.daysFromNow(7), now: Self.now, calendar: Self.calendar)
        let comps = Self.calendar.dateComponents([.year, .month, .day], from: d)
        #expect(comps.day == 19)
    }

    @Test("weeksFromNow(-2) is today - 14 days")
    func minus2w() {
        let d = RelativeDateResolver.resolve(.weeksFromNow(-2), now: Self.now, calendar: Self.calendar)
        let comps = Self.calendar.dateComponents([.year, .month, .day], from: d)
        #expect(comps.month == 4)
        #expect(comps.day == 28)
    }

    @Test("startOfWeek with Sunday-firstWeekday resolves to Sunday 2026-05-10")
    func startOfWeek() {
        let d = RelativeDateResolver.resolve(.startOfWeek, now: Self.now, calendar: Self.calendar)
        let comps = Self.calendar.dateComponents([.year, .month, .day, .weekday], from: d)
        #expect(comps.day == 10)
        #expect(comps.weekday == 1) // Sunday
    }

    @Test("endOfWeek with Sunday-firstWeekday resolves to end of Saturday 2026-05-16")
    func endOfWeek() {
        let d = RelativeDateResolver.resolve(.endOfWeek, now: Self.now, calendar: Self.calendar)
        let comps = Self.calendar.dateComponents([.year, .month, .day, .hour], from: d)
        #expect(comps.day == 16)
        // Last instant of the day = 23:59:59
        #expect(comps.hour == 23)
    }

    @Test("startOfMonth is first day of current month")
    func startOfMonth() {
        let d = RelativeDateResolver.resolve(.startOfMonth, now: Self.now, calendar: Self.calendar)
        let comps = Self.calendar.dateComponents([.year, .month, .day, .hour], from: d)
        #expect(comps.month == 5)
        #expect(comps.day == 1)
        #expect(comps.hour == 0)
    }

    @Test("endOfMonth is last instant of last day of current month")
    func endOfMonth() {
        let d = RelativeDateResolver.resolve(.endOfMonth, now: Self.now, calendar: Self.calendar)
        let comps = Self.calendar.dateComponents([.year, .month, .day, .hour], from: d)
        #expect(comps.month == 5)
        #expect(comps.day == 31)
        #expect(comps.hour == 23)
    }
}
