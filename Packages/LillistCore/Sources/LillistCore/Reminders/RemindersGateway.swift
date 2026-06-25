import Foundation

/// Boundary protocol over Reminders.app (EventKit). It returns only Sendable
/// value DTOs, so the importer, the settings UI, and tests never touch
/// EventKit types. The production implementation is
/// ``EventKitRemindersGateway``; tests use an in-memory fake.
public protocol RemindersGateway: Sendable {
    /// Current authorization for full Reminders access.
    func authorization() async -> RemindersAuthorization

    /// Prompt for full Reminders access. A no-op beyond the first decision;
    /// returns whether access is granted once the prompt resolves.
    @discardableResult
    func requestAccess() async -> Bool

    /// All reminder lists the user owns, by title.
    func lists() async throws -> [ReminderListInfo]

    /// Every reminder in the given list, regardless of completion state.
    func items(inListID listID: String) async throws -> [ReminderItem]

    /// Permanently remove a reminder by its external identifier.
    func remove(itemID: String) async throws
}
