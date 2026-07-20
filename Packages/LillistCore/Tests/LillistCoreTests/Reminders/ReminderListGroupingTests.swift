import Testing
@testable import LillistCore

@Suite("ReminderListGrouping")
struct ReminderListGroupingTests {
    private static func list(
        _ id: String,
        title: String,
        accountID: String,
        accountName: String,
        incompleteCount: Int = 0
    ) -> ReminderListInfo {
        ReminderListInfo(
            id: id,
            title: title,
            accountID: accountID,
            accountName: accountName,
            incompleteCount: incompleteCount
        )
    }

    @Test("Empty input yields no groups")
    func empty() {
        #expect(ReminderListGrouping.grouped([]).isEmpty)
    }

    @Test("A single account produces one group holding every list")
    func singleAccount() {
        let lists = [
            Self.list("a", title: "Inbox", accountID: "icloud", accountName: "iCloud"),
            Self.list("b", title: "Groceries", accountID: "icloud", accountName: "iCloud")
        ]
        let groups = ReminderListGrouping.grouped(lists)
        #expect(groups.count == 1)
        #expect(groups[0].accountID == "icloud")
        #expect(groups[0].accountName == "iCloud")
        #expect(groups[0].lists.map(\.id) == ["a", "b"])
    }

    @Test("Multiple accounts preserve first-appearance order")
    func multipleAccountsPreserveOrder() {
        let lists = [
            Self.list("a", title: "Work", accountID: "gmail", accountName: "Gmail"),
            Self.list("b", title: "Inbox", accountID: "icloud", accountName: "iCloud"),
            Self.list("c", title: "Errands", accountID: "gmail", accountName: "Gmail")
        ]
        let groups = ReminderListGrouping.grouped(lists)
        // "gmail" appeared first, so its group comes first even though a
        // "icloud" list is interleaved between "gmail" lists in the input.
        #expect(groups.map(\.accountID) == ["gmail", "icloud"])
        #expect(groups[0].lists.map(\.id) == ["a", "c"])
        #expect(groups[1].lists.map(\.id) == ["b"])
    }

    @Test("Lists sharing an account coalesce into one group")
    func coalescesSharedAccount() {
        let lists = [
            Self.list("a", title: "List A", accountID: "x", accountName: "Account X"),
            Self.list("b", title: "List B", accountID: "y", accountName: "Account Y"),
            Self.list("c", title: "List C", accountID: "x", accountName: "Account X")
        ]
        let groups = ReminderListGrouping.grouped(lists)
        #expect(groups.count == 2)
        #expect(groups.first { $0.accountID == "x" }?.lists.count == 2)
    }

    @Test("Grouping preserves each list's title and incomplete count")
    func preservesListFields() {
        let lists = [
            Self.list("a", title: "Inbox", accountID: "icloud", accountName: "iCloud", incompleteCount: 5)
        ]
        let groups = ReminderListGrouping.grouped(lists)
        #expect(groups[0].lists[0].title == "Inbox")
        #expect(groups[0].lists[0].incompleteCount == 5)
    }
}
