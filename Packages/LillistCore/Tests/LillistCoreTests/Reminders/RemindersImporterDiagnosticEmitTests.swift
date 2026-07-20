import Testing
import Foundation
@testable import LillistCore

/// Confirms `RemindersImporter` emits one `reminders.drain` event per pass
/// when given a diagnostic sink — the piece that makes the previously-silent
/// automatic activation drain (issue #50) inspectable after the fact.
@Suite("RemindersImporter diagnostics")
struct RemindersImporterDiagnosticEmitTests {
    private static let listID = "list-A"

    private static func enabledPrefs(list: String? = listID) async -> DevicePreferencesStore {
        let suite = "RemindersImporterDiagnosticEmitTests-\(UUID().uuidString)"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        let prefs = DevicePreferencesStore(suiteName: suite)
        await prefs.setRemindersImportEnabled(true)
        if let list { await prefs.setRemindersImportListID(list) }
        return prefs
    }

    private static func makeImporter(
        gateway: FakeRemindersGateway,
        prefs: DevicePreferencesStore,
        spy: SpyDiagnosticSink
    ) async throws -> RemindersImporter {
        let persistence = try await TestStore.make()
        return RemindersImporter(
            gateway: gateway,
            taskStore: TaskStore(persistence: persistence),
            devicePreferences: prefs,
            diagnosticLog: spy
        )
    }

    @Test("A completed auto drain emits reminders.drain with trigger, outcome, listID, and counts")
    func completedAutoDrainEmitsEvent() async throws {
        let spy = SpyDiagnosticSink()
        let prefs = await Self.enabledPrefs()
        let gateway = FakeRemindersGateway(itemsByList: [
            Self.listID: [ReminderItem(id: "rem-0", title: "One", notes: nil, dueDate: nil, dueHasTime: false, isCompleted: false)]
        ])
        let importer = try await Self.makeImporter(gateway: gateway, prefs: prefs, spy: spy)

        _ = await importer.drainIfNeeded()

        let events = await spy.events
        let event = try #require(events.last { $0.name == "reminders.drain" })
        #expect(event.category == .data)
        #expect(event.payload["trigger"] == .string("auto"))
        #expect(event.payload["outcome"] == .string("completed"))
        #expect(event.payload["listID"] == .string(Self.listID))
        #expect(event.payload["imported"] == .int(1))
        #expect(event.payload["deletedWithoutImport"] == .int(0))
    }

    @Test("An explicit manual drain tags the event trigger as manual")
    func explicitDrainEmitsManualTrigger() async throws {
        let spy = SpyDiagnosticSink()
        let prefs = await Self.enabledPrefs(list: nil)
        let gateway = FakeRemindersGateway(itemsByList: [Self.listID: []])
        let importer = try await Self.makeImporter(gateway: gateway, prefs: prefs, spy: spy)

        _ = await importer.drain(listID: Self.listID)

        let events = await spy.events
        let event = try #require(events.last { $0.name == "reminders.drain" })
        #expect(event.payload["trigger"] == .string("manual"))
        #expect(event.payload["outcome"] == .string("completed"))
    }

    @Test("A stale list id emits outcome:listUnavailable with the requested listID")
    func staleListEmitsListUnavailable() async throws {
        let spy = SpyDiagnosticSink()
        let prefs = await Self.enabledPrefs()
        let gateway = FakeRemindersGateway(itemsByList: ["some-other-list": []])
        let importer = try await Self.makeImporter(gateway: gateway, prefs: prefs, spy: spy)

        _ = await importer.drainIfNeeded()

        let events = await spy.events
        let event = try #require(events.last { $0.name == "reminders.drain" })
        #expect(event.payload["outcome"] == .string("listUnavailable"))
        #expect(event.payload["listID"] == .string(Self.listID))
        #expect(event.payload["imported"] == nil, "non-completed outcomes carry no count fields")
    }

    @Test("No diagnostic sink means no emission, and drainIfNeeded still works")
    func nilSinkEmitsNothing() async throws {
        let prefs = await Self.enabledPrefs()
        let gateway = FakeRemindersGateway(itemsByList: [Self.listID: []])
        let persistence = try await TestStore.make()
        // No diagnosticLog: — the default-nil param must not be required at
        // every one of the ~10 existing call sites across the test suite.
        let importer = RemindersImporter(gateway: gateway, taskStore: TaskStore(persistence: persistence), devicePreferences: prefs)

        let outcome = await importer.drainIfNeeded()
        #expect(outcome == .completed(imported: 0, deletedWithoutImport: 0))
    }
}
