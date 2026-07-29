import Testing
import Foundation
import UserNotifications
@testable import LillistCore

/// X10 (council-decided, `.council/x10-all-day-timezone-dedup-posture/DECISION.md`)
/// — **KNOWN LIMITATION, tracked as `LIL-83`**: all-day fire times resolve
/// the configured default hour/minute in each device's OWN `TimeZone.current`
/// (see both `AppEnvironment.swift`s' `TODO(LIL-83)` markers), so two
/// devices in different time zones compute genuinely different absolute
/// instants for "the same" all-day reminder and the `lastFiredAt` cross-
/// device dedup guard does not suppress the second one. This pins that
/// behavior deliberately — same-timezone dedup (the common case) still
/// works and must keep working; cross-timezone divergence is a real,
/// tracked gap, not a silent regression risk hiding under "seems fine."
///
/// **Delete/invert this suite's `differingTimeZoneDevicesBothFire`
/// assertion once `LIL-83` ships** (a synced "home time zone" field on
/// `AppPreferences`, replacing per-device `.current`) — at that point two
/// devices in different zones should dedup exactly like the same-timezone
/// case below.
@Suite("X10 — KNOWN LIMITATION: all-day dedup is timezone-scoped (LIL-83)")
struct X10TimezoneDedupKnownLimitationTests {
    private func makeScheduler(
        fingerprint: String,
        timeZone: TimeZone,
        center: FakeUserNotificationCenter,
        persistence: PersistenceController,
        specs: NotificationSpecStore
    ) -> NotificationScheduler {
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: timeZone)
        return NotificationScheduler(
            persistence: persistence, specs: specs, center: center,
            snoozeRegistry: registry, deviceFingerprint: fingerprint,
            defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: timeZone
        )
    }

    /// Mirrors `NotificationScheduler.resolvedAnchorDate`'s exact algorithm
    /// (all-day date + configured hour:minute, resolved in `timeZone`) so
    /// the test can simulate "device A already fired at its own computed
    /// instant" without reconstructing a `Date` from a delivered trigger's
    /// `dateComponents` (fragile) or depending on a second live scheduler.
    private func computeAllDayFireDate(anchorDate: Date, hour: Int, minute: Int, timeZone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        var components = cal.dateComponents([.year, .month, .day], from: anchorDate)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return cal.date(from: components) ?? anchorDate
    }

    @Test("regression guard: same-timezone devices still dedup correctly")
    func sameTimeZoneDedupsCorrectly() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let deadline = Date().addingTimeInterval(86_400)
        try await tasks.update(id: taskID) { d in
            d.deadline = deadline; d.deadlineHasTime = false
        }
        let specID = try await specs.add(taskID: taskID, kind: .offsetDeadline, offsetMinutes: 0, fireDate: nil)

        let sharedTimeZone = TimeZone(identifier: "America/Los_Angeles")!
        let devAFireDate = computeAllDayFireDate(anchorDate: deadline, hour: 9, minute: 0, timeZone: sharedTimeZone)
        // Simulates "device A, same time zone, already fired."
        try await specs.recordLastFired(id: specID, at: devAFireDate)

        let centerB = FakeUserNotificationCenter()
        let schedulerB = makeScheduler(
            fingerprint: "devB", timeZone: sharedTimeZone,
            center: centerB, persistence: p, specs: specs
        )
        await schedulerB.reconcile(taskID: taskID)

        #expect(await centerB.pendingNotificationRequests().isEmpty, "same-timezone dedup must still work — this is NOT part of the known limitation")
    }

    @Test("KNOWN LIMITATION (LIL-83): differing-timezone devices legitimately diverge, not deduped")
    func differingTimeZoneDevicesBothFire() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let deadline = Date().addingTimeInterval(86_400)
        try await tasks.update(id: taskID) { d in
            d.deadline = deadline; d.deadlineHasTime = false
        }
        let specID = try await specs.add(taskID: taskID, kind: .offsetDeadline, offsetMinutes: 0, fireDate: nil)

        // Device A (Pacific) already fired at ITS computed instant.
        let devAFireDate = computeAllDayFireDate(
            anchorDate: deadline, hour: 9, minute: 0,
            timeZone: TimeZone(identifier: "America/Los_Angeles")!
        )
        try await specs.recordLastFired(id: specID, at: devAFireDate)

        // Device B (Tokyo, ~16-17h offset) computes a genuinely different
        // absolute instant for the "same" all-day reminder — well outside
        // the 60s dedup tolerance.
        let centerB = FakeUserNotificationCenter()
        let schedulerB = makeScheduler(
            fingerprint: "devB", timeZone: TimeZone(identifier: "Asia/Tokyo")!,
            center: centerB, persistence: p, specs: specs
        )
        await schedulerB.reconcile(taskID: taskID)

        #expect(await centerB.pendingNotificationRequests().isEmpty == false, "KNOWN LIMITATION: a differing-timezone device is NOT deduped against another device's fire — see LIL-83")
    }
}
