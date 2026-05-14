import Foundation

/// The active set of snooze actions, configurable at runtime.
///
/// Defaults registered at init per design Section 4: `tenMinutes`,
/// `oneHour`, `tomorrowMorning` (using `AppPreferences.defaultAllDayHour:Minute`).
public actor SnoozeRegistry {
    private var _actions: [SnoozeAction]

    public init(defaultAllDayHour: Int, defaultAllDayMinute: Int, timeZone: TimeZone) {
        self._actions = [
            .tenMinutes,
            .oneHour,
            .tomorrowMorning(hour: defaultAllDayHour, minute: defaultAllDayMinute, timeZone: timeZone)
        ]
    }

    public var actions: [SnoozeAction] { _actions }

    /// Register a new action, or replace one with the same `id`.
    public func register(_ action: SnoozeAction) {
        if let idx = _actions.firstIndex(where: { $0.id == action.id }) {
            _actions[idx] = action
        } else {
            _actions.append(action)
        }
    }

    public func action(id: String) -> SnoozeAction? {
        _actions.first { $0.id == id }
    }
}
