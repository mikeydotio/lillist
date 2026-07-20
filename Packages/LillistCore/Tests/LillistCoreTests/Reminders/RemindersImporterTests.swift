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
                // The drain only ever processes incomplete reminders (see
                // `skipsCompletedReminders`); these fixtures default to
                // incomplete so the other tests exercise that common path.
                isCompleted: false
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

        let outcome = await importer.drainIfNeeded()
        #expect(outcome == .completed(imported: 3, deletedWithoutImport: 0))

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

    @Test("Second drain reports a clean completed(0,0) once the list is empty")
    func idempotent() async throws {
        let persistence = try await TestStore.make()
        let taskStore = TaskStore(persistence: persistence)
        let prefs = await Self.enabledPrefs()
        let gateway = FakeRemindersGateway(itemsByList: [Self.listID: Self.items(2)])
        let importer = RemindersImporter(gateway: gateway, taskStore: taskStore, devicePreferences: prefs)

        _ = await importer.drainIfNeeded()
        let second = await importer.drainIfNeeded()
        #expect(second == .completed(imported: 0, deletedWithoutImport: 0))
        #expect(try await Self.allTasks(persistence).count == 2)
    }

    @Test("Disabled feature reports featureDisabled and leaves the list intact")
    func disabledNoOp() async throws {
        let persistence = try await TestStore.make()
        let taskStore = TaskStore(persistence: persistence)
        let prefs = Self.freshPrefs() // not enabled
        await prefs.setRemindersImportListID(Self.listID)
        let gateway = FakeRemindersGateway(itemsByList: [Self.listID: Self.items(2)])
        let importer = RemindersImporter(gateway: gateway, taskStore: taskStore, devicePreferences: prefs)

        #expect(await importer.drainIfNeeded() == .featureDisabled)
        #expect(try await Self.allTasks(persistence).isEmpty)
        #expect(await gateway.remainingItems(inListID: Self.listID).count == 2)
    }

    @Test("No selected list reports noListSelected")
    func unsetListNoOp() async throws {
        let persistence = try await TestStore.make()
        let taskStore = TaskStore(persistence: persistence)
        let prefs = await Self.enabledPrefs(list: nil)
        let gateway = FakeRemindersGateway(itemsByList: [Self.listID: Self.items(2)])
        let importer = RemindersImporter(gateway: gateway, taskStore: taskStore, devicePreferences: prefs)

        #expect(await importer.drainIfNeeded() == .noListSelected)
        #expect(try await Self.allTasks(persistence).isEmpty)
    }

    @Test("Unauthorized reports notAuthorized")
    func unauthorizedNoOp() async throws {
        let persistence = try await TestStore.make()
        let taskStore = TaskStore(persistence: persistence)
        let prefs = await Self.enabledPrefs()
        let gateway = FakeRemindersGateway(auth: .denied, itemsByList: [Self.listID: Self.items(2)])
        let importer = RemindersImporter(gateway: gateway, taskStore: taskStore, devicePreferences: prefs)

        #expect(await importer.drainIfNeeded() == .notAuthorized)
        #expect(try await Self.allTasks(persistence).isEmpty)
    }

    @Test("A persisted list id the gateway doesn't recognize reports listUnavailable, not a false empty completion")
    func staleListSurfacesUnavailable() async throws {
        let persistence = try await TestStore.make()
        let taskStore = TaskStore(persistence: persistence)
        // The prefs point at Self.listID, but the gateway only knows a
        // *different* list — simulating a persisted calendarIdentifier that
        // no longer resolves on this EKEventStore (issue #50, sub-cause B).
        let prefs = await Self.enabledPrefs()
        let gateway = FakeRemindersGateway(itemsByList: ["some-other-list": Self.items(2)])
        let importer = RemindersImporter(gateway: gateway, taskStore: taskStore, devicePreferences: prefs)

        #expect(await importer.drainIfNeeded() == .listUnavailable(listID: Self.listID))
        #expect(try await Self.allTasks(persistence).isEmpty)
    }

    @Test("A known list with zero items reports completed(0,0), not listUnavailable")
    func emptyKnownListReportsCompletedZero() async throws {
        let persistence = try await TestStore.make()
        let taskStore = TaskStore(persistence: persistence)
        let prefs = await Self.enabledPrefs()
        // Key present, value empty — a genuinely empty (not unresolvable) list.
        let gateway = FakeRemindersGateway(itemsByList: [Self.listID: []])
        let importer = RemindersImporter(gateway: gateway, taskStore: taskStore, devicePreferences: prefs)

        #expect(await importer.drainIfNeeded() == .completed(imported: 0, deletedWithoutImport: 0))
    }

    @Test("drain(listID:) drains the passed list even when no list is persisted (kills the picker-persist race)")
    func explicitDrainUsesPassedListIgnoringPersisted() async throws {
        let persistence = try await TestStore.make()
        let taskStore = TaskStore(persistence: persistence)
        // Persisted state has NO list selected — as it would be immediately
        // after picking one, before the picker's fire-and-forget persist Task
        // lands. "Drain now" must still work off the in-memory selection.
        let prefs = await Self.enabledPrefs(list: nil)
        let gateway = FakeRemindersGateway(itemsByList: [Self.listID: Self.items(2)])
        let importer = RemindersImporter(gateway: gateway, taskStore: taskStore, devicePreferences: prefs)

        let outcome = await importer.drain(listID: Self.listID)
        #expect(outcome == .completed(imported: 2, deletedWithoutImport: 0))
        #expect(try await Self.allTasks(persistence).count == 2)
    }

    @Test("drain(listID:) still requires authorization")
    func explicitDrainRequiresAuthorization() async throws {
        let persistence = try await TestStore.make()
        let taskStore = TaskStore(persistence: persistence)
        let prefs = await Self.enabledPrefs(list: nil)
        let gateway = FakeRemindersGateway(auth: .denied, itemsByList: [Self.listID: Self.items(2)])
        let importer = RemindersImporter(gateway: gateway, taskStore: taskStore, devicePreferences: prefs)

        #expect(await importer.drain(listID: Self.listID) == .notAuthorized)
        #expect(try await Self.allTasks(persistence).isEmpty)
    }

    @Test("A concurrent call while one is already draining coalesces to busy, not a false empty completion")
    func alreadyDrainingReturnsBusy() async throws {
        let persistence = try await TestStore.make()
        let taskStore = TaskStore(persistence: persistence)
        let prefs = await Self.enabledPrefs()
        let gateway = FakeRemindersGateway(itemsByList: [Self.listID: Self.items(2)])
        await gateway.setHoldFetch(true)
        let importer = RemindersImporter(gateway: gateway, taskStore: taskStore, devicePreferences: prefs)

        // The first call sets isDraining synchronously and then suspends
        // inside gateway.items(inListID:) (held by the fake). Awaiting the
        // first call's *start* via a task and yielding gives it a chance to
        // reach that suspension point before the second call fires.
        let first = Task { await importer.drainIfNeeded() }
        try await Task.sleep(for: .milliseconds(50))

        let second = await importer.drainIfNeeded()
        #expect(second == .busy)

        await gateway.releaseFetch()
        let firstOutcome = await first.value
        #expect(firstOutcome == .completed(imported: 2, deletedWithoutImport: 0))
    }

    @Test("Blank-title reminder still drains via a fallback title")
    func blankTitleFallback() async throws {
        let persistence = try await TestStore.make()
        let taskStore = TaskStore(persistence: persistence)
        let prefs = await Self.enabledPrefs()
        let blank = ReminderItem(id: "rem-x", title: "   ", notes: nil, dueDate: nil, dueHasTime: false, isCompleted: false)
        let gateway = FakeRemindersGateway(itemsByList: [Self.listID: [blank]])
        let importer = RemindersImporter(gateway: gateway, taskStore: taskStore, devicePreferences: prefs)

        #expect(await importer.drainIfNeeded() == .completed(imported: 1, deletedWithoutImport: 0))
        let tasks = try await Self.allTasks(persistence)
        #expect(tasks.count == 1)
        #expect(tasks.first?.title == "Untitled")
        #expect(await gateway.remainingItems(inListID: Self.listID).isEmpty)
    }

    @Test("Crash window: a failed delete never produces a duplicate on the next pass, and is reported as deletedWithoutImport")
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
        #expect(first == .completed(imported: 3, deletedWithoutImport: 0))
        // rem-1 survived the delete and is still queued + marked in-flight.
        #expect(await gateway.remainingItems(inListID: Self.listID).map(\.id) == ["rem-1"])
        #expect(await prefs.remindersInFlightIDs() == ["rem-1"])

        // Delete now succeeds; the next pass must NOT re-create rem-1's task,
        // and must report it as crash-window cleanup, not a fresh import.
        await gateway.clearFailRemove()
        let second = await importer.drainIfNeeded()
        #expect(second == .completed(imported: 0, deletedWithoutImport: 1))
        #expect(try await Self.allTasks(persistence).count == 3) // still 3, no dupe
        #expect(await gateway.remainingItems(inListID: Self.listID).isEmpty)
        #expect(await prefs.remindersInFlightIDs().isEmpty)
    }

    @Test("Completed reminders are skipped: not imported, not removed")
    func skipsCompletedReminders() async throws {
        let persistence = try await TestStore.make()
        let taskStore = TaskStore(persistence: persistence)
        let prefs = await Self.enabledPrefs()
        let incomplete = ReminderItem(
            id: "rem-open", title: "Open reminder", notes: nil,
            dueDate: nil, dueHasTime: false, isCompleted: false
        )
        let completed = ReminderItem(
            id: "rem-done", title: "Done reminder", notes: nil,
            dueDate: nil, dueHasTime: false, isCompleted: true
        )
        let gateway = FakeRemindersGateway(itemsByList: [Self.listID: [incomplete, completed]])
        let importer = RemindersImporter(gateway: gateway, taskStore: taskStore, devicePreferences: prefs)

        let outcome = await importer.drainIfNeeded()
        #expect(outcome == .completed(imported: 1, deletedWithoutImport: 0))

        let tasks = try await Self.allTasks(persistence)
        #expect(tasks.count == 1)
        #expect(tasks.first?.title == "Open reminder")

        // The completed reminder is left in Reminders untouched — neither
        // imported nor removed.
        let remaining = await gateway.remainingItems(inListID: Self.listID)
        #expect(remaining.map(\.id) == ["rem-done"])
    }

    @Test("A mid-flight item still gets deleted even if it's completed before the retry")
    func inFlightItemStillRemovedIfCompletedBeforeRetry() async throws {
        let persistence = try await TestStore.make()
        let taskStore = TaskStore(persistence: persistence)
        let prefs = await Self.enabledPrefs()
        let item = ReminderItem(
            id: "rem-1", title: "Reminder 1", notes: nil,
            dueDate: nil, dueHasTime: false, isCompleted: false
        )
        // First pass: the task is created but the delete fails, leaving
        // "rem-1" in-flight.
        let gateway = FakeRemindersGateway(itemsByList: [Self.listID: [item]], failRemoveIDs: ["rem-1"])
        let importer = RemindersImporter(gateway: gateway, taskStore: taskStore, devicePreferences: prefs)

        let first = await importer.drainIfNeeded()
        #expect(first == .completed(imported: 1, deletedWithoutImport: 0))
        #expect(await prefs.remindersInFlightIDs() == ["rem-1"])

        // The user completes it in Reminders.app before the retry, and the
        // delete now succeeds.
        await gateway.markCompleted(itemID: "rem-1", inListID: Self.listID)
        await gateway.clearFailRemove()

        let second = await importer.drainIfNeeded()
        // No new task — the create already happened on the first pass. The
        // cleanup delete still counts as deletedWithoutImport (crash-window
        // cleanup), not a fresh import.
        #expect(second == .completed(imported: 0, deletedWithoutImport: 1))
        #expect(try await Self.allTasks(persistence).count == 1)
        // But the reminder is still removed, and its marker cleared.
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
            await withTaskGroup(of: RemindersDrainOutcome.self) { group in
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
