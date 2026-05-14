import Foundation

extension CLIBridge {
    /// Parses date/time tokens for the CLI and Shortcuts.
    ///
    /// Supports four input shapes (in priority order):
    ///   1. ISO-8601 date+time (`2026-06-01T09:30:00`, with optional TZ).
    ///   2. ISO-8601 date (`2026-06-01`).
    ///   3. Plan-3 relative DSL (`today`, `+7d`, `-2w`, `startOfWeek`, etc.).
    ///   4. Natural-language phrases:
    ///        `tomorrow`, `yesterday`, `today`
    ///        `next <weekday>` / `last <weekday>` / `this <weekday>`
    ///        any of the above followed by an optional time clause:
    ///            ` <h>am`, ` <h>pm`, ` at <h>`, ` <h>:<mm>`, ` at <h>:<mm>`
    ///
    /// Returns the resolved `Date` plus a `hasTime` flag. Callers map
    /// `hasTime` onto `startHasTime` / `deadlineHasTime` per design Section 2.
    public enum DateParsing {
        public struct Resolved: Sendable, Equatable {
            public let date: Date
            public let hasTime: Bool
        }

        public static func parse(_ input: String, now: Date = Date(), calendar: Calendar = Calendar.current) throws -> Resolved {
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                throw LillistError.validationFailed([.init(field: "date", message: "empty input")])
            }

            // 1. ISO-8601 date+time. Construct the formatter per call —
            // ISO8601DateFormatter is not Sendable, so it cannot live as a
            // static under strict concurrency.
            let dateTimeFormatter = ISO8601DateFormatter()
            dateTimeFormatter.formatOptions = [.withInternetDateTime]
            if let d = dateTimeFormatter.date(from: trimmed) {
                return Resolved(date: d, hasTime: true)
            }
            // 2. ISO-8601 date only.
            if let d = isoDateOnly(from: trimmed, calendar: calendar) {
                return Resolved(date: d, hasTime: false)
            }

            // Split into base phrase and optional time clause.
            let (basePhrase, timePart) = splitTime(trimmed)

            let baseDate = try resolveBase(basePhrase, now: now, calendar: calendar)
            if let timePart {
                let withTime = try applyTime(timePart, to: baseDate, calendar: calendar)
                return Resolved(date: withTime, hasTime: true)
            } else {
                return Resolved(date: baseDate, hasTime: false)
            }
        }

        // MARK: - Base phrase

        static func resolveBase(_ phrase: String, now: Date, calendar: Calendar) throws -> Date {
            let lower = phrase.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

            switch lower {
            case "today": return startOfDay(now, calendar: calendar)
            case "tomorrow": return calendar.date(byAdding: .day, value: 1, to: startOfDay(now, calendar: calendar))!
            case "yesterday": return calendar.date(byAdding: .day, value: -1, to: startOfDay(now, calendar: calendar))!
            case "startofweek": return startOfWeek(now, calendar: calendar)
            case "endofweek": return endOfWeek(now, calendar: calendar)
            case "startofmonth": return startOfMonth(now, calendar: calendar)
            case "endofmonth": return endOfMonth(now, calendar: calendar)
            default: break
            }

            // Relative DSL: ±<n><unit>
            if let match = parseRelativeDSL(lower) {
                guard let d = calendar.date(byAdding: match.component, value: match.value, to: now) else {
                    throw LillistError.validationFailed([.init(field: "date", message: "could not compute relative date")])
                }
                return startOfDay(d, calendar: calendar)
            }

            // "next monday" / "last friday" / "this monday"
            if let weekdayDate = parseWeekdayPhrase(lower, now: now, calendar: calendar) {
                return weekdayDate
            }

            throw LillistError.validationFailed([.init(field: "date", message: "could not parse date phrase '\(phrase)'")])
        }

        // MARK: - Time clause

        static func splitTime(_ input: String) -> (base: String, time: String?) {
            // Look for ` at <time>` first.
            if let range = input.range(of: " at ", options: .caseInsensitive) {
                let base = String(input[..<range.lowerBound])
                let time = String(input[range.upperBound...])
                return (base, time)
            }
            // Trailing am/pm or H:MM token.
            let parts = input.split(separator: " ").map(String.init)
            if parts.count >= 2 {
                let last = parts.last!
                if looksLikeTimeToken(last) {
                    let base = parts.dropLast().joined(separator: " ")
                    return (base, last)
                }
            }
            return (input, nil)
        }

        static func looksLikeTimeToken(_ s: String) -> Bool {
            let lower = s.lowercased()
            if lower.hasSuffix("am") || lower.hasSuffix("pm") { return true }
            if lower.contains(":") { return true }
            return false
        }

        static func applyTime(_ time: String, to base: Date, calendar: Calendar) throws -> Date {
            let lower = time.lowercased()
            var hour = 0
            var minute = 0
            var isPM = false
            var explicitMeridiem = false

            var clean = lower
            if clean.hasSuffix("am") {
                clean = String(clean.dropLast(2))
                explicitMeridiem = true
            } else if clean.hasSuffix("pm") {
                clean = String(clean.dropLast(2))
                explicitMeridiem = true
                isPM = true
            }
            clean = clean.trimmingCharacters(in: .whitespaces)

            if clean.contains(":") {
                let parts = clean.split(separator: ":").map(String.init)
                guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else {
                    throw LillistError.validationFailed([.init(field: "time", message: "could not parse time '\(time)'")])
                }
                hour = h
                minute = m
            } else {
                guard let h = Int(clean) else {
                    throw LillistError.validationFailed([.init(field: "time", message: "could not parse time '\(time)'")])
                }
                hour = h
            }
            if explicitMeridiem && isPM && hour < 12 { hour += 12 }
            if explicitMeridiem && !isPM && hour == 12 { hour = 0 }

            let dateOnly = startOfDay(base, calendar: calendar)
            var comps = calendar.dateComponents([.year, .month, .day], from: dateOnly)
            comps.hour = hour
            comps.minute = minute
            comps.timeZone = calendar.timeZone
            guard let d = calendar.date(from: comps) else {
                throw LillistError.validationFailed([.init(field: "time", message: "could not assemble time")])
            }
            return d
        }

        // MARK: - Relative DSL

        struct RelativeMatch {
            let value: Int
            let component: Calendar.Component
        }

        static func parseRelativeDSL(_ s: String) -> RelativeMatch? {
            // Matches +Nd, -Nd, +Nw, -Nw, +Nm, -Nm, +Ny, -Ny.
            guard let first = s.first, first == "+" || first == "-" else { return nil }
            let body = s.dropFirst()
            guard let lastChar = body.last else { return nil }
            let numericPart = body.dropLast()
            guard let n = Int(numericPart) else { return nil }
            let signed = (first == "-") ? -n : n
            let component: Calendar.Component
            switch lastChar {
            case "d": component = .day
            case "w": component = .weekOfYear
            case "m": component = .month
            case "y": component = .year
            default: return nil
            }
            return RelativeMatch(value: signed, component: component)
        }

        // MARK: - Weekday phrases

        static let weekdayNames: [String: Int] = [
            "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
            "thursday": 5, "friday": 6, "saturday": 7
        ]

        static func parseWeekdayPhrase(_ s: String, now: Date, calendar: Calendar) -> Date? {
            let tokens = s.split(separator: " ").map(String.init)
            guard tokens.count == 2 else { return nil }
            let modifier = tokens[0]
            let name = tokens[1]
            guard let weekday = weekdayNames[name] else { return nil }

            let today = startOfDay(now, calendar: calendar)
            let todayWeekday = calendar.component(.weekday, from: today)
            switch modifier {
            case "next":
                var delta = weekday - todayWeekday
                if delta <= 0 { delta += 7 }
                return calendar.date(byAdding: .day, value: delta, to: today)
            case "last":
                var delta = weekday - todayWeekday
                if delta >= 0 { delta -= 7 }
                return calendar.date(byAdding: .day, value: delta, to: today)
            case "this":
                var delta = weekday - todayWeekday
                if delta < 0 { delta += 7 }
                return calendar.date(byAdding: .day, value: delta, to: today)
            default:
                return nil
            }
        }

        // MARK: - Calendar helpers

        static func startOfDay(_ d: Date, calendar: Calendar) -> Date {
            calendar.startOfDay(for: d)
        }
        static func startOfWeek(_ d: Date, calendar: Calendar) -> Date {
            let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)
            return calendar.date(from: comps) ?? d
        }
        static func endOfWeek(_ d: Date, calendar: Calendar) -> Date {
            let start = startOfWeek(d, calendar: calendar)
            return calendar.date(byAdding: .day, value: 6, to: start) ?? d
        }
        static func startOfMonth(_ d: Date, calendar: Calendar) -> Date {
            let comps = calendar.dateComponents([.year, .month], from: d)
            return calendar.date(from: comps) ?? d
        }
        static func endOfMonth(_ d: Date, calendar: Calendar) -> Date {
            let start = startOfMonth(d, calendar: calendar)
            var add = DateComponents()
            add.month = 1
            add.day = -1
            return calendar.date(byAdding: add, to: start) ?? d
        }

        // MARK: - Formatters

        /// Parse `yyyy-MM-dd` honoring the supplied calendar's time zone, so the
        /// resulting `Date` lands at midnight in that calendar's TZ rather than
        /// midnight UTC. Important for tests that pin the calendar to a non-UTC
        /// zone.
        static func isoDateOnly(from input: String, calendar: Calendar) -> Date? {
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = calendar.timeZone
            f.dateFormat = "yyyy-MM-dd"
            return f.date(from: input)
        }

    }
}
