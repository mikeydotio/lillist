import Testing
import Foundation
import UserNotifications
@testable import LillistCore

@Suite("NotificationScheduler — DST safety")
struct NotificationSchedulerDSTTests {
    @Test("Scheduling at 09:00 the day before US spring-forward yields a calendar trigger at 09:00")
    func dstSpringForward() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let nyc = TimeZone(identifier: "America/New_York")!
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: nyc
        )

        // 2099-03-08 is a Sunday before a (hypothetical) DST transition.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = nyc
        let comps = DateComponents(year: 2099, month: 3, day: 8, hour: 9, minute: 0)
        let when = cal.date(from: comps)!

        let taskID = try await tasks.create(title: "T")
        try await tasks.update(id: taskID) { d in
            d.deadline = when
            d.deadlineHasTime = true
        }
        // Defaults removed — drive the DST-safe trigger via a user offset (0).
        _ = try await scheduler.addOffset(taskID: taskID, anchor: .deadline, offsetMinutes: 0)

        let pending = await fake.pendingNotificationRequests()
        let trigger = pending[0].trigger as? UNCalendarNotificationTrigger
        // Trigger stores components, not interval — the system reapplies the
        // calendar at fire time so 09:00 remains 09:00 regardless of DST.
        #expect(trigger?.dateComponents.hour == 9)
        #expect(trigger?.dateComponents.minute == 0)
        #expect(trigger?.dateComponents.timeZone == nyc)
    }

    @Test("All-day date during DST transition still uses configured default hour:minute")
    func allDayDuringDST() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 7, defaultAllDayMinute: 0, timeZone: TimeZone(identifier: "America/New_York")!)
        let nyc = TimeZone(identifier: "America/New_York")!
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 7, defaultAllDayMinute: 0,
            timeZone: nyc
        )

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = nyc
        let comps = DateComponents(year: 2099, month: 3, day: 8)
        let allDay = cal.date(from: comps)!

        let taskID = try await tasks.create(title: "T")
        try await tasks.update(id: taskID) { d in
            d.deadline = allDay
            d.deadlineHasTime = false
        }
        _ = try await scheduler.addOffset(taskID: taskID, anchor: .deadline, offsetMinutes: 0)

        let pending = await fake.pendingNotificationRequests()
        let trigger = pending[0].trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.dateComponents.hour == 7)
        #expect(trigger?.dateComponents.minute == 0)
        #expect(trigger?.dateComponents.timeZone == nyc)
    }
}
