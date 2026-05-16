import Foundation
import LillistCore

/// Mutable view-model wrapper around an optional `RecurrenceRule`.
/// Designed to be held in `@State` and read/written by SwiftUI form
/// controls. `build()` synthesizes a `RecurrenceRule` on commit.
///
/// Plan 11 introduces the recurrence pattern editor to v1 (originally
/// scheduled for v2 per design Section 10).
public struct RecurrenceEditorViewModel: Equatable {
    public enum Mode: Hashable, Sendable, CaseIterable {
        case calendar
        case afterCompletion
    }

    public var repeats: Bool
    public var mode: Mode
    public var freq: RecurrenceRule.Frequency
    public var interval: Int
    public var byDay: Set<Weekday>
    public var byMonthDay: Set<Int>
    public var bySetPos: Set<Int>
    public var count: Int?
    public var until: Date?
    public var afterCompletionSeconds: TimeInterval

    public init(rule: RecurrenceRule?) {
        switch rule {
        case .none:
            self.repeats = false
            self.mode = .calendar
            self.freq = .daily
            self.interval = 1
            self.byDay = []
            self.byMonthDay = []
            self.bySetPos = []
            self.count = nil
            self.until = nil
            self.afterCompletionSeconds = 86_400
        case .some(.calendar(let c)):
            self.repeats = true
            self.mode = .calendar
            self.freq = c.freq
            self.interval = c.interval
            self.byDay = Set(c.byDay ?? [])
            self.byMonthDay = Set(c.byMonthDay ?? [])
            self.bySetPos = Set(c.bySetPos ?? [])
            self.count = c.count
            self.until = c.until
            self.afterCompletionSeconds = 86_400
        case .some(.afterCompletion(let a)):
            self.repeats = true
            self.mode = .afterCompletion
            self.freq = .daily
            self.interval = 1
            self.byDay = []
            self.byMonthDay = []
            self.bySetPos = []
            self.count = nil
            self.until = nil
            self.afterCompletionSeconds = a.interval
        }
    }

    /// Synthesize a `RecurrenceRule` from the current view-model state, or
    /// `nil` when `repeats == false`.
    public func build() -> RecurrenceRule? {
        guard repeats else { return nil }
        switch mode {
        case .calendar:
            // Preserve natural Mon→Sun ordering for byDay (Weekday.allCases is
            // declared Monday-first), rather than alphabetizing by RRULE
            // shortcode.
            let dayList: [Weekday]? = byDay.isEmpty
                ? nil
                : Weekday.allCases.filter { byDay.contains($0) }
            return .calendar(RecurrenceRule.CalendarRule(
                freq: freq,
                interval: max(1, interval),
                byDay: dayList,
                byMonthDay: byMonthDay.isEmpty ? nil : byMonthDay.sorted(),
                bySetPos: bySetPos.isEmpty ? nil : bySetPos.sorted(),
                count: count,
                until: until
            ))
        case .afterCompletion:
            return .afterCompletion(RecurrenceRule.AfterCompletionRule(interval: afterCompletionSeconds))
        }
    }
}
