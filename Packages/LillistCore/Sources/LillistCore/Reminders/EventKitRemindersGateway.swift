@preconcurrency import EventKit
import Foundation

/// EventKit-backed ``RemindersGateway``. Confines a single `EKEventStore`
/// inside an `actor` and only ever returns Sendable DTOs, so EventKit's
/// non-Sendable types never cross the isolation boundary.
///
/// Deployment targets (iOS 18 / macOS 15) mean the iOS 17+/macOS 14+ full
/// access API is available unconditionally — no `#available` gate needed.
public actor EventKitRemindersGateway: RemindersGateway {
    private let store = EKEventStore()

    public init() {}

    public func authorization() -> RemindersAuthorization {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            return .authorized
        case .notDetermined:
            return .notDetermined
        default:
            // .denied / .restricted / .writeOnly all mean "can't read the queue".
            return .denied
        }
    }

    @discardableResult
    public func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToReminders()
        } catch {
            return false
        }
    }

    public func lists() throws -> [ReminderListInfo] {
        store.calendars(for: .reminder)
            .map { ReminderListInfo(id: $0.calendarIdentifier, title: $0.title) }
    }

    public func items(inListID listID: String) async throws -> [ReminderItem] {
        guard let calendar = store.calendar(withIdentifier: listID) else { return [] }
        let predicate = store.predicateForReminders(in: [calendar])
        // Map to Sendable DTOs *inside* the completion handler so the
        // non-Sendable `[EKReminder]` never crosses the continuation boundary.
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map(Self.makeItem))
            }
        }
    }

    /// Pure EKReminder → DTO projection. `nonisolated static` so the
    /// (non-isolated) fetch completion handler can call it without capturing
    /// actor state.
    private nonisolated static func makeItem(from reminder: EKReminder) -> ReminderItem {
        let components = reminder.dueDateComponents
        return ReminderItem(
            id: reminder.calendarItemExternalIdentifier,
            title: reminder.title ?? "",
            notes: reminder.notes,
            dueDate: components.flatMap { Calendar.current.date(from: $0) },
            dueHasTime: components?.hour != nil,
            isCompleted: reminder.isCompleted
        )
    }

    public func remove(itemID: String) throws {
        // `calendarItems(withExternalIdentifier:)` can return more than one
        // match (recurrence/iCloud dupes); remove every reminder it yields.
        let matches = store.calendarItems(withExternalIdentifier: itemID)
        for case let reminder as EKReminder in matches {
            try store.remove(reminder, commit: false)
        }
        try store.commit()
    }
}
