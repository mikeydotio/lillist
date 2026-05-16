import Foundation

/// Build a `Date` whose date components match today and whose hour /
/// minute match the supplied values. Used by Preferences DatePickers
/// that bind to (Int16 hour, Int16 minute) prefs columns.
///
/// Previously duplicated verbatim in iOS `NotificationsSection.swift`
/// and macOS `NotificationsPane.swift`. Plan 14 lifts to LillistUI.
public enum HourMinuteDate {
    public static func date(hour: Int, minute: Int, calendar: Calendar = .current) -> Date {
        var c = calendar.dateComponents([.year, .month, .day], from: Date())
        c.hour = hour
        c.minute = minute
        return calendar.date(from: c) ?? Date()
    }
}
