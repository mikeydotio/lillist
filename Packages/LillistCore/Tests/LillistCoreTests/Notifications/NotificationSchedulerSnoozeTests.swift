import Testing
import Foundation
import UserNotifications
@testable import LillistCore

@Suite("NotificationScheduler — Snooze")
struct NotificationSchedulerSnoozeTests {
    /// `LIL-90`: the snooze now lands in the device-local ``SnoozeStateStore``
    /// rather than on the synced spec row. The observable contract — snoozing
    /// reschedules the notification to the snooze instant — is unchanged; only
    /// where the state lives moved.
    @Test("handleSnoozeAction records a device-local snooze and reschedules to that date")
    func snoozeTenMinutes() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let snoozeState = SnoozeStateStore(suiteName: "SchedulerSnoozeTests-\(UUID().uuidString)")
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!,
            snoozeState: snoozeState
        )

        let taskID = try await tasks.create(title: "T")
        let nudgeID = try await scheduler.addNudge(taskID: taskID, fireDate: Date().addingTimeInterval(60))

        let deliveredAt = Date().addingTimeInterval(60)
        try await scheduler.handleSnoozeAction(
            actionID: "snooze.10m",
            specID: nudgeID,
            deliveredAt: deliveredAt
        )

        let stored = try #require(await snoozeState.snoozedUntil(specID: nudgeID))
        let expected = deliveredAt.addingTimeInterval(600)
        #expect(abs(stored.timeIntervalSince(expected)) < 1.0)
        // And it must NOT have touched the synced row.
        #expect(try await specs.fetch(id: nudgeID).snoozedUntil == nil)

        let pending = await fake.pendingNotificationRequests()
        let trigger = pending.first?.trigger as? UNCalendarNotificationTrigger
        #expect(trigger != nil)
    }

    @Test("A snoozed reminder reschedules to the snooze instant, not its original anchor")
    func snoozeWinsOverAnchor() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let snoozeState = SnoozeStateStore(suiteName: "SchedulerSnoozeTests-\(UUID().uuidString)")
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current),
            deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!,
            snoozeState: snoozeState
        )

        let taskID = try await tasks.create(title: "T")
        let original = Date().addingTimeInterval(3_600)
        let nudgeID = try await scheduler.addNudge(taskID: taskID, fireDate: original)

        let until = Date().addingTimeInterval(7_200)
        await snoozeState.setSnoozedUntil(until, specID: nudgeID)
        await scheduler.reconcile(taskID: taskID)

        // Proves hydration actually runs during reconcile — the store projects
        // `snoozedUntil` as nil, so without it the snooze would be invisible.
        let pending = await fake.pendingNotificationRequests()
        let trigger = try #require(pending.first?.trigger as? UNCalendarNotificationTrigger)
        let fireAt = try #require(trigger.nextTriggerDate())
        #expect(abs(fireAt.timeIntervalSince(until)) < 60)
        #expect(abs(fireAt.timeIntervalSince(original)) > 60)
    }

    @Test("Unknown snooze action ID is rejected")
    func unknownAction() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )

        let taskID = try await tasks.create(title: "T")
        let nudgeID = try await scheduler.addNudge(taskID: taskID, fireDate: Date().addingTimeInterval(60))

        await #expect(throws: LillistError.self) {
            try await scheduler.handleSnoozeAction(
                actionID: "nope",
                specID: nudgeID,
                deliveredAt: Date()
            )
        }
    }
}
