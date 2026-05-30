import Foundation

/// Pure-Swift expansion of a `RecurrenceRule` into a stream of occurrence dates.
///
/// Calendar-aware throughout: uses `Calendar.date(byAdding:)` rather than
/// `Date.addingTimeInterval`, so DST transitions preserve wall-clock time
/// (design Section 8). `byMonthDay = 31` skips short months rather than
/// coercing to the 30th (design Section 8).
public enum RecurrenceExpander {

    /// Returns up to `count` occurrences strictly after `seed`, respecting
    /// the rule's `count` and `until` caps.
    public static func nextOccurrences(
        after seed: Date,
        rule: RecurrenceRule.CalendarRule,
        calendar: Calendar,
        count: Int
    ) -> [Date] {
        guard count > 0 else { return [] }
        var out: [Date] = []
        var cursor = seed
        let hardCap = rule.count.map { min($0, count) } ?? count

        while out.count < hardCap {
            guard let next = step(from: cursor, rule: rule, calendar: calendar) else {
                break
            }
            if let until = rule.until, next > until { break }
            out.append(next)
            cursor = next
        }
        return out
    }

    /// Computes the next occurrence after `completedAt` for an
    /// `.afterCompletion` rule.
    public static func nextAfterCompletion(
        completedAt: Date,
        rule: RecurrenceRule.AfterCompletionRule
    ) -> Date {
        completedAt.addingTimeInterval(rule.interval)
    }

    // MARK: - Frequency dispatch

    private static func step(
        from previous: Date,
        rule: RecurrenceRule.CalendarRule,
        calendar: Calendar
    ) -> Date? {
        switch rule.freq {
        case .daily:
            let n = max(1, rule.interval)
            return calendar.date(byAdding: .day, value: n, to: previous)
        case .weekly:
            return weeklyStep(from: previous, rule: rule, calendar: calendar)
        case .monthly:
            return monthlyStep(from: previous, rule: rule, calendar: calendar)
        case .yearly:
            return yearlyStep(from: previous, rule: rule, calendar: calendar)
        }
    }

    private static func weeklyStep(
        from previous: Date,
        rule: RecurrenceRule.CalendarRule,
        calendar: Calendar
    ) -> Date? {
        let n = max(1, rule.interval)
        guard let byDay = rule.byDay, byDay.isEmpty == false else {
            return calendar.date(byAdding: .weekOfYear, value: n, to: previous)
        }
        let sortedDays = byDay.sorted { $0.calendarComponent < $1.calendarComponent }
        let previousWeekday = calendar.component(.weekday, from: previous)
        if let next = sortedDays.first(where: { $0.calendarComponent > previousWeekday }) {
            let delta = next.calendarComponent - previousWeekday
            return calendar.date(byAdding: .day, value: delta, to: previous)
        }
        let firstNext = sortedDays.first!
        let daysToEndOfWeek = 7 - previousWeekday + firstNext.calendarComponent
        let totalDays = daysToEndOfWeek + 7 * (n - 1)
        return calendar.date(byAdding: .day, value: totalDays, to: previous)
    }

    private static func monthlyStep(
        from previous: Date,
        rule: RecurrenceRule.CalendarRule,
        calendar: Calendar
    ) -> Date? {
        if let byDay = rule.byDay, byDay.isEmpty == false,
           let bySetPos = rule.bySetPos, bySetPos.isEmpty == false {
            return monthlyStepBySetPos(
                from: previous,
                byDay: byDay,
                bySetPos: bySetPos,
                interval: rule.interval,
                calendar: calendar
            )
        }
        let n = max(1, rule.interval)
        let targetDays = rule.byMonthDay ?? [calendar.component(.day, from: previous)]
        var monthOffset = 0
        while monthOffset <= 12 * n + 1 {
            guard let monthStart = calendar.date(byAdding: .month, value: monthOffset, to: previous) else {
                return nil
            }
            if monthOffset > 0 && monthOffset % n != 0 {
                monthOffset += 1
                continue
            }
            let candidates = targetDays.compactMap { day -> Date? in
                composeDate(in: monthStart, day: day, time: previous, calendar: calendar)
            }.sorted()
            if let next = candidates.first(where: { $0 > previous }) {
                return next
            }
            monthOffset += 1
        }
        return nil
    }

    private static func monthlyStepBySetPos(
        from previous: Date,
        byDay: [Weekday],
        bySetPos: [Int],
        interval: Int,
        calendar: Calendar
    ) -> Date? {
        let n = max(1, interval)
        var monthOffset = 0
        while monthOffset <= 12 * n + 1 {
            guard let monthAnchor = calendar.date(byAdding: .month, value: monthOffset, to: previous) else {
                return nil
            }
            if monthOffset > 0 && monthOffset % n != 0 {
                monthOffset += 1
                continue
            }
            let candidates = candidateDates(
                inMonthOf: monthAnchor,
                weekdays: byDay,
                timeOf: previous,
                calendar: calendar
            ).sorted()
            let selected = bySetPos.compactMap { pos -> Date? in
                let idx = pos > 0 ? pos - 1 : candidates.count + pos
                return candidates.indices.contains(idx) ? candidates[idx] : nil
            }.sorted()
            if let next = selected.first(where: { $0 > previous }) {
                return next
            }
            monthOffset += 1
        }
        return nil
    }

    private static func candidateDates(
        inMonthOf monthAnchor: Date,
        weekdays: [Weekday],
        timeOf timeSource: Date,
        calendar: Calendar
    ) -> [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: monthAnchor) else { return [] }
        let weekdayValues = Set(weekdays.map(\.calendarComponent))
        let timeComps = calendar.dateComponents([.hour, .minute, .second], from: timeSource)
        var monthStartComps = calendar.dateComponents([.year, .month], from: monthAnchor)
        var out: [Date] = []
        for day in range {
            monthStartComps.day = day
            monthStartComps.hour = timeComps.hour
            monthStartComps.minute = timeComps.minute
            monthStartComps.second = timeComps.second
            guard let d = calendar.date(from: monthStartComps) else { continue }
            if weekdayValues.contains(calendar.component(.weekday, from: d)) {
                out.append(d)
            }
        }
        return out
    }

    /// Builds a date in `monthAnchor`'s year+month, using `day` for day-of-month
    /// and `time`'s hour/minute/second. Returns `nil` if `day` doesn't exist in
    /// that month (e.g. Feb 31), implementing the skip-month rule from design
    /// Section 8.
    private static func composeDate(
        in monthAnchor: Date,
        day: Int,
        time: Date,
        calendar: Calendar
    ) -> Date? {
        var comps = calendar.dateComponents([.year, .month], from: monthAnchor)
        let timeComps = calendar.dateComponents([.hour, .minute, .second], from: time)
        comps.day = day
        comps.hour = timeComps.hour
        comps.minute = timeComps.minute
        comps.second = timeComps.second
        guard
            let range = calendar.range(of: .day, in: .month, for: monthAnchor),
            range.contains(day)
        else {
            return nil
        }
        return calendar.date(from: comps)
    }

    private static func yearlyStep(
        from previous: Date,
        rule: RecurrenceRule.CalendarRule,
        calendar: Calendar
    ) -> Date? {
        let month = calendar.component(.month, from: previous)
        let day = calendar.component(.day, from: previous)
        let hour = calendar.component(.hour, from: previous)
        let minute = calendar.component(.minute, from: previous)
        let second = calendar.component(.second, from: previous)
        let n = max(1, rule.interval)
        var year = calendar.component(.year, from: previous) + n

        for _ in 0..<40 {
            var c = DateComponents()
            c.year = year
            c.month = month
            c.day = day
            c.hour = hour
            c.minute = minute
            c.second = second
            if let date = calendar.date(from: c),
               calendar.component(.day, from: date) == day,
               calendar.component(.month, from: date) == month {
                return date
            }
            year += n
        }
        return nil
    }
}
