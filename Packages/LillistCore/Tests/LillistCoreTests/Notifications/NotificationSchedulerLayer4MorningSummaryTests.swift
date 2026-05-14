import Testing
import Foundation
import UserNotifications
@testable import LillistCore

@Suite("NotificationScheduler — Layer 4 (morning summary)")
struct NotificationSchedulerLayer4MorningSummaryTests {
    @Test("installMorningSummary schedules a repeating request with the well-known ID")
    func installs() async throws {
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

        await scheduler.installMorningSummary(hour: 7, minute: 15)
        let pending = await fake.pendingNotificationRequests()
        #expect(pending.count == 1)
        let r = pending[0]
        #expect(r.identifier == MorningSummary.requestID)
        #expect(r.content.categoryIdentifier == MorningSummary.categoryID)
        let trigger = r.trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.repeats == true)
        #expect(trigger?.dateComponents.hour == 7)
        #expect(trigger?.dateComponents.minute == 15)
    }

    @Test("Calling installMorningSummary twice replaces (one pending)")
    func replaces() async throws {
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

        await scheduler.installMorningSummary(hour: 7, minute: 0)
        await scheduler.installMorningSummary(hour: 8, minute: 0)
        let pending = await fake.pendingNotificationRequests()
        #expect(pending.count == 1)
        let trigger = pending[0].trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.dateComponents.hour == 8)
    }

    @Test("uninstallMorningSummary removes the pending request")
    func uninstalls() async throws {
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

        await scheduler.installMorningSummary(hour: 7, minute: 0)
        await scheduler.uninstallMorningSummary()
        let pending = await fake.pendingNotificationRequests()
        #expect(pending.isEmpty)
    }
}
