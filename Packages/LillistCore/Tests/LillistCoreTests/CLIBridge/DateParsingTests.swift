import Testing
import Foundation
@testable import LillistCore

@Suite("CLIBridge.DateParsing")
struct DateParsingTests {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return cal
    }

    private func ref() -> Date {
        // 2026-05-12 (Tuesday) 12:00 PDT
        var comps = DateComponents()
        comps.year = 2026; comps.month = 5; comps.day = 12; comps.hour = 12
        comps.timeZone = TimeZone(identifier: "America/Los_Angeles")
        return calendar.date(from: comps)!
    }

    @Test("ISO-8601 date only parses without time")
    func iso8601DateOnly() throws {
        let r = try CLIBridge.DateParsing.parse("2026-06-01", now: ref(), calendar: calendar)
        #expect(r.hasTime == false)
        let comps = calendar.dateComponents([.year, .month, .day], from: r.date)
        #expect(comps.year == 2026); #expect(comps.month == 6); #expect(comps.day == 1)
    }

    @Test("ISO-8601 date+time parses with time")
    func iso8601DateTime() throws {
        let r = try CLIBridge.DateParsing.parse("2026-06-01T09:30:00Z", now: ref(), calendar: calendar)
        #expect(r.hasTime == true)
        // Verify the absolute instant in UTC is 09:30 — interpretation in PDT
        // is up to the caller.
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let comps = utc.dateComponents([.hour, .minute], from: r.date)
        #expect(comps.hour == 9); #expect(comps.minute == 30)
    }

    @Test("today resolves to ref's calendar date, no time")
    func today() throws {
        let r = try CLIBridge.DateParsing.parse("today", now: ref(), calendar: calendar)
        #expect(r.hasTime == false)
        let comps = calendar.dateComponents([.year, .month, .day], from: r.date)
        #expect(comps.year == 2026); #expect(comps.month == 5); #expect(comps.day == 12)
    }

    @Test("tomorrow resolves to next day")
    func tomorrow() throws {
        let r = try CLIBridge.DateParsing.parse("tomorrow", now: ref(), calendar: calendar)
        #expect(r.hasTime == false)
        let comps = calendar.dateComponents([.day], from: r.date)
        #expect(comps.day == 13)
    }

    @Test("yesterday resolves to previous day")
    func yesterday() throws {
        let r = try CLIBridge.DateParsing.parse("yesterday", now: ref(), calendar: calendar)
        let comps = calendar.dateComponents([.day], from: r.date)
        #expect(comps.day == 11)
    }

    @Test("tomorrow 9am has time = true and hour 9")
    func tomorrow9am() throws {
        let r = try CLIBridge.DateParsing.parse("tomorrow 9am", now: ref(), calendar: calendar)
        #expect(r.hasTime == true)
        let comps = calendar.dateComponents([.hour, .minute], from: r.date)
        #expect(comps.hour == 9); #expect(comps.minute == 0)
    }

    @Test("next monday resolves to following monday")
    func nextMonday() throws {
        let r = try CLIBridge.DateParsing.parse("next monday", now: ref(), calendar: calendar)
        let comps = calendar.dateComponents([.weekday, .month, .day], from: r.date)
        #expect(comps.weekday == 2) // Monday
        // 2026-05-12 is Tuesday; next Monday is May 18.
        #expect(comps.day == 18)
    }

    @Test("next monday at 9 has time")
    func nextMondayAt9() throws {
        let r = try CLIBridge.DateParsing.parse("next monday at 9", now: ref(), calendar: calendar)
        #expect(r.hasTime == true)
        let comps = calendar.dateComponents([.weekday, .hour], from: r.date)
        #expect(comps.weekday == 2); #expect(comps.hour == 9)
    }

    @Test("Relative DSL +7d resolves to 7 days from now")
    func plus7d() throws {
        let r = try CLIBridge.DateParsing.parse("+7d", now: ref(), calendar: calendar)
        let comps = calendar.dateComponents([.day], from: r.date)
        #expect(comps.day == 19)
    }

    @Test("Relative DSL -2w resolves to 14 days before")
    func minus2w() throws {
        let r = try CLIBridge.DateParsing.parse("-2w", now: ref(), calendar: calendar)
        let comps = calendar.dateComponents([.month, .day], from: r.date)
        #expect(comps.month == 4); #expect(comps.day == 28)
    }

    @Test("Unparseable input throws validationFailed")
    func unparseable() {
        #expect(throws: LillistError.self) {
            _ = try CLIBridge.DateParsing.parse("zorp", now: Date(), calendar: Calendar(identifier: .gregorian))
        }
    }
}
