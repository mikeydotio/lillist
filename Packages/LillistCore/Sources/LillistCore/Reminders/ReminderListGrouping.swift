import Foundation

/// One account's worth of Reminders lists, grouped for display (e.g. as a
/// `Section` in the Reminders import picker).
public struct ReminderListGroup: Sendable, Equatable, Identifiable {
    public let accountID: String
    public let accountName: String
    public let lists: [ReminderListInfo]

    public var id: String { accountID }

    public init(accountID: String, accountName: String, lists: [ReminderListInfo]) {
        self.accountID = accountID
        self.accountName = accountName
        self.lists = lists
    }
}

/// Groups a flat `[ReminderListInfo]` by the account (`EKSource`) each list
/// belongs to. Pure and platform-agnostic so both the iOS and macOS picker
/// share one tested implementation instead of duplicating the grouping logic.
public enum ReminderListGrouping {
    /// Groups `lists` by `accountID`, preserving the first-appearance order
    /// of both the accounts and the lists within each account. Callers that
    /// want a specific display order (e.g. alphabetical) should sort `lists`
    /// before calling this — `EventKitRemindersGateway.lists()` already
    /// returns them account-then-title sorted.
    public static func grouped(_ lists: [ReminderListInfo]) -> [ReminderListGroup] {
        var order: [String] = []
        var byAccount: [String: (name: String, lists: [ReminderListInfo])] = [:]
        for list in lists {
            if byAccount[list.accountID] == nil {
                order.append(list.accountID)
                byAccount[list.accountID] = (list.accountName, [])
            }
            byAccount[list.accountID]?.lists.append(list)
        }
        return order.compactMap { accountID in
            byAccount[accountID].map {
                ReminderListGroup(accountID: accountID, accountName: $0.name, lists: $0.lists)
            }
        }
    }
}
