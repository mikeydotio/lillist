import Testing
import Foundation
import UserNotifications
@testable import LillistCore

@Suite("NotificationScheduler — Cross-device de-dup")
struct NotificationSchedulerCrossDeviceDedupTests {
    @Test("Identifier format is \"{specID}#{fingerprint}\"")
    func identifierFormat() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "phone-7",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )

        let taskID = try await tasks.create(title: "T")
        let nudgeID = try await scheduler.addNudge(taskID: taskID, fireDate: Date().addingTimeInterval(60))

        let pending = await fake.pendingNotificationRequests()
        #expect(pending[0].identifier == "\(nudgeID.uuidString)#phone-7")
    }

    @Test("Recording lastFiredAt removes the pending request on this device")
    func lastFiredRemoves() async throws {
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
        let fireDate = Date().addingTimeInterval(3600)
        let nudgeID = try await scheduler.addNudge(taskID: taskID, fireDate: fireDate)
        #expect(await fake.addedCount() == 1)

        // Simulate another device firing it; lastFiredAt is set in the spec.
        try await specs.recordLastFired(id: nudgeID, at: Date())
        await scheduler.reconcile(taskID: taskID)

        let pending = await fake.pendingNotificationRequests()
        #expect(pending.isEmpty)
    }

    @Test("Different device fingerprints produce different identifiers for the same spec")
    func differentDevicesDifferentIdentifiers() async throws {
        let p1 = try await TestStore.make()
        let p2 = try await TestStore.make()
        let tasks1 = TaskStore(persistence: p1)
        let specs1 = NotificationSpecStore(persistence: p1)
        let tasks2 = TaskStore(persistence: p2)
        let specs2 = NotificationSpecStore(persistence: p2)
        let fakeA = FakeUserNotificationCenter()
        let fakeB = FakeUserNotificationCenter()
        let registry1 = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let registry2 = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)

        let schedulerA = NotificationScheduler(
            persistence: p1, specs: specs1, center: fakeA,
            snoozeRegistry: registry1, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )
        let schedulerB = NotificationScheduler(
            persistence: p2, specs: specs2, center: fakeB,
            snoozeRegistry: registry2, deviceFingerprint: "devB",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )

        let taskA = try await tasks1.create(title: "T")
        let taskB = try await tasks2.create(title: "T")
        let nudgeA = try await schedulerA.addNudge(taskID: taskA, fireDate: Date().addingTimeInterval(60))
        let nudgeB = try await schedulerB.addNudge(taskID: taskB, fireDate: Date().addingTimeInterval(60))

        let pendingA = await fakeA.pendingNotificationRequests()
        let pendingB = await fakeB.pendingNotificationRequests()
        #expect(pendingA[0].identifier == "\(nudgeA.uuidString)#devA")
        #expect(pendingB[0].identifier == "\(nudgeB.uuidString)#devB")
    }
}
