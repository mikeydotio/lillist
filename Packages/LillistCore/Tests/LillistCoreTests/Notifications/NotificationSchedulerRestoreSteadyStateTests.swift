import Testing
import Foundation
import UserNotifications
@testable import LillistCore

@Suite("NotificationScheduler — restoreSteadyState (post-migration)")
struct NotificationSchedulerRestoreSteadyStateTests {

    /// Build a scheduler + the stores it sweeps, sharing one persistence stack.
    private func makeStack() async throws -> (PersistenceController, TaskStore, NotificationSpecStore, FakeUserNotificationCenter, NotificationScheduler) {
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
        let taskStore = TaskStore(persistence: p)
        taskStore.notificationScheduler = scheduler
        return (p, taskStore, specs, fake, scheduler)
    }

    @Test("restoreSteadyState re-installs a per-task deadline notification from a surviving spec")
    func reinstallsPerTaskNotification() async throws {
        let (_, taskStore, _, fake, scheduler) = try await makeStack()
        let id = try await taskStore.create(title: "Pay rent")
        let deadline = Date().addingTimeInterval(3600)
        try await taskStore.update(id: id) { d in
            d.deadline = deadline
            d.deadlineHasTime = true
        }
        // Defaults are no longer auto-created — a user reminder is the
        // surviving per-task spec restoreSteadyState re-installs.
        _ = try await scheduler.addOffset(taskID: id, anchor: .deadline, offsetMinutes: -10)
        await scheduler.cancelAllPending()
        #expect(await fake.addedCount() == 0)

        await scheduler.restoreSteadyState(morningSummaryEnabled: false, hour: 9, minute: 0)

        let pending = await fake.pendingNotificationRequests()
        #expect(pending.count == 1)
        #expect(pending[0].identifier.hasSuffix("#devA"))
        #expect(pending[0].content.userInfo["taskID"] as? String == id.uuidString)
        #expect(pending.contains { $0.identifier == MorningSummary.requestID } == false)
    }

    @Test("restoreSteadyState installs the morning summary when enabled")
    func installsMorningSummaryWhenEnabled() async throws {
        let (_, _, _, fake, scheduler) = try await makeStack()
        await scheduler.restoreSteadyState(morningSummaryEnabled: true, hour: 7, minute: 30)
        let pending = await fake.pendingNotificationRequests()
        let summary = pending.first { $0.identifier == MorningSummary.requestID }
        #expect(summary != nil)
        let trigger = summary?.trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.repeats == true)
        #expect(trigger?.dateComponents.hour == 7)
        #expect(trigger?.dateComponents.minute == 30)
    }

    @Test("restoreSteadyState uninstalls the morning summary when disabled")
    func uninstallsMorningSummaryWhenDisabled() async throws {
        let (_, _, _, fake, scheduler) = try await makeStack()
        await scheduler.installMorningSummary(hour: 9, minute: 0)
        #expect(await fake.pendingNotificationRequests().contains { $0.identifier == MorningSummary.requestID })
        await scheduler.restoreSteadyState(morningSummaryEnabled: false, hour: 9, minute: 0)
        #expect(await fake.pendingNotificationRequests().contains { $0.identifier == MorningSummary.requestID } == false)
    }

    @Test("cancelAllPending preserves the repeating morning-summary request")
    func cancelAllPendingPreservesMorningSummary() async throws {
        let (_, taskStore, _, fake, scheduler) = try await makeStack()
        await scheduler.installMorningSummary(hour: 9, minute: 0)
        let id = try await taskStore.create(title: "Call dentist")
        try await taskStore.update(id: id) { d in
            d.deadline = Date().addingTimeInterval(3600)
            d.deadlineHasTime = true
        }
        // Defaults removed — a user reminder provides the per-task pending.
        _ = try await scheduler.addOffset(taskID: id, anchor: .deadline, offsetMinutes: -10)
        #expect(await fake.pendingNotificationRequests().contains { $0.identifier == MorningSummary.requestID })
        #expect(await fake.pendingNotificationRequests().contains { $0.identifier.hasSuffix("#devA") })

        await scheduler.cancelAllPending()

        let pending = await fake.pendingNotificationRequests()
        #expect(pending.count == 1)
        #expect(pending[0].identifier == MorningSummary.requestID)
    }
}
