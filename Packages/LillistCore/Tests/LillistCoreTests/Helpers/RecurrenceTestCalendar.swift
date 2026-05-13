import Foundation

/// Deterministic `Calendar` + helpers for recurrence tests.
///
/// All recurrence math is calendar-aware (DST-correct, month-length-aware).
/// Tests pin to a specific timezone to keep expectations stable across CI machines.
enum RecurrenceTestCalendar {
    /// Pacific Time — chosen because it has clean DST transitions to assert against.
    static let pacific: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        c.firstWeekday = 2
        return c
    }()

    /// UTC — used when the test doesn't care about wall-clock semantics
    /// but does care about deterministic Date arithmetic.
    static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }()

    /// Builds a `Date` in `calendar`'s timezone from explicit components.
    static func date(
        in calendar: Calendar = Self.pacific,
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = hour
        c.minute = minute
        c.second = 0
        return calendar.date(from: c)!
    }
}
