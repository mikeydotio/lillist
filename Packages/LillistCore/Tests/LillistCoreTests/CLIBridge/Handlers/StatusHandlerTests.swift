import Testing
import Foundation
import UserNotifications
@testable import LillistCore

@Suite("CLIBridge.StatusHandler")
struct StatusHandlerTests {
    // MARK: - X8: notificationScheduler parameter

    @Test("X8: with no notificationScheduler passed, defaults to nil — CLI's pre-existing behavior, unchanged")
    func defaultsToNoScheduler() async throws {
        let p = try await TestStore.make()
        let id = try await TaskStore(persistence: p).create(title: "Demo")
        // No crash, no notification side effect expected — this is exactly
        // today's lillist-cli call shape (StatusHandler.run without the new
        // parameter), asserted to still compile and behave identically.
        try await CLIBridge.StatusHandler.run(
            token: id.uuidString, to: .closed, note: nil, persistence: p
        )
        let rec = try await TaskStore(persistence: p).fetch(id: id)
        #expect(rec.status == .closed)
    }

    @Test("X8: a passed notificationScheduler is wired into the constructed TaskStore and reconciles on transition")
    func schedulerParameterIsWired() async throws {
        let p = try await TestStore.make()
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )
        let tasks = TaskStore(persistence: p)
        let id = try await tasks.create(title: "Demo")
        try await tasks.update(id: id) { d in
            d.deadline = Date().addingTimeInterval(3600); d.deadlineHasTime = true
        }
        _ = try await scheduler.addOffset(taskID: id, anchor: .deadline, offsetMinutes: -10)
        #expect(await fake.addedCount() == 1)

        // Simulates what CompleteTaskIntent/ToggleStatusIntent now do: pass
        // an extension-constructed scheduler through StatusHandler.run —
        // this must reconcile the pending set the exact same way the app's
        // own status controls do (closing cancels all pending, matching
        // NotificationSchedulerStatusTransitionsTests's "Closing a task
        // cancels all pending deliveries").
        try await CLIBridge.StatusHandler.run(
            token: id.uuidString, to: .closed, note: nil,
            persistence: p, notificationScheduler: scheduler
        )

        #expect(await fake.pendingNotificationRequests().isEmpty, "a scheduler passed through StatusHandler.run must actually cancel the pending reminder on close")
    }
    @Test("Transitions to started for fuzzy match")
    func started() async throws {
        let p = try await TestStore.make()
        let id = try await TaskStore(persistence: p).create(title: "Demo")
        try await CLIBridge.StatusHandler.run(
            token: "Demo", to: .started, note: nil, persistence: p
        )
        let rec = try await TaskStore(persistence: p).fetch(id: id)
        #expect(rec.status == .started)
    }

    @Test("Transition to closed requires exact match for fuzzy token")
    func closedRequiresExact() async throws {
        let p = try await TestStore.make()
        _ = try await TaskStore(persistence: p).create(title: "Buy stuff at the store")
        await #expect(throws: LillistError.self) {
            try await CLIBridge.StatusHandler.run(
                token: "stuff", to: .closed, note: nil, persistence: p
            )
        }
    }

    @Test("Closed transition accepts UUID")
    func closedAcceptsUUID() async throws {
        let p = try await TestStore.make()
        let id = try await TaskStore(persistence: p).create(title: "Demo")
        try await CLIBridge.StatusHandler.run(
            token: id.uuidString, to: .closed, note: nil, persistence: p
        )
        let rec = try await TaskStore(persistence: p).fetch(id: id)
        #expect(rec.status == .closed)
    }

    @Test("Optional note appended after transition")
    func noteAppended() async throws {
        let p = try await TestStore.make()
        let id = try await TaskStore(persistence: p).create(title: "Demo")
        try await CLIBridge.StatusHandler.run(
            token: id.uuidString, to: .blocked, note: "waiting on QA", persistence: p
        )
        let entries = try await JournalStore(persistence: p).entries(forTask: id)
        #expect(entries.contains { $0.body == "waiting on QA" })
    }
}
