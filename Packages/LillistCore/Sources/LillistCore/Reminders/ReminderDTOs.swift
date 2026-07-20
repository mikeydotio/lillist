import Foundation

/// A Reminders.app list (an `EKCalendar` whose entity type is reminder),
/// reduced to the Sendable fields Lillist needs. `id` is the
/// `EKCalendar.calendarIdentifier`.
public struct ReminderListInfo: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    /// The owning account's `EKSource.sourceIdentifier` — stable grouping key
    /// for lists that belong to the same account (iCloud, a Google/CalDAV
    /// account, …).
    public let accountID: String
    /// The owning account's display name (`EKSource.title`), e.g. "iCloud".
    public let accountName: String
    /// Count of incomplete reminders in this list — exactly what a drain of
    /// this list would import.
    public let incompleteCount: Int

    public init(
        id: String,
        title: String,
        accountID: String,
        accountName: String,
        incompleteCount: Int
    ) {
        self.id = id
        self.title = title
        self.accountID = accountID
        self.accountName = accountName
        self.incompleteCount = incompleteCount
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
