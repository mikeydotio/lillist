import Testing
import Foundation
import UserNotifications
@testable import LillistCore

@Suite("NotificationScheduler — Snooze")
struct NotificationSchedulerSnoozeTests {
    @Test("handleSnoozeAction writes snoozedUntil and reschedules to that date")
    func snoozeTenMinutes() async throws {
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

        let deliveredAt = Date().addingTimeInterval(60)
        try await scheduler.handleSnoozeAction(
            actionID: "snooze.10m",
            specID: nudgeID,
            deliveredAt: deliveredAt
        )

        let record = try await specs.fetch(id: nudgeID)
        let expected = deliveredAt.addingTimeInterval(600)
        let drift = abs(record.snoozedUntil!.timeIntervalSince(expected))
        #expect(drift < 1.0)

        let pending = await fake.pendingNotificationRequests()
        let trigger = pending.first?.trigger as? UNCalendarNotificationTrigger
        #expect(trigger != nil)
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
