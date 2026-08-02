import Testing
import Foundation
@testable import LillistCore

/// `LIL-83` — reminders carry the zone they were scheduled in, so every device
/// resolves the same absolute instant.
///
/// The fault these replace: each device resolved an all-day reminder through its
/// own `TimeZone.current`, so two devices in two zones computed two different
/// instants and the `lastFiredAt` dedup guard — which compares instants — could
/// not suppress the second. Both fired.
///
/// The pre-existing `X10TimezoneDedupKnownLimitationTests` pins the OLD
/// behaviour as a known limitation. This suite is its replacement: same
/// scenario, now asserting agreement instead of documenting divergence.
@Suite("Reminder time zones — cross-device agreement")
struct ReminderTimeZoneTests {

    private let newYork = TimeZone(identifier: "America/New_York")!
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    /// A scheduler standing in for one device in one zone.
    private func scheduler(
        in zone: TimeZone,
        persistence: PersistenceController,
        hour: Int = 9,
        minute: Int = 0
    ) -> NotificationScheduler {
        NotificationScheduler(
            persistence: persistence,
            specs: NotificationSpecStore(persistence: persistence),
            center: FakeUserNotificationCenter(),
            snoozeRegistry: SnoozeRegistry(
                defaultAllDayHour: hour, defaultAllDayMinute: minute, timeZone: zone
            ),
            deviceFingerprint: "device-\(zone.identifier)",
            defaultAllDayHour: hour,
            defaultAllDayMinute: minute,
            timeZone: zone
        )
    }

    private func spec(
        zoneID: String?,
        kind: NotificationKind = .defaultStart
    ) -> NotificationSpecStore.SpecRecord {
        .init(
            id: UUID(),
            taskID: UUID(),
            kind: kind,
            offsetMinutes: nil,
            fireDate: nil,
            lastFiredAt: nil,
            snoozedUntil: nil,
            scheduledTimeZoneID: zoneID,
            createdAt: Date()
        )
    }

    /// An all-day task on 2026-03-10.
    private func allDayTask() -> NotificationScheduler.TaskSnapshot {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 3; comps.day = 10
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return .init(
            id: UUID(),
            title: "Take medication",
            status: .todo,
            start: cal.date(from: comps),
            startHasTime: false,
            deadline: nil,
            deadlineHasTime: false,
            deletedAt: nil
        )
    }

    // MARK: - The X10 fault, now fixed

    @Test("Two devices in different zones compute the SAME instant for a zone-stamped all-day reminder")
    func crossZoneDevicesAgree() async throws {
        let controller = try await TestStore.make()
        let task = allDayTask()
        // The user scheduled this in New York. Both devices must honour that.
        let anchored = spec(zoneID: newYork.identifier)

        let east = scheduler(in: newYork, persistence: controller)
        let west = scheduler(in: losAngeles, persistence: controller)
        let farEast = scheduler(in: tokyo, persistence: controller)

        let a = await east.computeFireDate(for: anchored, task: task)
        let b = await west.computeFireDate(for: anchored, task: task)
        let c = await farEast.computeFireDate(for: anchored, task: task)

        #expect(a != nil)
        #expect(a == b, "LIL-83: the whole point — the device's own zone must not change the answer")
        #expect(b == c)
    }

    @Test("Without a stored zone, devices still diverge — the legacy behaviour, deliberately preserved")
    func legacySpecsStillResolveLocally() async throws {
        let controller = try await TestStore.make()
        let task = allDayTask()
        let legacy = spec(zoneID: nil)

        let east = scheduler(in: newYork, persistence: controller)
        let west = scheduler(in: losAngeles, persistence: controller)

        let a = await east.computeFireDate(for: legacy, task: task)
        let b = await west.computeFireDate(for: legacy, task: task)

        // Pre-LIL-83 rows are NOT backfilled: inventing a zone the user never
        // chose would be worse than leaving today's behaviour in place. This
        // divergence is expected and is what the reschedule prompt resolves.
        #expect(a != b, "a legacy spec must keep resolving through the device zone")
    }

    @Test("The stored zone, not the device zone, sets the wall-clock hour")
    func storedZoneSetsWallClock() async throws {
        let controller = try await TestStore.make()
        let task = allDayTask()
        let anchored = spec(zoneID: newYork.identifier)

        // A device in Tokyo resolving a New York reminder must produce 09:00 in
        // NEW YORK, which is 22:00 the same day in Tokyo — not 09:00 Tokyo.
        let farEast = scheduler(in: tokyo, persistence: controller)
        let fire = try #require(await farEast.computeFireDate(for: anchored, task: task))

        var nyCal = Calendar(identifier: .gregorian)
        nyCal.timeZone = newYork
        #expect(nyCal.component(.hour, from: fire) == 9)
        #expect(nyCal.component(.minute, from: fire) == 0)
    }

    @Test("An unparseable stored zone falls back to the device zone rather than dropping the reminder")
    func corruptZoneFallsBack() async throws {
        let controller = try await TestStore.make()
        let task = allDayTask()
        let corrupt = spec(zoneID: "Not/AZone")

        let east = scheduler(in: newYork, persistence: controller)
        let viaCorrupt = await east.computeFireDate(for: corrupt, task: task)
        let viaLegacy = await east.computeFireDate(for: spec(zoneID: nil), task: task)

        #expect(viaCorrupt != nil, "a corrupt zone must never silently cancel a reminder")
        #expect(viaCorrupt == viaLegacy)
    }

    @Test("A time-bearing (non-all-day) anchor is unaffected by the stored zone")
    func timeBearingAnchorIgnoresZone() async throws {
        let controller = try await TestStore.make()
        let exact = Date(timeIntervalSince1970: 1_800_000_000)
        var task = allDayTask()
        task = .init(
            id: task.id, title: task.title, status: .todo,
            start: exact, startHasTime: true,
            deadline: nil, deadlineHasTime: false,
            deletedAt: nil
        )

        let east = scheduler(in: newYork, persistence: controller)
        let west = scheduler(in: losAngeles, persistence: controller)

        // An absolute instant is already unambiguous; zones must not perturb it.
        #expect(await east.computeFireDate(for: spec(zoneID: newYork.identifier), task: task) == exact)
        #expect(await west.computeFireDate(for: spec(zoneID: tokyo.identifier), task: task) == exact)
    }

    // MARK: - Persistence round-trip

    @Test("scheduledTimeZoneID round-trips through the store")
    func zoneRoundTrips() async throws {
        let controller = try await TestStore.make()
        let tasks = TaskStore(persistence: controller)
        let specs = NotificationSpecStore(persistence: controller)
        let taskID = try await tasks.create(title: "Take medication")

        let specID = try await specs.add(
            taskID: taskID, kind: .defaultStart, offsetMinutes: nil, fireDate: nil,
            scheduledTimeZoneID: newYork.identifier
        )
        #expect(try await specs.fetch(id: specID).scheduledTimeZoneID == newYork.identifier)

        try await specs.update(id: specID) { $0.scheduledTimeZoneID = tokyo.identifier }
        #expect(try await specs.fetch(id: specID).scheduledTimeZoneID == tokyo.identifier)
    }

    @Test("A spec added without a zone is legacy-shaped, not empty-string-shaped")
    func absentZoneIsNil() async throws {
        let controller = try await TestStore.make()
        let tasks = TaskStore(persistence: controller)
        let specs = NotificationSpecStore(persistence: controller)
        let taskID = try await tasks.create(title: "Take medication")

        let specID = try await specs.add(taskID: taskID, kind: .defaultStart, offsetMinutes: nil, fireDate: nil)
        #expect(try await specs.fetch(id: specID).scheduledTimeZoneID == nil)
    }
}
