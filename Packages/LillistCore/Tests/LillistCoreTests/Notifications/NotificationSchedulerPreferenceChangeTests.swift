import Testing
import Foundation
import UserNotifications
@testable import LillistCore

@Suite("NotificationScheduler — Preference change rescheduling")
struct NotificationSchedulerPreferenceChangeTests {
    @Test("Changing default all-day time reschedules existing all-day specs")
    func updateDefaultTime() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: TimeZone(identifier: "UTC")!)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )

        let taskID = try await tasks.create(title: "T")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = DateComponents(year: 2099, month: 1, day: 15)
        let allDay = cal.date(from: comps)!
        try await tasks.update(id: taskID) { d in
            d.deadline = allDay
            d.deadlineHasTime = false
        }
        await scheduler.reconcile(taskID: taskID)
        var pending = await fake.pendingNotificationRequests()
        var trigger = pending[0].trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.dateComponents.hour == 9)

        await scheduler.updateDefaultAllDayTime(hour: 17, minute: 30)
        pending = await fake.pendingNotificationRequests()
        trigger = pending[0].trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.dateComponents.hour == 17)
        #expect(trigger?.dateComponents.minute == 30)
    }
}
