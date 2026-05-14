import Testing
import Foundation
import UserNotifications
@testable import LillistCore

@Suite("NotificationScheduler — Layer 3 (per-task offsets)")
struct NotificationSchedulerLayer3OffsetTests {
    @Test("addOffset(.deadline, -60) creates a spec firing one hour before deadline")
    func addOffsetBeforeDeadline() async throws {
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
        let deadline = Date().addingTimeInterval(7 * 24 * 3600)
        try await tasks.update(id: taskID) { d in d.deadline = deadline; d.deadlineHasTime = true }

        let specID = try await scheduler.addOffset(taskID: taskID, anchor: .deadline, offsetMinutes: -60)
        await scheduler.reconcile(taskID: taskID)

        let pending = await fake.pendingNotificationRequests()
        // Two pending: the defaultDeadline + the offsetDeadline.
        #expect(pending.count == 2)
        let offsetReq = pending.first { $0.identifier.hasPrefix(specID.uuidString) }
        #expect(offsetReq?.content.categoryIdentifier == "lillist.offsetDeadline")
    }

    @Test("addOffset(.start, -30) creates a spec firing 30 minutes before start")
    func addOffsetBeforeStart() async throws {
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
        let start = Date().addingTimeInterval(7 * 24 * 3600)
        try await tasks.update(id: taskID) { d in d.start = start; d.startHasTime = true }

        _ = try await scheduler.addOffset(taskID: taskID, anchor: .start, offsetMinutes: -30)
        await scheduler.reconcile(taskID: taskID)

        let pending = await fake.pendingNotificationRequests()
        let offsetReq = pending.first { $0.content.categoryIdentifier == "lillist.offsetStart" }
        #expect(offsetReq != nil)
    }

    @Test("Offsets are skipped when the anchor field is nil")
    func offsetWithoutAnchorSkipped() async throws {
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
        _ = try await scheduler.addOffset(taskID: taskID, anchor: .start, offsetMinutes: -15)
        await scheduler.reconcile(taskID: taskID)
        let pending = await fake.pendingNotificationRequests()
        #expect(pending.isEmpty)
    }
}
