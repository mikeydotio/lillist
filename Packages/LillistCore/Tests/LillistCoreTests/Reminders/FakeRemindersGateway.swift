import Foundation
@testable import LillistCore

/// In-memory ``RemindersGateway`` for importer tests. A *data* fake — it
/// stores reminders and honors deletes; it never mocks importer behavior, so
/// it satisfies the no-mock-behavior testing rule (EventKit is the external
/// boundary it stands in for).
actor FakeRemindersGateway: RemindersGateway {
    private var auth: RemindersAuthorization
    private var lists_: [ReminderListInfo]
    private var itemsByList: [String: [ReminderItem]]
    /// Ids whose `remove` throws until cleared — simulates a failed delete
    /// (the create→delete crash window).
    private var failRemoveIDs: Set<String>
    private(set) var requestAccessCount = 0
    private(set) var removeCallCount = 0

    init(
        auth: RemindersAuthorization = .authorized,
        lists: [ReminderListInfo] = [],
        itemsByList: [String: [ReminderItem]] = [:],
        failRemoveIDs: Set<String> = []
    ) {
        self.auth = auth
        self.lists_ = lists
        self.itemsByList = itemsByList
        self.failRemoveIDs = failRemoveIDs
    }

    func authorization() -> RemindersAuthorization { auth }

    @discardableResult
    func requestAccess() -> Bool {
        requestAccessCount += 1
        auth = .authorized
        return true
    }

    func lists() -> [ReminderListInfo] { lists_ }

    func items(inListID listID: String) -> [ReminderItem] {
        itemsByList[listID] ?? []
    }

    func remove(itemID: String) throws {
        removeCallCount += 1
        if failRemoveIDs.contains(itemID) { throw FakeError.removeFailed }
        for (list, items) in itemsByList {
            itemsByList[list] = items.filter { $0.id != itemID }
        }
    }

    // MARK: Test introspection

    func remainingItems(inListID listID: String) -> [ReminderItem] {
        itemsByList[listID] ?? []
    }
    func setAuth(_ value: RemindersAuthorization) { auth = value }
    func clearFailRemove() { failRemoveIDs = [] }

    /// Marks an existing item completed in place, simulating the user
    /// completing a reminder in Reminders.app between two drain passes.
    func markCompleted(itemID: String, inListID listID: String) {
        guard let items = itemsByList[listID],
              let index = items.firstIndex(where: { $0.id == itemID })
        else { return }
        let original = items[index]
        itemsByList[listID]?[index] = ReminderItem(
            id: original.id,
            title: original.title,
            notes: original.notes,
            dueDate: original.dueDate,
            dueHasTime: original.dueHasTime,
            isCompleted: true
        )
    }

    enum FakeError: Error { case removeFailed }
}
