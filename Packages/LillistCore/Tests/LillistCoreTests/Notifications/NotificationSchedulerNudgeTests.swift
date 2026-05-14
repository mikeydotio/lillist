import Testing
import Foundation
import UserNotifications
@testable import LillistCore

@Suite("NotificationScheduler — Nudges")
struct NotificationSchedulerNudgeTests {
    @Test("addNudge schedules a nudge-category request at the given fireDate")
    func addNudge() async throws {
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
        let when = Date().addingTimeInterval(3 * 24 * 3600)
        let nudgeID = try await scheduler.addNudge(taskID: taskID, fireDate: when)

        let pending = await fake.pendingNotificationRequests()
        #expect(pending.count == 1)
        #expect(pending[0].identifier == "\(nudgeID.uuidString)#devA")
        #expect(pending[0].content.categoryIdentifier == "lillist.nudge")
    }

    @Test("Nudges are independent of start/deadline")
    func nudgeIndependent() async throws {
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
        // No start, no deadline.
        let when = Date().addingTimeInterval(3 * 24 * 3600)
        _ = try await scheduler.addNudge(taskID: taskID, fireDate: when)
        let pending = await fake.pendingNotificationRequests()
        #expect(pending.count == 1)
    }
}
