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
    /// When true, `items(inListID:)` suspends until `releaseFetch()` is called.
    /// Simulates a slow EventKit fetch so a test can deterministically fire a
    /// second, concurrent `RemindersImporter` call while the first is still
    /// mid-drain (past `isDraining = true`, before it returns) — the only way
    /// to observe `.busy` without a race on wall-clock timing.
    private var holdFetch = false
    private var fetchWaiters: [CheckedContinuation<Void, Never>] = []

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

    /// Mirrors the production gateway's fixed behavior: an unresolvable list
    /// throws `.listUnavailable` rather than silently returning `[]`. "Known"
    /// means the key is present in `itemsByList` — including a key whose value
    /// is now `[]` because `remove` drained it, so a fully-drained list still
    /// reports `[]` (an empty completion), never `.listUnavailable`.
    func items(inListID listID: String) async throws -> [ReminderItem] {
        if holdFetch {
            await withCheckedContinuation { fetchWaiters.append($0) }
        }
        guard let items = itemsByList[listID] else {
            throw RemindersGatewayError.listUnavailable(id: listID)
        }
        return items
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

    func setHoldFetch(_ value: Bool) { holdFetch = value }
    /// Releases every `items(inListID:)` call currently suspended, and stops
    /// holding future calls.
    func releaseFetch() {
        holdFetch = false
        let waiters = fetchWaiters
        fetchWaiters = []
        for waiter in waiters { waiter.resume() }
    }

    enum FakeError: Error { case removeFailed }
}
