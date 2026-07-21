import Testing
import Foundation
@testable import LillistCore

/// Issue #66: the safety gaps a Reminders drain left after the
/// completed-reminder filter was fixed (`d3e9db53`) — the automatic pass
/// had no ceiling and could still silently import a huge, unwanted batch in
/// one pass, and there was no way to undo an import once it happened (the
/// drained reminder is also deleted from Reminders.app, so a full local
/// restore was the only recourse). Covers the auto-import limit, the
/// manual-drain preview, and the one-shot undo affordance.
@Suite("RemindersImporter safety (limit / preview / undo)")
struct RemindersImporterSafetyTests {
    private static let listID = "list-A"

    private static func freshPrefs() -> DevicePreferencesStore {
        let suite = "RemindersImporterSafetyTests-\(UUID().uuidString)"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        return DevicePreferencesStore(suiteName: suite)
    }

    private static func enabledPrefs(list: String? = listID) async -> DevicePreferencesStore {
        let prefs = freshPrefs()
        await prefs.setRemindersImportEnabled(true)
        if let list { await prefs.setRemindersImportListID(list) }
        return prefs
    }

    private static func items(_ count: Int, completed: Bool = false) -> [ReminderItem] {
        (0..<count).map { i in
            ReminderItem(
                id: "rem-\(i)", title: "Reminder \(i)", notes: nil,
                dueDate: nil, dueHasTime: false, isCompleted: completed
            )
        }
    }

    /// Mirrors `RemindersImporterTests.allTasks` — no public list-all API.
    private static func allTasks(_ persistence: PersistenceController) async throws -> [TaskStore.TaskRecord] {
        let group = PredicateGroup(
            combinator: .all,
            predicates: [.leaf(Leaf(field: .inTrash, op: .is, value: .bool(false)))]
        )
        return try await SmartFilterStore(persistence: persistence)
            .evaluate(group: group, sort: .modifiedAt, ascending: false, limit: 1000)
    }

    // MARK: - Auto-import limit

    @Test("An automatic pass at or under the limit imports normally")
    func autoDrainAtLimitImportsNormally() async throws {
        let persistence = try await TestStore.make()
        let taskStore = TaskStore(persistence: persistence)
        let prefs = await Self.enabledPrefs()
        let gateway = FakeRemindersGateway(itemsByList: [Self.listID: Self.items(5)])
        let importer = RemindersImporter(
            gateway: gateway, taskStore: taskStore, devicePreferences: prefs, autoImportLimit: 5
        )

        let outcome = await importer.drainIfNeeded()
        #expect(outcome == .completed(imported: 5, deletedWithoutImport: 0))
    }

    @Test("An automatic pass over the limit imports NOTHING and reports tooManyToAutoImport")
    func autoDrainOverLimitImportsNothing() async throws {
        let persistence = try await TestStore.make()
        let taskStore = TaskStore(persistence: persistence)
        let prefs = await Self.enabledPrefs()
        let gateway = FakeRemindersGateway(itemsByList: [Self.listID: Self.items(30)])
        let importer = RemindersImporter(
            gateway: gateway, taskStore: taskStore, devicePreferences: prefs, autoImportLimit: 25
        )

        let outcome = await importer.drainIfNeeded()
        #expect(outcome == .tooManyToAutoImport(listID: Self.listID, count: 30))

        let tasks = try await Self.allTasks(persistence)
        #expect(tasks.isEmpty, "nothing should be imported when the limit is exceeded")
        let remaining = await gateway.remainingItems(inListID: Self.listID)
        #expect(remaining.count == 30, "reminders must stay untouched in Reminders.app too")
    }

    @Test("Completed reminders don't count toward the auto-import limit")
    func completedItemsDoNotCountTowardLimit() async throws {
        let persistence = try await TestStore.make()
        let taskStore = TaskStore(persistence: persistence)
        let prefs = await Self.enabledPrefs()
        // 3 incomplete (under the limit) + 40 completed (never drained anyway).
        let gateway = FakeRemindersGateway(itemsByList: [
            Self.listID: Self.items(3) + Self.items(40, completed: true)
        ])
        let importer = RemindersImporter(
            gateway: gateway, taskStore: taskStore, devicePreferences: prefs, autoImportLimit: 25
        )

        let outcome = await importer.drainIfNeeded()
        #expect(outcome == .completed(imported: 3, deletedWithoutImport: 0))
    }

    @Test("The manual drain(listID:) path is never subject to the auto-import limit")
    func manualDrainIgnoresLimit() async throws {
        let persistence = try await TestStore.make()
        let taskStore = TaskStore(persistence: persistence)
        let prefs = Self.freshPrefs()   // feature disabled — irrelevant to the manual path
        let gateway = FakeRemindersGateway(itemsByList: [Self.listID: Self.items(30)])
        let importer = RemindersImporter(
            gateway: gateway, taskStore: taskStore, devicePreferences: prefs, autoImportLimit: 25
        )

        let outcome = await importer.drain(listID: Self.listID)
        #expect(outcome == .completed(imported: 30, deletedWithoutImport: 0))
    }

    // MARK: - preview(listID:)

    @Test("preview reports the count of incomplete reminders without importing or removing anything")
    func previewReportsCandidateCountWithoutMutating() async throws {
        let persistence = try await TestStore.make()
        let taskStore = TaskStore(persistence: persistence)
        let prefs = await Self.enabledPrefs()
        let gateway = FakeRemindersGateway(itemsByList: [
            Self.listID: Self.items(4) + Self.items(2, completed: true)
        ])
        let importer = RemindersImporter(gateway: gateway, taskStore: taskStore, devicePreferences: prefs)

        let preview = await importer.preview(listID: Self.listID)
        #expect(preview == RemindersDrainPreview(listID: Self.listID, candidateCount: 4))

        // Nothing was imported or removed.
        let tasks = try await Self.allTasks(persistence)
        #expect(tasks.isEmpty)
        let remaining = await gateway.remainingItems(inListID: Self.listID)
        #expect(remaining.count == 6)
    }

    @Test("preview returns nil when Reminders access isn't authorized")
    func previewReturnsNilWhenUnauthorized() async throws {
        let persistence = try await TestStore.make()
        let taskStore = TaskStore(persistence: persistence)
        let prefs = await Self.enabledPrefs()
        let gateway = FakeRemindersGateway(itemsByList: [Self.listID: Self.items(3)])
        await gateway.setAuth(.denied)
        let importer = RemindersImporter(gateway: gateway, taskStore: taskStore, devicePreferences: prefs)

        let preview = await importer.preview(listID: Self.listID)
        #expect(preview == nil)
    }

    // MARK: - undoLastImport()

    @Test("Undo soft-deletes exactly the tasks from the most recent import")
    func undoSoftDeletesLastBatch() async throws {
        let persistence = try await TestStore.make()
        let taskStore = TaskStore(persistence: persistence)
        let prefs = await Self.enabledPrefs()
        let gateway = FakeRemindersGateway(itemsByList: [Self.listID: Self.items(3)])
        let importer = RemindersImporter(gateway: gateway, taskStore: taskStore, devicePreferences: prefs)

        _ = await importer.drainIfNeeded()
        #expect(try await Self.allTasks(persistence).count == 3)

        let undone = await importer.undoLastImport()
        #expect(undone == .undone(count: 3))
        #expect(try await Self.allTasks(persistence).isEmpty, "the undone tasks must no longer appear in non-trash views")
    }

    @Test("Undoing twice in a row reports nothingToUndo the second time")
    func undoTwiceReportsNothingToUndoOnceCleared() async throws {
        let persistence = try await TestStore.make()
        let taskStore = TaskStore(persistence: persistence)
        let prefs = await Self.enabledPrefs()
        let gateway = FakeRemindersGateway(itemsByList: [Self.listID: Self.items(2)])
        let importer = RemindersImporter(gateway: gateway, taskStore: taskStore, devicePreferences: prefs)

        _ = await importer.drainIfNeeded()
        let first = await importer.undoLastImport()
        #expect(first == .undone(count: 2))

        let second = await importer.undoLastImport()
        #expect(second == .nothingToUndo)
    }

    @Test("Nothing to undo before any import has happened")
    func nothingToUndoBeforeAnyImport() async throws {
        let persistence = try await TestStore.make()
        let taskStore = TaskStore(persistence: persistence)
        let prefs = Self.freshPrefs()
        let gateway = FakeRemindersGateway(itemsByList: [:])
        let importer = RemindersImporter(gateway: gateway, taskStore: taskStore, devicePreferences: prefs)

        let outcome = await importer.undoLastImport()
        #expect(outcome == .nothingToUndo)
    }

    @Test("A later no-op pass does not clear a still-undoable prior batch")
    func laterEmptyPassDoesNotClearUndoableBatch() async throws {
        let persistence = try await TestStore.make()
        let taskStore = TaskStore(persistence: persistence)
        let prefs = await Self.enabledPrefs()
        let gateway = FakeRemindersGateway(itemsByList: [Self.listID: Self.items(2)])
        let importer = RemindersImporter(gateway: gateway, taskStore: taskStore, devicePreferences: prefs)

        // First pass imports 2 and drains the list empty.
        let first = await importer.drainIfNeeded()
        #expect(first == .completed(imported: 2, deletedWithoutImport: 0))

        // Second pass (e.g. the next app activation): list is now empty.
        let second = await importer.drainIfNeeded()
        #expect(second == .completed(imported: 0, deletedWithoutImport: 0))

        // The batch from the FIRST pass must still be undoable.
        let undone = await importer.undoLastImport()
        #expect(undone == .undone(count: 2))
    }

    @Test("undoLastImport and a concurrent drain never race — mutual exclusion, no duplicated or lost work")
    func undoAndDrainAreMutuallyExclusive() async throws {
        let persistence = try await TestStore.make()
        let taskStore = TaskStore(persistence: persistence)
        let prefs = await Self.enabledPrefs()
        let gateway = FakeRemindersGateway(itemsByList: [Self.listID: Self.items(1)])
        let importer = RemindersImporter(gateway: gateway, taskStore: taskStore, devicePreferences: prefs)

        // Both share one `isDraining` flag (the same mutual-exclusion
        // pattern already stress-tested for concurrent drains). Swift gives
        // no ordering guarantee between two `async let`s, so either call may
        // legitimately run first — what must NEVER happen is the other
        // observing partial state (e.g. undo "succeeding" against an import
        // that hasn't finished writing its batch yet).
        async let drainResult = importer.drainIfNeeded()
        async let undoResult = importer.undoLastImport()
        let (drain, undo) = await (drainResult, undoResult)

        switch (drain, undo) {
        case (.completed(let imported, _), .busy), (.completed(let imported, _), .nothingToUndo):
            #expect(imported == 1)
        case (.busy, .nothingToUndo), (.busy, .undone):
            break   // undo ran to completion (or found nothing yet) before the drain got its turn
        default:
            Issue.record("unexpected combination: drain=\(drain), undo=\(undo)")
        }

        // Whatever the interleaving, the single-item batch was never
        // duplicated or corrupted: at most one non-trashed task remains
        // (zero if undo ran after the import and removed it).
        let remainingTasks = try await Self.allTasks(persistence)
        #expect(remainingTasks.count <= 1)
    }
}
