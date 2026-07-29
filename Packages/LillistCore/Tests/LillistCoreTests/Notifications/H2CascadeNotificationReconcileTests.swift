import Testing
import Foundation
import CoreData
import UserNotifications
@testable import LillistCore

/// H2 — `softDelete`/`restore` only reconciled the ROOT task's notifications,
/// even though both cascade `deletedAt`/`archivedAt` onto every descendant
/// (`applySoftDelete`/`clearSoftDelete` already walk the whole subtree — see
/// `1a`'s H7 cycle-guard fix). A trashed subtree's descendants kept firing
/// (their specs were never told the task is now deleted); a restored
/// subtree's descendants never got their specs re-installed.
@Suite("H2 — softDelete/restore cascade notification reconcile")
struct H2CascadeNotificationReconcileTests {
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

    @Test("softDelete cancels the ROOT's pending notification (existing behavior, still true)")
    func softDeleteCancelsRootNotification() async throws {
        let (_, store, _, fake, scheduler) = try await makeStack()
        let id = try await store.create(title: "T")
        try await addDeadlineReminder(taskID: id, store: store, scheduler: scheduler)
        #expect(await fake.addedCount() == 1)

        try await store.softDelete(id: id)

        #expect(await fake.pendingNotificationRequests().isEmpty)
    }

    @Test("softDelete cancels a DESCENDANT's pending notification too")
    func softDeleteCancelsDescendantNotification() async throws {
        let (_, store, _, fake, scheduler) = try await makeStack()
        let parentID = try await store.create(title: "parent")
        let childID = try await store.create(title: "child", parent: parentID)
        try await addDeadlineReminder(taskID: parentID, store: store, scheduler: scheduler)
        try await addDeadlineReminder(taskID: childID, store: store, scheduler: scheduler)
        #expect(await fake.addedCount() == 2)

        try await store.softDelete(id: parentID)

        let pending = await fake.pendingNotificationRequests()
        #expect(pending.isEmpty, "the child's pending notification must be cancelled too — it was cascaded into the trash along with its parent")
    }

    @Test("softDelete cancels notifications for a multi-level subtree")
    func softDeleteCancelsGrandchildNotification() async throws {
        let (_, store, _, fake, scheduler) = try await makeStack()
        let rootID = try await store.create(title: "root")
        let childID = try await store.create(title: "child", parent: rootID)
        let grandchildID = try await store.create(title: "grandchild", parent: childID)
        try await addDeadlineReminder(taskID: grandchildID, store: store, scheduler: scheduler)
        #expect(await fake.addedCount() == 1)

        try await store.softDelete(id: rootID)

        #expect(await fake.pendingNotificationRequests().isEmpty, "a grandchild two levels down must also lose its pending notification")
    }

    @Test("restore re-installs the ROOT's pending notification (existing behavior, still true)")
    func restoreReinstallsRootNotification() async throws {
        let (_, store, _, fake, scheduler) = try await makeStack()
        let id = try await store.create(title: "T")
        try await addDeadlineReminder(taskID: id, store: store, scheduler: scheduler)
        try await store.softDelete(id: id)
        #expect(await fake.pendingNotificationRequests().isEmpty)

        try await store.restore(id: id)

        #expect(await fake.pendingNotificationRequests().count == 1)
    }

    @Test("restore re-installs a DESCENDANT's pending notification too")
    func restoreReinstallsDescendantNotification() async throws {
        let (_, store, _, fake, scheduler) = try await makeStack()
        let parentID = try await store.create(title: "parent")
        let childID = try await store.create(title: "child", parent: parentID)
        try await addDeadlineReminder(taskID: parentID, store: store, scheduler: scheduler)
        try await addDeadlineReminder(taskID: childID, store: store, scheduler: scheduler)
        try await store.softDelete(id: parentID)
        #expect(await fake.pendingNotificationRequests().isEmpty)

        try await store.restore(id: parentID)

        let pending = await fake.pendingNotificationRequests()
        #expect(pending.count == 2, "both the parent's and the child's reminders must come back — the child was cascaded into the trash and back out again")
        let taskIDs = Set(pending.compactMap { $0.content.userInfo["taskID"] as? String })
        #expect(taskIDs == Set([parentID.uuidString, childID.uuidString]))
    }

    @Test("restore does not reconcile an unrelated sibling that was never trashed")
    func restoreDoesNotTouchUnrelatedTask() async throws {
        let (_, store, _, fake, scheduler) = try await makeStack()
        let id = try await store.create(title: "T")
        let siblingID = try await store.create(title: "sibling")
        try await addDeadlineReminder(taskID: id, store: store, scheduler: scheduler)
        try await addDeadlineReminder(taskID: siblingID, store: store, scheduler: scheduler)
        try await store.softDelete(id: id)
        #expect(await fake.pendingNotificationRequests().count == 1)

        try await store.restore(id: id)

        let pending = await fake.pendingNotificationRequests()
        #expect(pending.count == 2)
        let taskIDs = Set(pending.compactMap { $0.content.userInfo["taskID"] as? String })
        #expect(taskIDs == Set([id.uuidString, siblingID.uuidString]))
    }

    @Test("softDelete/restore with no notificationScheduler set is a no-op, not a crash")
    func withoutSchedulerNoOps() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let parentID = try await store.create(title: "parent")
        _ = try await store.create(title: "child", parent: parentID)

        try await store.softDelete(id: parentID)
        try await store.restore(id: parentID)
        // No crash is the assertion; confirm the restore actually ran.
        let restored = try await store.fetch(id: parentID)
        #expect(restored.deletedAt == nil)
    }
}
