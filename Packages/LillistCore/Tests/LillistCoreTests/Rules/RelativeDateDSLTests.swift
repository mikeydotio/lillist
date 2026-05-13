import Foundation
import Testing
@testable import LillistCore

@Suite("RelativeDate DSL")
struct RelativeDateDSLTests {
    @Test("Keyword phrases parse")
    func keywords() throws {
        #expect(try RelativeDate.parse("today") == .today)
        #expect(try RelativeDate.parse("tomorrow") == .tomorrow)
        #expect(try RelativeDate.parse("yesterday") == .yesterday)
        #expect(try RelativeDate.parse("startOfWeek") == .startOfWeek)
        #expect(try RelativeDate.parse("endOfWeek") == .endOfWeek)
        #expect(try RelativeDate.parse("startOfMonth") == .startOfMonth)
        #expect(try RelativeDate.parse("endOfMonth") == .endOfMonth)
    }

    @Test("Keyword parsing is case-insensitive")
    func caseInsensitive() throws {
        #expect(try RelativeDate.parse("Today") == .today)
        #expect(try RelativeDate.parse("STARTOFWEEK") == .startOfWeek)
    }

    @Test("Offset forms parse")
    func offsets() throws {
        #expect(try RelativeDate.parse("+7d") == .daysFromNow(7))
        #expect(try RelativeDate.parse("-2d") == .daysFromNow(-2))
        #expect(try RelativeDate.parse("+0d") == .daysFromNow(0))
        #expect(try RelativeDate.parse("+3w") == .weeksFromNow(3))
        #expect(try RelativeDate.parse("-1w") == .weeksFromNow(-1))
    }

    @Test("Unsigned integer day count parses as +N days")
    func bareInteger() throws {
        #expect(try RelativeDate.parse("7d") == .daysFromNow(7))
        #expect(try RelativeDate.parse("2w") == .weeksFromNow(2))
    }

    @Test("Invalid strings throw validationFailed")
    func invalid() {
        #expect(throws: LillistError.self) { _ = try RelativeDate.parse("") }
        #expect(throws: LillistError.self) { _ = try RelativeDate.parse("nextMonday") }
        #expect(throws: LillistError.self) { _ = try RelativeDate.parse("+xd") }
        #expect(throws: LillistError.self) { _ = try RelativeDate.parse("7q") }
        #expect(throws: LillistError.self) { _ = try RelativeDate.parse("startOf") }
    }

    @Test("Codable round-trips every variant")
    func codable() throws {
        let cases: [RelativeDate] = [
            .today, .tomorrow, .yesterday,
            .daysFromNow(7), .daysFromNow(-3),
            .weeksFromNow(2), .weeksFromNow(-1),
            .startOfWeek, .endOfWeek, .startOfMonth, .endOfMonth
        ]
        for c in cases {
            let data = try JSONEncoder().encode(c)
            let decoded = try JSONDecoder().decode(RelativeDate.self, from: data)
            #expect(decoded == c)
        }
    }
}
