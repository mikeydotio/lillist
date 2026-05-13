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
            self.interval = interval
            self.byDay = byDay
            self.byMonthDay = byMonthDay
            self.bySetPos = bySetPos
            self.count = count
            self.until = until
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
