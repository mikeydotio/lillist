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
            return calendar.date(byAdding: .day, value: n * 7, to: startOfToday) ?? startOfToday
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
