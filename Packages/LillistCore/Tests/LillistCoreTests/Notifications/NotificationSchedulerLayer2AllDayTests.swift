import Testing
import Foundation
import UserNotifications
@testable import LillistCore

@Suite("NotificationScheduler — Layer 2 (all-day default time)")
struct NotificationSchedulerLayer2AllDayTests {
    @Test("All-day deadline fires at the default time on that date")
    func allDayDeadlineUsesDefault() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 8, defaultAllDayMinute: 30, timeZone: TimeZone(identifier: "UTC")!)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 8, defaultAllDayMinute: 30,
            timeZone: TimeZone(identifier: "UTC")!
        )

        let taskID = try await tasks.create(title: "All-day deadline")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = DateComponents(year: 2099, month: 6, day: 15)
        let allDayDate = cal.date(from: comps)!
        try await tasks.update(id: taskID) { d in
            d.deadline = allDayDate
            d.deadlineHasTime = false
        }
        // Defaults are no longer auto-created; a user offset reminder (offset
        // 0 = fire at the anchor) exercises the same all-day time resolution.
        _ = try await scheduler.addOffset(taskID: taskID, anchor: .deadline, offsetMinutes: 0)

        let pending = await fake.pendingNotificationRequests()
        #expect(pending.count == 1)
        let trigger = pending[0].trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.dateComponents.hour == 8)
        #expect(trigger?.dateComponents.minute == 30)
        #expect(trigger?.dateComponents.year == 2099)
        #expect(trigger?.dateComponents.month == 6)
        #expect(trigger?.dateComponents.day == 15)
    }

    @Test("Time-bearing date uses its own time, not the default")
    func timeBearingIgnoresDefault() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 8, defaultAllDayMinute: 30, timeZone: TimeZone(identifier: "UTC")!)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 8, defaultAllDayMinute: 30,
            timeZone: TimeZone(identifier: "UTC")!
        )

        let taskID = try await tasks.create(title: "T")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = DateComponents(year: 2099, month: 6, day: 15, hour: 14, minute: 0)
        let timed = cal.date(from: comps)!
        try await tasks.update(id: taskID) { d in
            d.deadline = timed
            d.deadlineHasTime = true
        }
        _ = try await scheduler.addOffset(taskID: taskID, anchor: .deadline, offsetMinutes: 0)

        let pending = await fake.pendingNotificationRequests()
        let trigger = pending[0].trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.dateComponents.hour == 14)
        #expect(trigger?.dateComponents.minute == 0)
    }
}
