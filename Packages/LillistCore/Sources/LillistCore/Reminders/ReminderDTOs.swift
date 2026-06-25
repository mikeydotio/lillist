import Foundation

/// A Reminders.app list (an `EKCalendar` whose entity type is reminder),
/// reduced to the Sendable fields Lillist needs. `id` is the
/// `EKCalendar.calendarIdentifier`.
public struct ReminderListInfo: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// A single reminder, reduced to Sendable value fields. `id` is the
/// `EKReminder.calendarItemExternalIdentifier` — stable across the
/// create→delete window and used as the dedup key.
public struct ReminderItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let notes: String?
    /// Resolved due date (`nil` for reminders with no due date).
    public let dueDate: Date?
    /// Whether the due date carries a time-of-day (vs. an all-day date).
    public let dueHasTime: Bool
    public let isCompleted: Bool

    public init(
        id: String,
        title: String,
        notes: String?,
        dueDate: Date?,
        dueHasTime: Bool,
        isCompleted: Bool
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.dueHasTime = dueHasTime
        self.isCompleted = isCompleted
    }
}

/// Coarse Reminders authorization state, decoupled from EventKit's enum so
/// callers (and the UI) never import EventKit.
public enum RemindersAuthorization: Sendable, Equatable {
    case notDetermined
    /// Denied or restricted — the queue can't be read.
    case denied
    /// Full access granted.
    case authorized
}
