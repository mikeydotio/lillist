import Testing
import Foundation
import CoreData
import UserNotifications
@testable import LillistCore

/// H3 — `hardDelete`, `purgeAll`, and `AutoPurgeJob.run` all permanently
/// remove `LillistTask` rows with no notification-scheduler awareness: a
/// purged task's OS-level reminder still fires later, and its deep link
/// dangles. Critically, the existing `notificationScheduler?.reconcile(taskID:)`
/// pattern used by every other mutation (`update`, `transition`,
/// `softDelete`, `restore`) does NOT work here — `reconcile` starts by
/// fetching the task from `viewContext`, and after a hard delete the row is
/// entirely gone, so `reconcile` throws `.notFound` internally and its own
/// top-level `catch` silently swallows it. `NotificationReconciling.cancelPending(forTaskIDs:)`
/// is the new mechanism: it matches pending requests via
/// `request.content.userInfo["taskID"]` directly, never touching the store,
/// so it works whether or not the row still exists.
@Suite("H3 — purge/hard-delete cancels pending OS notifications")
struct H3PurgeNotificationCancellationTests {
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

    private func addDeadlineReminder(taskID: UUID, store: TaskStore, scheduler: NotificationScheduler) async throws {
        try await store.update(id: taskID) { d in
            d.deadline = Date().addingTimeInterval(3600); d.deadlineHasTime = true
        }
        _ = try await scheduler.addOffset(taskID: taskID, anchor: .deadline, offsetMinutes: -10)
    }

    @Test("hardDelete cancels the task's own pending notification")
    func hardDeleteCancelsOwnNotification() async throws {
        let (_, store, _, fake, scheduler) = try await makeStack()
        let id = try await store.create(title: "T")
        try await addDeadlineReminder(taskID: id, store: store, scheduler: scheduler)
        #expect(await fake.addedCount() == 1)

        try await store.hardDelete(id: id)

        #expect(await fake.pendingNotificationRequests().isEmpty)
    }

    @Test("hardDelete cancels every descendant's pending notification too")
    func hardDeleteCancelsDescendantNotifications() async throws {
        let (_, store, _, fake, scheduler) = try await makeStack()
        let parentID = try await store.create(title: "parent")
        let childID = try await store.create(title: "child", parent: parentID)
        try await addDeadlineReminder(taskID: parentID, store: store, scheduler: scheduler)
        try await addDeadlineReminder(taskID: childID, store: store, scheduler: scheduler)
        #expect(await fake.addedCount() == 2)

        try await store.hardDelete(id: parentID)

        #expect(await fake.pendingNotificationRequests().isEmpty)
    }

    @Test("hardDelete with no notificationScheduler set is a no-op, not a crash")
    func hardDeleteWithoutSchedulerNoOps() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "T")
        try await store.hardDelete(id: id)
        await #expect(throws: LillistError.notFound) {
            _ = try await store.fetch(id: id)
        }
    }

    @Test("purgeAll cancels pending notifications for every purged task")
    func purgeAllCancelsNotifications() async throws {
        let (_, store, _, fake, scheduler) = try await makeStack()
        let parentID = try await store.create(title: "parent")
        let childID = try await store.create(title: "child", parent: parentID)
        let survivorID = try await store.create(title: "survivor")
        try await addDeadlineReminder(taskID: parentID, store: store, scheduler: scheduler)
        try await addDeadlineReminder(taskID: childID, store: store, scheduler: scheduler)
        try await addDeadlineReminder(taskID: survivorID, store: store, scheduler: scheduler)
        #expect(await fake.addedCount() == 3)

        try await store.softDelete(id: parentID)
        let purged = try await store.purgeAll()
        #expect(purged == 2)

        let pending = await fake.pendingNotificationRequests()
        #expect(pending.count == 1)
        #expect(pending.first?.content.userInfo["taskID"] as? String == survivorID.uuidString)
    }

    @Test("AutoPurgeJob cancels pending notifications for every purged task")
    func autoPurgeJobCancelsNotifications() async throws {
        let (p, store, _, fake, scheduler) = try await makeStack()
        let prefs = PreferencesStore(persistence: p)
        try await prefs.update { $0.trashRetentionDays = 0 }
        let id = try await store.create(title: "T")
        try await addDeadlineReminder(taskID: id, store: store, scheduler: scheduler)
        #expect(await fake.addedCount() == 1)

        try await store.softDelete(id: id)
        try await p.container.viewContext.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            let m = try p.container.viewContext.fetch(req).first!
            m.deletedAt = Date().addingTimeInterval(-86_400)
            try p.container.viewContext.save()
        }

        let job = AutoPurgeJob(persistence: p, preferences: prefs)
        job.notificationScheduler = scheduler
        let purged = try await job.run()
        #expect(purged == 1)

        #expect(await fake.pendingNotificationRequests().isEmpty)
    }

    @Test("AutoPurgeJob with no notificationScheduler set purges cleanly, no crash")
    func autoPurgeJobWithoutSchedulerNoOps() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let prefs = PreferencesStore(persistence: p)
        try await prefs.update { $0.trashRetentionDays = 0 }
        let id = try await store.create(title: "T")
        try await store.softDelete(id: id)
        try await p.container.viewContext.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            let m = try p.container.viewContext.fetch(req).first!
            m.deletedAt = Date().addingTimeInterval(-86_400)
            try p.container.viewContext.save()
        }

        let job = AutoPurgeJob(persistence: p, preferences: prefs)
        let purged = try await job.run()
        #expect(purged == 1)
    }
}
