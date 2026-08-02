import Testing
import Foundation
import CoreData
@testable import LillistCore

/// `LIL-90` — snooze is device-local, which makes a remote in-place snooze edit
/// *unrepresentable* rather than merely unreachable.
///
/// The original residual: `RemoteChangeReconciler` ignores in-place
/// `NotificationSpec` edits, so a `snoozedUntil` written on another device
/// never rescheduled here. It was filed as latent because nothing could trigger
/// it. `LIL-83`'s time-zone prompt would have made it reachable — so rather than
/// widen the reconciler to cover snooze, snooze left the synced entity entirely.
@Suite("Snooze state — device-local partition")
struct SnoozeStatePartitionTests {

    private func suite() -> String { "SnoozeStateTests-\(UUID().uuidString)" }

    // MARK: - The store

    @Test("A snooze round-trips")
    func roundTrip() async {
        let store = SnoozeStateStore(suiteName: suite())
        let id = UUID()
        let until = Date().addingTimeInterval(600)

        await store.setSnoozedUntil(until, specID: id)

        let read = await store.snoozedUntil(specID: id)
        #expect(read?.timeIntervalSince1970 == until.timeIntervalSince1970)
    }

    @Test("An elapsed snooze reads as absent and is cleaned up on read")
    func elapsedSnoozeIsCleared() async {
        let store = SnoozeStateStore(suiteName: suite())
        let id = UUID()
        let past = Date().addingTimeInterval(-60)

        // Written with a `now` in the past so the setter accepts it.
        await store.setSnoozedUntil(past, specID: id, now: past.addingTimeInterval(-10))
        #expect(await store.snoozedUntil(specID: id) == nil)
        // Cleaned up, not merely filtered — a second read finds nothing stored.
        #expect(await store.snoozedSpecIDs().contains(id) == false)
    }

    @Test("Setting a nil or already-elapsed date clears the snooze")
    func clearingSemantics() async {
        let store = SnoozeStateStore(suiteName: suite())
        let id = UUID()

        await store.setSnoozedUntil(Date().addingTimeInterval(600), specID: id)
        await store.setSnoozedUntil(nil, specID: id)
        #expect(await store.snoozedUntil(specID: id) == nil)

        await store.setSnoozedUntil(Date().addingTimeInterval(600), specID: id)
        await store.setSnoozedUntil(Date().addingTimeInterval(-1), specID: id)
        #expect(await store.snoozedUntil(specID: id) == nil)
    }

    @Test("Snoozes are per-spec, never shared")
    func perSpecIsolation() async {
        let store = SnoozeStateStore(suiteName: suite())
        let a = UUID(), b = UUID()
        await store.setSnoozedUntil(Date().addingTimeInterval(600), specID: a)

        #expect(await store.snoozedUntil(specID: a) != nil)
        #expect(await store.snoozedUntil(specID: b) == nil)
    }

    @Test("prune drops entries whose spec no longer exists, and keeps live ones")
    func pruneRemovesDeadEntries() async {
        let store = SnoozeStateStore(suiteName: suite())
        let live = UUID(), dead = UUID()
        let until = Date().addingTimeInterval(600)
        await store.setSnoozedUntil(until, specID: live)
        await store.setSnoozedUntil(until, specID: dead)

        await store.prune(liveSpecIDs: [live])

        #expect(await store.snoozedUntil(specID: live) != nil, "a live spec's snooze must survive")
        #expect(await store.snoozedUntil(specID: dead) == nil)
    }

    @Test("prune leaves unrelated App Group keys alone")
    func pruneIsNamespaced() async {
        let name = suite()
        let defaults = UserDefaults(suiteName: name)!
        defaults.set("keep me", forKey: "lillist.devicePrefs.quickCaptureHotkey")
        let store = SnoozeStateStore(suiteName: name)
        await store.setSnoozedUntil(Date().addingTimeInterval(600), specID: UUID())

        await store.prune(liveSpecIDs: [])

        #expect(defaults.string(forKey: "lillist.devicePrefs.quickCaptureHotkey") == "keep me")
    }

    // MARK: - The synced column is dead

    @Test("The store never projects Core Data's snoozedUntil column")
    func recordNeverReadsTheColumn() async throws {
        let controller = try await TestStore.make()
        let tasks = TaskStore(persistence: controller)
        let specs = NotificationSpecStore(persistence: controller)
        let taskID = try await tasks.create(title: "Take medication")
        let specID = try await specs.add(taskID: taskID, kind: .defaultStart, offsetMinutes: nil, fireDate: nil)

        // Simulate a peer still on the old build writing the legacy column.
        let ctx = controller.container.viewContext
        try await ctx.perform {
            let req = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
            req.predicate = NSPredicate(format: "id == %@", specID as CVarArg)
            let m = try #require(try ctx.fetch(req).first)
            m.snoozedUntil = Date().addingTimeInterval(3600)
            try ctx.save()
        }

        // The record must ignore it — that write is inert, not authoritative.
        #expect(try await specs.fetch(id: specID).snoozedUntil == nil)
    }

    @Test("update() does not write the snooze column, even when a caller sets it on the draft")
    func updateIgnoresSnoozeDraft() async throws {
        let controller = try await TestStore.make()
        let tasks = TaskStore(persistence: controller)
        let specs = NotificationSpecStore(persistence: controller)
        let taskID = try await tasks.create(title: "Take medication")
        let specID = try await specs.add(taskID: taskID, kind: .defaultStart, offsetMinutes: nil, fireDate: nil)

        try await specs.update(id: specID) { $0.snoozedUntil = Date().addingTimeInterval(3600) }

        let ctx = controller.container.viewContext
        let stored: Date? = try await ctx.perform {
            let req = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
            req.predicate = NSPredicate(format: "id == %@", specID as CVarArg)
            return try ctx.fetch(req).first?.snoozedUntil
        }
        #expect(stored == nil, "LIL-90: a synced snooze is what made the remote in-place edit reachable")
    }

    // MARK: - Migration

    @Test("The migrator carries a live snooze across, once")
    func migratorCarriesLiveSnooze() async throws {
        let controller = try await TestStore.make()
        let tasks = TaskStore(persistence: controller)
        let specs = NotificationSpecStore(persistence: controller)
        let taskID = try await tasks.create(title: "Take medication")
        let specID = try await specs.add(taskID: taskID, kind: .defaultStart, offsetMinutes: nil, fireDate: nil)
        let until = Date().addingTimeInterval(3600)

        let ctx = controller.container.viewContext
        try await ctx.perform {
            let req = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
            req.predicate = NSPredicate(format: "id == %@", specID as CVarArg)
            try #require(try ctx.fetch(req).first).snoozedUntil = until
            try ctx.save()
        }

        let name = suite()
        let snooze = SnoozeStateStore(suiteName: name)
        let prefs = DevicePreferencesStore(suiteName: name)
        let migrator = SnoozeStatePartitionMigrator(
            persistence: controller, snoozeState: snooze, devicePreferences: prefs
        )

        #expect(try await migrator.runIfNeeded() == .migrated(count: 1))
        #expect(await snooze.snoozedUntil(specID: specID) != nil, "an active snooze must survive the upgrade")
        // Idempotent — a second launch must not re-scan.
        #expect(try await migrator.runIfNeeded() == .alreadyMigrated)
    }

    @Test("The migrator skips an already-elapsed snooze")
    func migratorSkipsElapsed() async throws {
        let controller = try await TestStore.make()
        let tasks = TaskStore(persistence: controller)
        let specs = NotificationSpecStore(persistence: controller)
        let taskID = try await tasks.create(title: "Take medication")
        let specID = try await specs.add(taskID: taskID, kind: .defaultStart, offsetMinutes: nil, fireDate: nil)

        let ctx = controller.container.viewContext
        try await ctx.perform {
            let req = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
            req.predicate = NSPredicate(format: "id == %@", specID as CVarArg)
            try #require(try ctx.fetch(req).first).snoozedUntil = Date().addingTimeInterval(-3600)
            try ctx.save()
        }

        let name = suite()
        let snooze = SnoozeStateStore(suiteName: name)
        let migrator = SnoozeStatePartitionMigrator(
            persistence: controller,
            snoozeState: snooze,
            devicePreferences: DevicePreferencesStore(suiteName: name)
        )

        #expect(try await migrator.runIfNeeded() == .migrated(count: 0))
        #expect(await snooze.snoozedUntil(specID: specID) == nil)
    }
}
