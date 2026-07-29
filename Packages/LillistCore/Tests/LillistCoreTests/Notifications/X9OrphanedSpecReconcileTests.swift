import Testing
import Foundation
import UserNotifications
@testable import LillistCore

/// X9 — `NotificationScheduler.reconcileOrphanedPendingRequests()`: a
/// `NotificationSpec` deleted on another device can't be resolved to a
/// taskID from persistent history (no attribute is flagged
/// `preservesValueInHistoryOnDeletion`; relationships are never tombstoned
/// regardless — see the plan doc's investigation). This sweeps every
/// locally-pending request and cancels any whose `specID` no longer
/// resolves to a live `NotificationSpec` row — the mechanism itself, not
/// just the `RemoteChangeReconciler` wiring that triggers it
/// (`RemoteChangeReconcilerTests`'s `processPendingHistoryFires...` tests
/// cover that half).
@Suite("X9 — NotificationScheduler.reconcileOrphanedPendingRequests")
struct X9OrphanedSpecReconcileTests {
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

    @Test("cancels a pending request whose spec no longer exists")
    func cancelsOrphanedPending() async throws {
        let (_, store, specs, fake, scheduler) = try await makeStack()
        let taskID = try await store.create(title: "T")
        try await store.update(id: taskID) { d in
            d.deadline = Date().addingTimeInterval(3600); d.deadlineHasTime = true
        }
        let specID = try await scheduler.addOffset(taskID: taskID, anchor: .deadline, offsetMinutes: -10)
        #expect(await fake.addedCount() == 1)

        // Simulate a remote deletion: the spec row is gone, but the pending
        // OS request this device already scheduled for it is not — exactly
        // the state a foreign NotificationSpec DELETE leaves behind.
        try await specs.delete(id: specID)

        await scheduler.reconcileOrphanedPendingRequests()

        #expect(await fake.pendingNotificationRequests().isEmpty)
    }

    @Test("preserves a pending request whose spec still exists")
    func preservesLivePending() async throws {
        let (_, store, _, fake, scheduler) = try await makeStack()
        let taskID = try await store.create(title: "T")
        try await store.update(id: taskID) { d in
            d.deadline = Date().addingTimeInterval(3600); d.deadlineHasTime = true
        }
        _ = try await scheduler.addOffset(taskID: taskID, anchor: .deadline, offsetMinutes: -10)
        #expect(await fake.addedCount() == 1)

        await scheduler.reconcileOrphanedPendingRequests()

        #expect(await fake.pendingNotificationRequests().count == 1, "a still-live spec's pending request must not be touched by the orphan sweep")
    }

    @Test("cancels only the orphaned request, leaving a still-live sibling pending")
    func cancelsOnlyOrphanAmongMultiple() async throws {
        let (_, store, specs, fake, scheduler) = try await makeStack()
        let taskID = try await store.create(title: "T")
        try await store.update(id: taskID) { d in
            d.deadline = Date().addingTimeInterval(3600); d.deadlineHasTime = true
        }
        let orphanID = try await scheduler.addOffset(taskID: taskID, anchor: .deadline, offsetMinutes: -10)
        _ = try await scheduler.addOffset(taskID: taskID, anchor: .deadline, offsetMinutes: -30)
        #expect(await fake.addedCount() == 2)

        try await specs.delete(id: orphanID)

        await scheduler.reconcileOrphanedPendingRequests()

        let pending = await fake.pendingNotificationRequests()
        #expect(pending.count == 1)
        #expect(pending.first?.content.userInfo["specID"] as? String != orphanID.uuidString)
    }

    @Test("a request belonging to a different device's fingerprint is never touched")
    func ignoresOtherDeviceRequests() async throws {
        let (_, store, specs, fake, scheduler) = try await makeStack()
        let taskID = try await store.create(title: "T")
        try await store.update(id: taskID) { d in
            d.deadline = Date().addingTimeInterval(3600); d.deadlineHasTime = true
        }
        let specID = try await scheduler.addOffset(taskID: taskID, anchor: .deadline, offsetMinutes: -10)
        try await specs.delete(id: specID)

        // A foreign device's own pending request for the same (now-deleted)
        // spec — this device must never touch another device's requests.
        let foreignRequest = UNNotificationRequest(
            identifier: "\(specID.uuidString)#devB",
            content: {
                let c = UNMutableNotificationContent()
                c.userInfo = ["taskID": taskID.uuidString, "specID": specID.uuidString]
                return c
            }(),
            trigger: nil
        )
        try await fake.add(foreignRequest)

        await scheduler.reconcileOrphanedPendingRequests()

        let pending = await fake.pendingNotificationRequests()
        #expect(pending.map(\.identifier) == ["\(specID.uuidString)#devB"], "reconcileOrphanedPendingRequests must only ever touch this device's own (#devA) pending requests")
    }

    @Test("no-op when nothing is pending")
    func noOpWhenEmpty() async throws {
        let (_, _, _, fake, scheduler) = try await makeStack()
        await scheduler.reconcileOrphanedPendingRequests()
        #expect(await fake.pendingNotificationRequests().isEmpty)
        #expect(await fake.removedIdentifiersLog().isEmpty)
    }
}
