import Testing
import Foundation
import UserNotifications
@testable import LillistCore

@Suite("NotificationScheduler — Layer 1 (time-bearing dates: no auto-defaults)")
struct NotificationSchedulerLayer1TimeBearingTests {
    @Test("A deadline alone schedules nothing — defaults are not auto-created")
    func deadlineSchedulesNothing() async throws {
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

        // No default notification is created from a bare deadline.
        #expect(await fake.pendingNotificationRequests().isEmpty)
        let allSpecs = try await specs.specs(forTask: taskID)
        #expect(allSpecs.contains { $0.kind == .defaultDeadline } == false)
    }

    @Test("A legacy default spec is purged on the next reconcile")
    func legacyDefaultPurged() async throws {
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
        // Simulate a default spec created before defaults were removed.
        _ = try await specs.add(taskID: taskID, kind: .defaultDeadline, offsetMinutes: nil, fireDate: nil)

        await scheduler.reconcile(taskID: taskID)

        let remaining = try await specs.specs(forTask: taskID)
        #expect(remaining.contains { $0.kind == .defaultDeadline } == false)
        #expect(await fake.pendingNotificationRequests().isEmpty)
    }

    @Test("Reconcile is idempotent for a user offset reminder")
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
        _ = try await scheduler.addOffset(taskID: taskID, anchor: .deadline, offsetMinutes: -10)
        await scheduler.reconcile(taskID: taskID)
        await scheduler.reconcile(taskID: taskID)
        let pending = await fake.pendingNotificationRequests()
        #expect(pending.count == 1)
    }
}
