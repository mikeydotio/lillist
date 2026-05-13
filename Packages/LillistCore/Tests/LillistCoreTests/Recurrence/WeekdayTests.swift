import Testing
@testable import LillistCore

@Suite("Weekday")
struct WeekdayTests {
    @Test("Raw values are RRULE-stable codes")
    func rawValues() {
        #expect(Weekday.monday.rawValue == "MO")
        #expect(Weekday.tuesday.rawValue == "TU")
        #expect(Weekday.wednesday.rawValue == "WE")
        #expect(Weekday.thursday.rawValue == "TH")
        #expect(Weekday.friday.rawValue == "FR")
        #expect(Weekday.saturday.rawValue == "SA")
        #expect(Weekday.sunday.rawValue == "SU")
    }

    @Test("All cases enumerable")
    func allCases() {
        #expect(Weekday.allCases.count == 7)
    }

    @Test("calendarComponent maps to Calendar's Sunday-first 1...7")
    func calendarComponentMapping() {
        #expect(Weekday.sunday.calendarComponent == 1)
        #expect(Weekday.monday.calendarComponent == 2)
        #expect(Weekday.tuesday.calendarComponent == 3)
        #expect(Weekday.wednesday.calendarComponent == 4)
        #expect(Weekday.thursday.calendarComponent == 5)
        #expect(Weekday.friday.calendarComponent == 6)
        #expect(Weekday.saturday.calendarComponent == 7)
    }

    @Test("Round-trip from calendarComponent")
    func fromCalendarComponent() {
        for d in Weekday.allCases {
            #expect(Weekday(calendarComponent: d.calendarComponent) == d)
        }
    }

    @Test("Invalid calendarComponent returns nil")
    func invalidCalendarComponent() {
        #expect(Weekday(calendarComponent: 0) == nil)
        #expect(Weekday(calendarComponent: 8) == nil)
    }
}
