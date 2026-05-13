import Foundation

/// A day of the week, encoded as the two-letter RRULE code (`MO`..`SU`).
///
/// Raw values are persisted in `RecurrenceRule` JSON; never renumber.
public enum Weekday: String, CaseIterable, Codable, Sendable {
    case monday = "MO"
    case tuesday = "TU"
    case wednesday = "WE"
    case thursday = "TH"
    case friday = "FR"
    case saturday = "SA"
    case sunday = "SU"

    /// Apple `Calendar` uses Sunday=1...Saturday=7 regardless of `firstWeekday`.
    /// This property bridges Lillist's Monday-first ordering to that scheme
    /// for use with `DateComponents.weekday`.
    public var calendarComponent: Int {
        switch self {
        case .sunday:    return 1
        case .monday:    return 2
        case .tuesday:   return 3
        case .wednesday: return 4
        case .thursday:  return 5
        case .friday:    return 6
        case .saturday:  return 7
        }
    }

    /// Inverse of `calendarComponent`. Returns `nil` for out-of-range input.
    public init?(calendarComponent value: Int) {
        switch value {
        case 1: self = .sunday
        case 2: self = .monday
        case 3: self = .tuesday
        case 4: self = .wednesday
        case 5: self = .thursday
        case 6: self = .friday
        case 7: self = .saturday
        default: return nil
        }
    }
}
