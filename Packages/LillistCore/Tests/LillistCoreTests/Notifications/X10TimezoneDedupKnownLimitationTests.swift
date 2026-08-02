import Testing
import Foundation
import UserNotifications
@testable import LillistCore

/// X10 — **RESOLVED by `LIL-83` for zone-stamped reminders; this suite now
/// pins the residual LEGACY behaviour only.**
///
/// The original limitation: all-day fire times resolved the default
/// hour/minute in each device's OWN `TimeZone.current`, so two devices in
/// different zones computed different absolute instants for "the same"
/// reminder and the `lastFiredAt` dedup guard could not suppress the second.
///
/// `LIL-83` fixed that at the origin — a reminder now stores the zone it was
/// scheduled in (`NotificationSpec.scheduledTimeZoneID`) and every device
/// resolves through *that*, so all devices agree. See
/// `ReminderTimeZoneTests.crossZoneDevicesAgree`, which asserts the inverse of
/// `differingTimeZoneDevicesBothFire` below.
///
/// What survives, and why this suite survives with it: reminders created
/// **before** `LIL-83` carry no zone and are deliberately **not** backfilled —
/// writing a zone the user never chose would invent intent, and backfilling on
/// two devices in two zones would manufacture the very disagreement the change
/// removes. Those legacy rows keep resolving through the device zone and can
/// still double-fire. `TimeZoneChangeDetector`'s prompt is how a user resolves
/// it; until then, this is the behaviour, and it is pinned here so it stays
/// *known* rather than rediscovered.
///
/// The council decision this originally cited
/// (`.council/x10-all-day-timezone-dedup-posture/DECISION.md`, a synced
/// "home time zone" field on `AppPreferences`) was **superseded** — see
/// `docs/spec/reminder-timezones.md` for why storing the zone per reminder
/// beat a global setting.
///
/// **`LIL-86` fix (discovered during `5a`'s verification):** both tests
/// used to anchor their simulated deadline at `Date().addingTimeInterval
/// (86_400)` — the live wall clock. `NotificationScheduler.computeDesired
/// Requests`'s dedup check (`lastFired >= fireDate - 60s`) compares
/// **absolute** instants, and whether Tokyo's or Los Angeles's respective
/// "9am on the calendar day of the deadline" lands later in UTC flips
/// depending on which side of a ~15:00 UTC boundary the live "now" happens
/// to fall on when the suite runs (Tokyo's calendar day rolls over to the
/// next date, relative to LA's, once the deadline instant's UTC hour is
/// late enough in the day) — a genuine day-alignment race against the
/// wall clock, not a timing flake. Both tests now anchor to a fixed,
/// explicit UTC instant (`fixedDeadlineUTC`, year 2099, matching
/// `NotificationSchedulerDSTTests`'s own far-future-fixed-date convention)
/// chosen so Tokyo's calendar day is deterministically one day ahead of
/// Los Angeles's for that instant — see `fixedDeadlineUTC`'s own doc
/// comment for the exact derivation. This also keeps both fire dates
/// comfortably in the future relative to any real "now" this suite could
/// ever run at, sidestepping `computeDesiredRequests`'s separate
/// past-due-fire-date filter too.
@Suite("X10 — LEGACY (zone-less) all-day dedup is still timezone-scoped")
struct X10TimezoneDedupKnownLimitationTests {
    /// A fixed, explicit UTC instant standing in for "the task's deadline,"
    /// replacing the old `Date().addingTimeInterval(86_400)` (the source of
    /// `LIL-86`'s flakiness). `2099-06-15T20:00:00Z` is chosen deliberately:
    /// at UTC+9 with no DST, `Asia/Tokyo`'s calendar day for this instant is
    /// `2099-06-16` (20:00 UTC + 9h = 05:00 the next day, Tokyo-local); at
    /// UTC-7/-8, `America/Los_Angeles`'s calendar day is `2099-06-15`
    /// regardless of whether DST applies that far out (20:00 UTC - 7h/-8h =
    /// 12:00/13:00 the same day, LA-local) — so Tokyo's day is
    /// deterministically **one calendar day ahead** of LA's for this exact
    /// instant, which is what makes Tokyo's own computed 9am-local fire date
    /// land chronologically AFTER (not before) LA's, satisfying the dedup
    /// check's `>=` comparison in the direction the "not deduped" assertion
    /// needs — see the suite doc comment above for why that ordering is
    /// what determines pass/fail, not merely "far enough apart in each
    /// device's own frame."
    private static var fixedDeadlineUTC: Date {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        return utcCalendar.date(from: DateComponents(year: 2099, month: 6, day: 15, hour: 20, minute: 0, second: 0))!
    }

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
        let deadline = Self.fixedDeadlineUTC
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

    @Test("LEGACY (zone-less) specs: differing-timezone devices still diverge, not deduped")
    func differingTimeZoneDevicesBothFire() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let deadline = Self.fixedDeadlineUTC
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

        // Device B (Tokyo) computes a genuinely different absolute instant
        // for the "same" all-day reminder, chronologically AFTER device A's
        // recorded fire (see `fixedDeadlineUTC`'s doc comment for exactly
        // why) — outside the 60s dedup tolerance in the direction that
        // matters for the dedup check's `lastFired >= fireDate - 60s` test.
        let centerB = FakeUserNotificationCenter()
        let schedulerB = makeScheduler(
            fingerprint: "devB", timeZone: TimeZone(identifier: "Asia/Tokyo")!,
            center: centerB, persistence: p, specs: specs
        )
        await schedulerB.reconcile(taskID: taskID)

        #expect(await centerB.pendingNotificationRequests().isEmpty == false, "KNOWN LIMITATION: a differing-timezone device is NOT deduped against another device's fire — see LIL-83")
    }
}
