import Foundation

/// A recurrence specification for a `Series`.
///
/// Two variants per design Section 2:
///   - `.calendar` — RRULE-subset (`freq`, `interval`, `byDay`, `byMonthDay`,
///     `bySetPos`, optional `count` and `until`).
///   - `.afterCompletion` — fixed `TimeInterval` from the moment the previous
///     instance was closed.
///
/// JSON-encoded into `Series.ruleJSON`. A `type` discriminator distinguishes the
/// two variants; never rename or remove discriminator values.
public enum RecurrenceRule: Codable, Sendable, Equatable {
    case calendar(CalendarRule)
    case afterCompletion(AfterCompletionRule)

    public enum Frequency: String, Codable, Sendable {
        case daily, weekly, monthly, yearly
    }

    public struct CalendarRule: Codable, Sendable, Equatable {
        public var freq: Frequency
        public var interval: Int
        public var byDay: [Weekday]?
        public var byMonthDay: [Int]?
        public var bySetPos: [Int]?
        public var count: Int?
        public var until: Date?

        public init(
            freq: Frequency,
            interval: Int,
            byDay: [Weekday]? = nil,
            byMonthDay: [Int]? = nil,
            bySetPos: [Int]? = nil,
            count: Int? = nil,
            until: Date? = nil
        ) {
            self.freq = freq
            self.interval = Self.normalizedInterval(interval)
            self.byDay = byDay
            self.byMonthDay = byMonthDay
            self.bySetPos = bySetPos
            self.count = count
            self.until = until
        }

        private enum CodingKeys: String, CodingKey {
            case freq, interval, byDay, byMonthDay, bySetPos, count, until
        }

        /// Hand-written decoder so untrusted JSON (CloudKit / Importer / CLI)
        /// funnels through the same interval normalization as the memberwise
        /// `init`. The synthesized decoder would assign the raw `interval`
        /// directly, leaving a `0`/negative value that crashes the expander.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.freq = try c.decode(Frequency.self, forKey: .freq)
            self.interval = Self.normalizedInterval(try c.decode(Int.self, forKey: .interval))
            self.byDay = try c.decodeIfPresent([Weekday].self, forKey: .byDay)
            self.byMonthDay = try c.decodeIfPresent([Int].self, forKey: .byMonthDay)
            self.bySetPos = try c.decodeIfPresent([Int].self, forKey: .bySetPos)
            self.count = try c.decodeIfPresent(Int.self, forKey: .count)
            self.until = try c.decodeIfPresent(Date.self, forKey: .until)
        }

        /// The largest recurrence interval the engine will honor. The recurrence
        /// editor bounds its stepper to `1...365`, so no first-party rule ever
        /// approaches this; it exists purely as a backstop for *untrusted*
        /// `interval` values (CloudKit decode / Importer / CLI). Left unbounded,
        /// a huge positive interval overflows the expander's `12 * n + 1`
        /// month-scan bound (a trap) or forces an `O(interval)` month scan (an
        /// effective hang) — the same untrusted-input-crashes-the-expander class
        /// the low-side clamp closes, from the high side (rec-1).
        static let maxInterval = 1000

        /// Clamps a raw interval into the honored `1...maxInterval` range,
        /// **without** logging. The expander calls this as silent
        /// defense-in-depth at every step/modulo site, so even a rule whose
        /// `interval` field is forced out of range *after* construction can
        /// neither divide-by-zero, integer-overflow, nor loop-trap (rec-2).
        static func clampedInterval(_ raw: Int) -> Int {
            min(maxInterval, max(1, raw))
        }

        /// Clamps an interval to the honored `1...maxInterval` range, logging a
        /// warning when it has to change the value. An interval of `0`
        /// divide-by-zero-crashes the monthly expander and loop-traps the
        /// daily/weekly steps; a negative interval walks backwards forever; a
        /// huge positive interval overflows/hangs the month scan. We normalize
        /// rather than throw so a single corrupt sync record can't strip
        /// recurrence off the series entirely (rec-1).
        private static func normalizedInterval(_ raw: Int) -> Int {
            let clamped = clampedInterval(raw)
            if clamped != raw {
                RecurrenceLog.normalization.warning(
                    "CalendarRule interval \(raw, privacy: .public) out of range; clamped to \(clamped, privacy: .public)"
                )
            }
            return clamped
        }
    }

    public struct AfterCompletionRule: Codable, Sendable, Equatable {
        public var interval: TimeInterval
        public init(interval: TimeInterval) {
            self.interval = interval
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case rule
    }

    private enum RuleType: String, Codable {
        case calendar
        case afterCompletion
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(RuleType.self, forKey: .type)
        switch type {
        case .calendar:
            self = .calendar(try c.decode(CalendarRule.self, forKey: .rule))
        case .afterCompletion:
            self = .afterCompletion(try c.decode(AfterCompletionRule.self, forKey: .rule))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .calendar(let r):
            try c.encode(RuleType.calendar, forKey: .type)
            try c.encode(r, forKey: .rule)
        case .afterCompletion(let r):
            try c.encode(RuleType.afterCompletion, forKey: .type)
            try c.encode(r, forKey: .rule)
        }
    }
}
