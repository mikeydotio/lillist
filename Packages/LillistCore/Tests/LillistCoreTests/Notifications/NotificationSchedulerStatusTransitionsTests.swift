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

    @Test("Closing a task cancels all pending deliveries (specs preserved)")
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
        await scheduler.reconcile(taskID: taskID)
        #expect(await fake.addedCount() == 1)

        try await tasks.transition(id: taskID, to: .closed)
        let pending = await fake.pendingNotificationRequests()
        #expect(pending.isEmpty)

        // Specs preserved (defaultDeadline still in store, not cascaded away).
        let allSpecs = try await specs.specs(forTask: taskID)
        #expect(allSpecs.contains { $0.kind == .defaultDeadline })
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
        await scheduler.reconcile(taskID: taskID)
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
        await scheduler.reconcile(taskID: taskID)
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
        await scheduler.reconcile(taskID: taskID)
        #expect(await fake.addedCount() == 1)

        try await tasks.softDelete(id: taskID)
        #expect(await fake.pendingNotificationRequests().isEmpty)
    }

    @Test("Closing a recurring instance schedules notifications on the spawn")
    func recurringSpawnGetsReconciled() async throws {
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

        // Spawn has been created and reconciled — pending requests include one
        // for the spawn's defaultStart, but none for the closed seed.
        // (Identifiers are "{specID}#{fingerprint}", so we match on
        // userInfo["taskID"] rather than the identifier prefix.)
        let pending = await fake.pendingNotificationRequests()
        let roots = try await tasks.children(of: nil)
        let spawn = roots.first { $0.id != seedID && $0.title == "Daily standup" }!
        #expect(pending.contains {
            ($0.content.userInfo["taskID"] as? String) == spawn.id.uuidString
        })
        #expect(pending.contains {
            ($0.content.userInfo["taskID"] as? String) == seedID.uuidString
        } == false)
    }
}
