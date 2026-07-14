import Foundation

/// Renders a task's schedule — its deadline (or, failing that, its start date)
/// plus any recurrence — into the single compact line shown on the task detail
/// card, e.g. `Due tomorrow at 5 PM (Every month)`.
///
/// The deadline drives the phrasing; when there is no deadline the start date
/// is used with a `Starts …` lead-in; when neither exists a neutral
/// `No due date` placeholder is returned. A repeating task appends its
/// `RecurrenceSummaryFormatter` string in parentheses.
///
/// Relative day words (`yesterday` / `today` / `tomorrow`) are used only within
/// one calendar day of `now`; beyond that the date renders absolutely. That
/// keeps the output stable for callers whose reference date is far from the
/// task date (notably the fixed-epoch snapshot fixtures).
///
/// `nonisolated` static API so non-`MainActor` callers (tests, background work)
/// can format without crossing the isolation boundary.
public enum DueLineFormatter {

    /// Formats the compact schedule line for a task.
    ///
    /// - Parameters:
    ///   - deadline: The task's deadline, if any.
    ///   - deadlineHasTime: Whether `deadline` carries a meaningful time.
    ///   - start: The task's start date, used only when `deadline` is `nil`.
    ///   - startHasTime: Whether `start` carries a meaningful time.
    ///   - recurrence: The structured recurrence summary; `.never` adds no suffix.
    ///   - now: The reference "today" for relative phrasing (injectable for tests).
    ///   - calendar: Calendar used for day/minute math (injectable for tests).
    ///   - locale: Locale for wording and date/time rendering.
    public static func string(
        deadline: Date?,
        deadlineHasTime: Bool,
        start: Date?,
        startHasTime: Bool,
        recurrence: RecurrenceSummary,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let base: String
        if let deadline {
            base = phrase(
                lead: .due, date: deadline, hasTime: deadlineHasTime,
                now: now, calendar: calendar, locale: locale
            )
        } else if let start {
            base = phrase(
                lead: .starts, date: start, hasTime: startHasTime,
                now: now, calendar: calendar, locale: locale
            )
        } else {
            return String(localized: "No due date", bundle: .module, locale: locale)
        }

        guard recurrence != .never else { return base }
        // The parenthetical wraps two already-localized fragments; the brackets
        // are punctuation, not translatable phrasing, so they stay literal.
        let rec = RecurrenceSummaryFormatter.string(for: recurrence, locale: locale)
        return "\(base) (\(rec))"
    }

    // MARK: - Internals

    private enum Lead { case due, starts }

    private static func phrase(
        lead: Lead,
        date: Date,
        hasTime: Bool,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        let when = relativeOrAbsoluteDay(date, now: now, calendar: calendar, locale: locale)
        guard hasTime else {
            switch lead {
            case .due: return String(localized: "Due \(when)", bundle: .module, locale: locale)
            case .starts: return String(localized: "Starts \(when)", bundle: .module, locale: locale)
            }
        }
        let time = timeString(date, calendar: calendar, locale: locale)
        switch lead {
        case .due: return String(localized: "Due \(when) at \(time)", bundle: .module, locale: locale)
        case .starts: return String(localized: "Starts \(when) at \(time)", bundle: .module, locale: locale)
        }
    }

    /// `yesterday` / `today` / `tomorrow` within one calendar day, else an
    /// absolute date (`May 28`, or `May 28, 2026` across a year boundary).
    private static func relativeOrAbsoluteDay(
        _ date: Date,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        let startOfNow = calendar.startOfDay(for: now)
        let startOfDate = calendar.startOfDay(for: date)
        let dayDelta = calendar.dateComponents([.day], from: startOfNow, to: startOfDate).day ?? 0

        switch dayDelta {
        case 0: return String(localized: "today", bundle: .module, locale: locale)
        case 1: return String(localized: "tomorrow", bundle: .module, locale: locale)
        case -1: return String(localized: "yesterday", bundle: .module, locale: locale)
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            var style = baseStyle(calendar: calendar, locale: locale).month(.abbreviated).day()
            if !sameYear { style = style.year() }
            return date.formatted(style)
        }
    }

    /// `5 PM` when the minute is zero, otherwise `5:30 PM` (locale-driven).
    private static func timeString(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        let minuteIsZero = calendar.component(.minute, from: date) == 0
        let base = baseStyle(calendar: calendar, locale: locale)
        let style = minuteIsZero ? base.hour() : base.hour().minute()
        return date.formatted(style)
    }

    /// A `Date.FormatStyle` pinned to the injected calendar's time zone, so
    /// rendering never silently depends on the process's current time zone.
    private static func baseStyle(calendar: Calendar, locale: Locale) -> Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }
}
