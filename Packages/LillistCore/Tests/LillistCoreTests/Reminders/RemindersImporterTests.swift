import Testing
import Foundation
@testable import LillistCore

@Suite("RemindersImporter")
struct RemindersImporterTests {
    private static let listID = "list-A"

    // MARK: Helpers

    private static func freshPrefs() -> DevicePreferencesStore {
        let suite = "RemindersImporterTests-\(UUID().uuidString)"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        return DevicePreferencesStore(suiteName: suite)
    }

    private static func enabledPrefs(list: String? = listID) async -> DevicePreferencesStore {
        let prefs = freshPrefs()
        await prefs.setRemindersImportEnabled(true)
        if let list { await prefs.setRemindersImportListID(list) }
        return prefs
    }

    private static func items(_ count: Int, withDue: Bool = false) -> [ReminderItem] {
        var result: [ReminderItem] = []
        for i in 0..<count {
            let notes: String? = (i == 0) ? "note-0" : nil
            var due: Date?
            if withDue {
                due = Date(timeIntervalSince1970: 1_700_000_000 + Double(i) * 86_400)
            }
            result.append(ReminderItem(
                id: "rem-\(i)",
                title: "Reminder \(i)",
                notes: notes,
                dueDate: due,
                dueHasTime: withDue,
                isCompleted: (i % 2 == 0)
            ))
        }
        return result
    }

    /// Enumerate all non-trashed tasks (no public list-all API on TaskStore;
    /// mirror `TaskEntityQuery.suggestedEntities`).
    private static func allTasks(_ persistence: PersistenceController) async throws -> [TaskStore.TaskRecord] {
        let group = PredicateGroup(
            combinator: .all,
            predicates: [.leaf(Leaf(field: .inTrash, op: .is, value: .bool(false)))]
        )
        return try await SmartFilterStore(persistence: persistence)
            .evaluate(group: group, sort: .modifiedAt, ascending: false, limit: 1000)
    }

    // MARK: Tests

    @Test("Drains every item into top-level tasks; title/notes/deadline map across")
    func drainsAll() async throws {
        let persistence = try await TestStore.make()
        let taskStore = TaskStore(persistence: persistence)
        let prefs = await Self.enabledPrefs()
        let gateway = FakeRemindersGateway(itemsByList: [Self.listID: Self.items(3, withDue: true)])
        let importer = RemindersImporter(gateway: gateway, taskStore: taskStore, devicePreferences: prefs)

        let count = await importer.drainIfNeeded()
        #expect(count == 3)

        let tasks = try await Self.allTasks(persistence)
        #expect(tasks.count == 3)
        #expect(tasks.allSatisfy { $0.parentID == nil })
        let titles = Set(tasks.map(\.title))
        #expect(titles == ["Reminder 0", "Reminder 1", "Reminder 2"])
        #expect(tasks.allSatisfy { $0.deadline != nil })
        let withNote = tasks.first { $0.title == "Reminder 0" }
        #expect(withNote?.notes == "note-0")

        let remaining = await gateway.remainingItems(inListID: Self.listID)
        #expect(remaining.isEmpty)
    }

    @Test("Second drain is a no-op once the list is empty")
    func idempotent() async throws {
        let persistence = try await TestStore.make()
        let taskStore = TaskStore(persistence: persistence)
        let prefs = await Self.enabledPrefs()
        let gateway = FakeRemindersGateway(itemsByList: [Self.listID: Self.items(2)])
        let importer = RemindersImporter(gateway: gateway, taskStore: taskStore, devicePreferences: prefs)

        _ = await importer.drainIfNeeded()
        let second = await importer.drainIfNeeded()
        #expect(second == 0)
        #expect(try await Self.allTasks(persistence).count == 2)
    }

    @Test("Disabled feature drains nothing and leaves the list intact")
    func disabledNoOp() async throws {
        let persistence = try await TestStore.make()
        let taskStore = TaskStore(persistence: persistence)
        let prefs = Self.freshPrefs() // not enabled
        await prefs.setRemindersImportListID(Self.listID)
        let gateway = FakeRemindersGateway(itemsByList: [Self.listID: Self.items(2)])
        let importer = RemindersImporter(gateway: gateway, taskStore: taskStore, devicePreferences: prefs)

        #expect(await importer.drainIfNeeded() == 0)
        #expect(try await Self.allTasks(persistence).isEmpty)
        #expect(await gateway.remainingItems(inListID: Self.listID).count == 2)
    }

    @Test("No selected list drains nothing")
    func unsetListNoOp() async throws {
        let persistence = try await TestStore.make()
        let taskStore = TaskStore(persistence: persistence)
        let prefs = await Self.enabledPrefs(list: nil)
        let gateway = FakeRemindersGateway(itemsByList: [Self.listID: Self.items(2)])
        let importer = RemindersImporter(gateway: gateway, taskStore: taskStore, devicePreferences: prefs)

        #expect(await importer.drainIfNeeded() == 0)
        #expect(try await Self.allTasks(persistence).isEmpty)
    }

    @Test("Unauthorized drains nothing")
    func unauthorizedNoOp() async throws {
        let persistence = try await TestStore.make()
        let taskStore = TaskStore(persistence: persistence)
        let prefs = await Self.enabledPrefs()
        let gateway = FakeRemindersGateway(auth: .denied, itemsByList: [Self.listID: Self.items(2)])
        let importer = RemindersImporter(gateway: gateway, taskStore: taskStore, devicePreferences: prefs)

        #expect(await importer.drainIfNeeded() == 0)
        #expect(try await Self.allTasks(persistence).isEmpty)
    }

    @Test("Blank-title reminder still drains via a fallback title")
    func blankTitleFallback() async throws {
        let persistence = try await TestStore.make()
        let taskStore = TaskStore(persistence: persistence)
        let prefs = await Self.enabledPrefs()
        let blank = ReminderItem(id: "rem-x", title: "   ", notes: nil, dueDate: nil, dueHasTime: false, isCompleted: false)
        let gateway = FakeRemindersGateway(itemsByList: [Self.listID: [blank]])
        let importer = RemindersImporter(gateway: gateway, taskStore: taskStore, devicePreferences: prefs)

        #expect(await importer.drainIfNeeded() == 1)
        let tasks = try await Self.allTasks(persistence)
        #expect(tasks.count == 1)
        #expect(tasks.first?.title == "Untitled")
        #expect(await gateway.remainingItems(inListID: Self.listID).isEmpty)
    }

    @Test("Crash window: a failed delete never produces a duplicate on the next pass")
    func dedupAcrossFailedDelete() async throws {
        let persistence = try await TestStore.make()
        let taskStore = TaskStore(persistence: persistence)
        let prefs = await Self.enabledPrefs()
        // "rem-1" fails to delete on the first pass.
        let gateway = FakeRemindersGateway(
            itemsByList: [Self.listID: Self.items(3)],
            failRemoveIDs: ["rem-1"]
        )
        let importer = RemindersImporter(gateway: gateway, taskStore: taskStore, devicePreferences: prefs)

        let first = await importer.drainIfNeeded()
        #expect(first == 3)
        // rem-1 survived the delete and is still queued + marked in-flight.
        #expect(await gateway.remainingItems(inListID: Self.listID).map(\.id) == ["rem-1"])
        #expect(await prefs.remindersInFlightIDs() == ["rem-1"])

        // Delete now succeeds; the next pass must NOT re-create rem-1's task.
        await gateway.clearFailRemove()
        let second = await importer.drainIfNeeded()
        #expect(second == 0)
        #expect(try await Self.allTasks(persistence).count == 3) // still 3, no dupe
        #expect(await gateway.remainingItems(inListID: Self.listID).isEmpty)
        #expect(await prefs.remindersInFlightIDs().isEmpty)
    }

    @Test("Stress: repeated concurrent drains never duplicate tasks")
    func stressNoDuplicates() async throws {
        for _ in 0..<25 {
            let persistence = try await TestStore.make()
            let taskStore = TaskStore(persistence: persistence)
            let prefs = await Self.enabledPrefs()
            let gateway = FakeRemindersGateway(itemsByList: [Self.listID: Self.items(5)])
            let importer = RemindersImporter(gateway: gateway, taskStore: taskStore, devicePreferences: prefs)

            // Fire several drains concurrently; the actor + isDraining guard
            // must collapse them to a single effective pass.
            await withTaskGroup(of: Int.self) { group in
                for _ in 0..<4 { group.addTask { await importer.drainIfNeeded() } }
                for await _ in group {}
            }
            // A trailing serial drain catches anything a coalesced pass skipped.
            _ = await importer.drainIfNeeded()

            #expect(try await Self.allTasks(persistence).count == 5)
            #expect(await gateway.remainingItems(inListID: Self.listID).isEmpty)
        }
    }
}
