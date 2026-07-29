import Testing
import Foundation
import UserNotifications
@testable import LillistCore

/// X10 — the all-day scheduler default was hardcoded 09:00 at construction
/// and never hydrated from `PreferencesStore`, so a fresh launch's first
/// reconcile compared a persisted-and-correct pending trigger (e.g. 07:30,
/// from an earlier session where the user changed the default) against the
/// wrong in-memory default and rewrote it back to 09:00. The actual fix is
/// the bootstrap call site in both `AppEnvironment.swift`s (not unit-
/// testable — no host-side test target reaches app-composition-root code,
/// matching this program's established pattern; verified via unsigned
/// `xcodebuild` builds instead). This suite proves the mechanism that call
/// site depends on: hydrating via `updateDefaultAllDayTime` BEFORE any
/// other reconcile runs preserves an already-correct pending trigger.
@Suite("X10 — all-day default hydration prevents the reconcile-rewrite bug")
struct X10AllDayDefaultHydrationTests {
    @Test("hydrating the default before any other reconcile preserves an already-correct pending trigger")
    func hydrationPreventsRewrite() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        // The pre-hydration construction default (09:00) — mirrors both
        // AppEnvironment.init()s' literal constructor arguments, which the
        // bootstrap-time hydration call now corrects before any reconcile
        // can observe the mismatch.
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )

        let taskID = try await tasks.create(title: "T")
        try await tasks.update(id: taskID) { d in
            // All-day (no time component) deadline tomorrow — its reminder
            // resolves through the configured default hour/minute.
            d.deadline = Date().addingTimeInterval(86_400); d.deadlineHasTime = false
        }
        _ = try await scheduler.addOffset(taskID: taskID, anchor: .deadline, offsetMinutes: 0)

        let scheduledAt09 = await fake.pendingNotificationRequests().first
        let triggerAt09 = scheduledAt09?.trigger as? UNCalendarNotificationTrigger
        #expect(triggerAt09?.dateComponents.hour == 9, "sanity check: scheduled against the unhydrated 09:00 default")

        // The fix: hydrate from the persisted preference (simulated here as
        // 07:30) BEFORE anything else reconciles — exactly what
        // AppEnvironment.bootstrap() now does immediately after
        // preferencesStore.normalizeSingletons(), ahead of
        // remoteChangeReconciler's own catch-up pass.
        await scheduler.updateDefaultAllDayTime(hour: 7, minute: 30)

        let pending = await fake.pendingNotificationRequests()
        #expect(pending.count == 1, "hydration must not duplicate the request — it's the same spec, just re-triggered at the corrected time")
        let trigger = pending.first?.trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.dateComponents.hour == 7)
        #expect(trigger?.dateComponents.minute == 30)
    }

    @Test("hydrating with the SAME value the trigger already reflects is a true no-op")
    func hydrationWithMatchingValueIsNoOp() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 7, defaultAllDayMinute: 30, timeZone: .current)
        // Already hydrated correctly at construction — the common-case
        // shape once X10's fix is live and the persisted default hasn't
        // changed since the last launch.
        let scheduler = NotificationScheduler(
            persistence: p, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 7, defaultAllDayMinute: 30,
            timeZone: TimeZone(identifier: "UTC")!
        )

        let taskID = try await tasks.create(title: "T")
        try await tasks.update(id: taskID) { d in
            d.deadline = Date().addingTimeInterval(86_400); d.deadlineHasTime = false
        }
        _ = try await scheduler.addOffset(taskID: taskID, anchor: .deadline, offsetMinutes: 0)
        let before = await fake.pendingNotificationRequests().first?.identifier

        await scheduler.updateDefaultAllDayTime(hour: 7, minute: 30)

        let after = await fake.pendingNotificationRequests()
        #expect(after.count == 1)
        #expect(after.first?.identifier == before, "re-hydrating with the value that already produced the pending trigger must not remove-and-re-add it")
    }
}
