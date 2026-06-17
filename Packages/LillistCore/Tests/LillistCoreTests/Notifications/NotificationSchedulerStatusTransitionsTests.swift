import Testing
import Foundation
import UserNotifications
@testable import LillistCore

@Suite("NotificationScheduler — Status transitions")
struct NotificationSchedulerStatusTransitionsTests {
    private func makeScheduler(_ p: PersistenceController, fake: FakeUserNotificationCenter, specs: NotificationSpecStore) -> NotificationScheduler {
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        return NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )
    }

    @Test("Closing a task cancels all pending deliveries (user spec preserved)")
    func closedCancels() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let scheduler = makeScheduler(p, fake: fake, specs: specs)
        tasks.notificationScheduler = scheduler

        let taskID = try await tasks.create(title: "T")
        try await tasks.update(id: taskID) { d in
            d.deadline = Date().addingTimeInterval(3600); d.deadlineHasTime = true
        }
        // Defaults are no longer auto-created — a user reminder is what schedules.
        _ = try await scheduler.addOffset(taskID: taskID, anchor: .deadline, offsetMinutes: -10)
        #expect(await fake.addedCount() == 1)

        try await tasks.transition(id: taskID, to: .closed)
        let pending = await fake.pendingNotificationRequests()
        #expect(pending.isEmpty)

        // The user spec is preserved (offsetDeadline still in store, not cascaded away).
        let allSpecs = try await specs.specs(forTask: taskID)
        #expect(allSpecs.contains { $0.kind == .offsetDeadline })
    }

    @Test("Re-opening a closed task re-registers future specs")
    func reopenRegisters() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let scheduler = makeScheduler(p, fake: fake, specs: specs)
        tasks.notificationScheduler = scheduler

        let taskID = try await tasks.create(title: "T")
        try await tasks.update(id: taskID) { d in
            d.deadline = Date().addingTimeInterval(3600); d.deadlineHasTime = true
        }
        _ = try await scheduler.addOffset(taskID: taskID, anchor: .deadline, offsetMinutes: -10)
        try await tasks.transition(id: taskID, to: .closed)
        #expect(await fake.pendingNotificationRequests().isEmpty)

        try await tasks.transition(id: taskID, to: .todo)
        #expect(await fake.pendingNotificationRequests().count == 1)
    }

    @Test("Blocked tasks keep their notifications (design Section 4: not suppressed)")
    func blockedNotSuppressed() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let scheduler = makeScheduler(p, fake: fake, specs: specs)
        tasks.notificationScheduler = scheduler

        let taskID = try await tasks.create(title: "T")
        try await tasks.update(id: taskID) { d in
            d.deadline = Date().addingTimeInterval(3600); d.deadlineHasTime = true
        }
        _ = try await scheduler.addOffset(taskID: taskID, anchor: .deadline, offsetMinutes: -10)
        #expect(await fake.addedCount() == 1)

        try await tasks.transition(id: taskID, to: .blocked)
        #expect(await fake.pendingNotificationRequests().count == 1)
    }

    @Test("Soft-deleted tasks cancel all pending")
    func softDeleteCancels() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let scheduler = makeScheduler(p, fake: fake, specs: specs)
        tasks.notificationScheduler = scheduler

        let taskID = try await tasks.create(title: "T")
        try await tasks.update(id: taskID) { d in
            d.deadline = Date().addingTimeInterval(3600); d.deadlineHasTime = true
        }
        _ = try await scheduler.addOffset(taskID: taskID, anchor: .deadline, offsetMinutes: -10)
        #expect(await fake.addedCount() == 1)

        try await tasks.softDelete(id: taskID)
        #expect(await fake.pendingNotificationRequests().isEmpty)
    }

    @Test("Closing a recurring instance spawns the next, with no auto-scheduled default")
    func recurringSpawnHasNoDefault() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let scheduler = makeScheduler(p, fake: fake, specs: specs)
        tasks.notificationScheduler = scheduler

        let seedID = try await tasks.create(title: "Daily standup")
        try await tasks.update(id: seedID) { d in
            d.start = Date().addingTimeInterval(3600); d.startHasTime = true
        }
        _ = try await series.create(
            fromSeedTask: seedID,
            rule: .calendar(.init(freq: .daily, interval: 1))
        )
        await fake.reset()

        try await tasks.transition(id: seedID, to: .closed)

        // The spawn is created and reconciled, but defaults are no longer
        // auto-created and spawns don't copy user specs — so nothing is
        // scheduled for the spawn or the closed seed.
        let roots = try await tasks.children(of: nil)
        let spawn = roots.first { $0.id != seedID && $0.title == "Daily standup" }
        #expect(spawn != nil)
        #expect(await fake.pendingNotificationRequests().isEmpty)
    }
}
