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

        /// Clamps an interval to the valid `>= 1` range. An interval of `0`
        /// divide-by-zero-crashes the monthly expander and loop-traps the
        /// daily/weekly steps; a negative interval walks backwards forever.
        /// We normalize rather than throw so a single corrupt sync record
        /// can't strip recurrence off the series entirely (rec-1).
        private static func normalizedInterval(_ raw: Int) -> Int {
            guard raw < 1 else { return raw }
            RecurrenceLog.normalization.warning(
                "CalendarRule interval \(raw, privacy: .public) out of range; clamped to 1"
            )
            return 1
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
