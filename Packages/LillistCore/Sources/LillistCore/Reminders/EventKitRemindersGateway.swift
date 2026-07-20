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

    public func lists() async throws -> [ReminderListInfo] {
        let calendars = store.calendars(for: .reminder)
        guard !calendars.isEmpty else { return [] }

        // One fetch across every list, bucketed by calendar id, rather than
        // an EventKit round-trip per list.
        let counts = await incompleteCounts(for: calendars)
        return calendars
            .map { calendar in
                ReminderListInfo(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    accountID: calendar.source.sourceIdentifier,
                    accountName: calendar.source.title,
                    incompleteCount: counts[calendar.calendarIdentifier] ?? 0
                )
            }
            .sorted {
                $0.accountName != $1.accountName
                    ? $0.accountName < $1.accountName
                    : $0.title < $1.title
            }
    }

    private func incompleteCounts(for calendars: [EKCalendar]) async -> [String: Int] {
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: calendars
        )
        // Map to a Sendable count dictionary *inside* the completion handler
        // so the non-Sendable `[EKReminder]` never crosses the continuation
        // boundary.
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: Self.countByCalendar(reminders ?? []))
            }
        }
    }

    /// Pure EKReminder-list → per-calendar count projection. `nonisolated
    /// static` for the same reason as ``makeItem(from:)``: EventKit's fetch
    /// completion handler is non-isolated.
    private nonisolated static func countByCalendar(_ reminders: [EKReminder]) -> [String: Int] {
        reminders.reduce(into: [String: Int]()) { counts, reminder in
            guard let id = reminder.calendar?.calendarIdentifier else { return }
            counts[id, default: 0] += 1
        }
    }

    public func items(inListID listID: String) async throws -> [ReminderItem] {
        // A stale/unresolvable calendarIdentifier must not be indistinguishable
        // from a genuinely empty list — that conflation was issue #50's root
        // cause (silently reporting "Imported 0 tasks" for both). Throw instead
        // of returning [].
        guard let calendar = store.calendar(withIdentifier: listID) else {
            throw RemindersGatewayError.listUnavailable(id: listID)
        }
        let predicate = store.predicateForReminders(in: [calendar])
        // Map to Sendable DTOs *inside* the completion handler so the
        // non-Sendable `[EKReminder]` never crosses the continuation boundary.
        return try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                // `fetchReminders` passes nil on fetch failure — another silent
                // swallow this method used to turn into an empty result.
                guard let reminders else {
                    continuation.resume(throwing: RemindersGatewayError.fetchFailed(id: listID))
                    return
                }
                continuation.resume(returning: reminders.map(Self.makeItem))
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
