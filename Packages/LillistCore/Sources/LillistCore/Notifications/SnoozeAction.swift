import Foundation

/// A user-facing snooze choice. Value type so the registry stays Sendable.
///
/// Design Section 4: "`SnoozeAction` value type: `{id, displayName,
/// compute: (NotificationSpec, deliveredAt) -> Date}`."
public struct SnoozeAction: Sendable {
    public typealias Compute = @Sendable (NotificationSpecStore.SpecRecord, Date) -> Date

    public let id: String
    public let displayName: String
    public let compute: Compute

    public init(id: String, displayName: String, compute: @escaping Compute) {
        self.id = id
        self.displayName = displayName
        self.compute = compute
    }
}

extension SnoozeAction {
    /// Ten-minute snooze (relative to delivery time).
    public static let tenMinutes = SnoozeAction(
        id: "snooze.10m",
        displayName: "Snooze 10 min"
    ) { _, deliveredAt in
        deliveredAt.addingTimeInterval(600)
    }

    /// One-hour snooze (relative to delivery time).
    public static let oneHour = SnoozeAction(
        id: "snooze.1h",
        displayName: "Snooze 1 hour"
    ) { _, deliveredAt in
        deliveredAt.addingTimeInterval(3600)
    }

    /// Snooze until the next morning at the user's default all-day notification time.
    /// Used by `SnoozeRegistry` with `AppPreferences.defaultAllDayHour/Minute`.
    public static func tomorrowMorning(hour: Int, minute: Int, timeZone: TimeZone) -> SnoozeAction {
        SnoozeAction(
            id: "snooze.tomorrow",
            displayName: "Snooze until tomorrow morning"
        ) { _, deliveredAt in
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = timeZone
            let tomorrow = cal.date(byAdding: .day, value: 1, to: deliveredAt) ?? deliveredAt
            var components = cal.dateComponents([.year, .month, .day], from: tomorrow)
            components.hour = hour
            components.minute = minute
            components.second = 0
            return cal.date(from: components) ?? deliveredAt
        }
    }
}
