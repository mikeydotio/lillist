import Testing
import Foundation
import UserNotifications
@testable import LillistCore

@Suite("NotificationScheduler — Layer 1 (time-bearing dates)")
struct NotificationSchedulerLayer1TimeBearingTests {
    @Test("Setting deadline with time schedules a defaultDeadline request")
    func deadlineWithTimeSchedules() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let scheduler = NotificationScheduler(
            persistence: p,
            specs: specs,
            center: fake,
            snoozeRegistry: registry,
            deviceFingerprint: "devA",
            defaultAllDayHour: 9,
            defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )

        let taskID = try await tasks.create(title: "Submit report")
        let when = Date().addingTimeInterval(7 * 24 * 3600)
        try await tasks.update(id: taskID) { d in
            d.deadline = when
            d.deadlineHasTime = true
        }
        await scheduler.reconcile(taskID: taskID)

        let pending = await fake.pendingNotificationRequests()
        #expect(pending.count == 1)
        let r = pending[0]
        #expect(r.identifier.hasSuffix("#devA"))
        #expect(r.content.categoryIdentifier == "lillist.defaultDeadline")
    }

    @Test("Clearing the deadline removes the pending request")
    func clearDeadlineRemoves() async throws {
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
        let when = Date().addingTimeInterval(7 * 24 * 3600)
        try await tasks.update(id: taskID) { d in d.deadline = when; d.deadlineHasTime = true }
        await scheduler.reconcile(taskID: taskID)
        #expect(await fake.addedCount() == 1)

        try await tasks.update(id: taskID) { d in d.deadline = nil; d.deadlineHasTime = false }
        await scheduler.reconcile(taskID: taskID)
        let pending = await fake.pendingNotificationRequests()
        #expect(pending.isEmpty)
    }

    @Test("Reconcile is idempotent: calling twice produces one pending request")
    func idempotent() async throws {
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
        let when = Date().addingTimeInterval(3600)
        try await tasks.update(id: taskID) { d in d.deadline = when; d.deadlineHasTime = true }
        await scheduler.reconcile(taskID: taskID)
        await scheduler.reconcile(taskID: taskID)
        let pending = await fake.pendingNotificationRequests()
        #expect(pending.count == 1)
    }
}
