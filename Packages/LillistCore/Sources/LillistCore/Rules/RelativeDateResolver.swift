import Foundation

/// Resolves a `RelativeDate` to an absolute `Date` using a supplied `now`
/// and `Calendar`. Pure utility — no shared state, safe to call from any
/// isolation context.
public enum RelativeDateResolver {
    public static func resolve(
        _ value: RelativeDate,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        switch value {
        case .today:
            return startOfToday
        case .tomorrow:
            return calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
        case .yesterday:
            return calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        case .daysFromNow(let n):
            return calendar.date(byAdding: .day, value: n, to: startOfToday) ?? startOfToday
        case .weeksFromNow(let n):
            // Saturate the week→day multiply so a pathological decoded count
            // (e.g. Int.max from a corrupt import) never traps. Calendar then
            // returns nil for an out-of-range day count and we fall back to
            // start-of-today.
            let (days, overflow) = n.multipliedReportingOverflow(by: 7)
            let safeDays = overflow ? (n > 0 ? Int.max : Int.min) : days
            return calendar.date(byAdding: .day, value: safeDays, to: startOfToday) ?? startOfToday
        case .startOfWeek:
            var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            comps.weekday = calendar.firstWeekday
            return calendar.date(from: comps) ?? startOfToday
        case .endOfWeek:
            var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            comps.weekday = calendar.firstWeekday
            guard let start = calendar.date(from: comps) else { return startOfToday }
            let endOfWeekDay = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            return Self.endOfDay(for: endOfWeekDay, calendar: calendar)
        case .startOfMonth:
            var comps = calendar.dateComponents([.year, .month], from: now)
            comps.day = 1
            return calendar.date(from: comps) ?? startOfToday
        case .endOfMonth:
            var comps = calendar.dateComponents([.year, .month], from: now)
            comps.day = 1
            guard let firstOfMonth = calendar.date(from: comps) else { return startOfToday }
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: firstOfMonth) ?? firstOfMonth
            let lastOfMonth = calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? firstOfMonth
            return Self.endOfDay(for: lastOfMonth, calendar: calendar)
        }
    }

    /// 23:59:59 on the same day as `date`.
    static func endOfDay(for date: Date, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        var comps = DateComponents()
        comps.day = 1
        comps.second = -1
        return calendar.date(byAdding: comps, to: startOfDay) ?? startOfDay
    }
}
