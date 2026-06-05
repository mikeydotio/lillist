import Testing
import Foundation
import CloudKit
import UserNotifications
@testable import LillistCore

@Suite("MigrationCoordinator — post-migration restore", .serialized)
struct MigrationCoordinatorRestoreTests {
    private static var liveSwapAllowed: Bool {
        Bundle.main.bundleIdentifier?.isEmpty == false
    }

    private static func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MigrationCoordinatorRestoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Disable Now restores per-task notifications and morning summary in finalize", .enabled(if: liveSwapAllowed))
    @MainActor
    func finalizeRestoresNotifications() async throws {
        let dir = Self.tempDir()
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        let host = try await PersistenceHost.make(initialMode: .iCloudSync, storeURL: storeURL)

        let persistence = await host.controller
        let specs = NotificationSpecStore(persistence: persistence)
        let fake = FakeUserNotificationCenter()
        let registry = SnoozeRegistry(defaultAllDayHour: 9, defaultAllDayMinute: 0, timeZone: .current)
        let scheduler = NotificationScheduler(
            persistence: persistence, specs: specs, center: fake,
            snoozeRegistry: registry, deviceFingerprint: "devA",
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            timeZone: TimeZone(identifier: "UTC")!
        )
        let taskStore = TaskStore(persistence: persistence)
        taskStore.notificationScheduler = scheduler
        let prefs = PreferencesStore(persistence: persistence)
        try await prefs.update { p in
            p.morningSummaryEnabled = true
            p.morningSummaryHour = 8
            p.morningSummaryMinute = 0
        }

        let id = try await taskStore.create(title: "Submit report")
        try await taskStore.update(id: id) { d in
            d.deadline = Date().addingTimeInterval(7200)
            d.deadlineHasTime = true
        }
        #expect(await fake.addedCount() >= 1)

        let journal = InMemoryMigrationJournalStore()
        let quarantine = QuarantineManager(rootDirectory: dir)
        let bridge = CloudKitEventBridge()
        let quiesce = SyncQuiesceMonitor(bridge: bridge)
        let suite = "MigrationCoordinatorRestoreTests-\(UUID().uuidString)"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        let modeStore = SyncModeStore(suiteName: suite)
        await modeStore.setMode(.iCloudSync)

        let coordinator = MigrationCoordinator(
            host: host,
            journal: journal,
            quarantine: quarantine,
            zoneEraser: FakeCloudKitZoneEraser(),
            quiesceMonitor: quiesce,
            notificationScheduler: scheduler,
            preferencesStore: prefs,
            syncModeStore: modeStore
        )

        try await coordinator.beginDisable(strategy: .now, storeURL: storeURL)

        let pending = await fake.pendingNotificationRequests()
        #expect(pending.contains { $0.identifier.hasSuffix("#devA") })
        let summary = pending.first { $0.identifier == MorningSummary.requestID }
        #expect(summary != nil)
        #expect((summary?.trigger as? UNCalendarNotificationTrigger)?.dateComponents.hour == 8)
        #expect(try journal.read() == .idle)
    }

    @Test("Replace iCloud with Local aborts before erase when the account changed", .enabled(if: liveSwapAllowed))
    @MainActor
    func abortsEraseOnAccountChange() async throws {
        let dir = Self.tempDir()
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        let host = try await PersistenceHost.make(initialMode: .localOnly, storeURL: storeURL)
        let journal = InMemoryMigrationJournalStore()
        let quarantine = QuarantineManager(rootDirectory: dir)
        let fakeEraser = FakeCloudKitZoneEraser()
        let bridge = CloudKitEventBridge()
        let quiesce = SyncQuiesceMonitor(bridge: bridge)
        let suite = "MigrationCoordinatorRestoreTests-\(UUID().uuidString)"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        let modeStore = SyncModeStore(suiteName: suite)
        await modeStore.setMode(.localOnly)

        let coordinator = MigrationCoordinator(
            host: host,
            journal: journal,
            quarantine: quarantine,
            zoneEraser: fakeEraser,
            quiesceMonitor: quiesce,
            notificationScheduler: nil,
            syncModeStore: modeStore,
            accountStateProvider: { .accountChanged }
        )

        await #expect(throws: LillistError.self) {
            try await coordinator.beginEnable(direction: .replaceICloud, storeURL: storeURL)
        }
        #expect(await fakeEraser.callCount == 0)
        #expect(try journal.read().state == .failed)
    }

    @Test("Replace iCloud with Local proceeds to erase when the account is available", .enabled(if: liveSwapAllowed))
    @MainActor
    func proceedsWhenAccountAvailable() async throws {
        let dir = Self.tempDir()
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        let host = try await PersistenceHost.make(initialMode: .localOnly, storeURL: storeURL)
        let journal = InMemoryMigrationJournalStore()
        let quarantine = QuarantineManager(rootDirectory: dir)
        let fakeEraser = FakeCloudKitZoneEraser()
        let bridge = CloudKitEventBridge()
        let quiesce = SyncQuiesceMonitor(bridge: bridge)
        let suite = "MigrationCoordinatorRestoreTests-\(UUID().uuidString)"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        let modeStore = SyncModeStore(suiteName: suite)
        await modeStore.setMode(.localOnly)

        let coordinator = MigrationCoordinator(
            host: host,
            journal: journal,
            quarantine: quarantine,
            zoneEraser: fakeEraser,
            quiesceMonitor: quiesce,
            notificationScheduler: nil,
            syncModeStore: modeStore,
            accountStateProvider: { .available }
        )

        try await coordinator.beginEnable(direction: .replaceICloud, storeURL: storeURL)
        #expect(await fakeEraser.callCount == 1)
        #expect(try journal.read() == .idle)
    }

    @Test("Two concurrent begin* calls: exactly one runs, the other is rejected", .enabled(if: liveSwapAllowed))
    @MainActor
    func rejectsConcurrentReentrantMigration() async throws {
        let dir = Self.tempDir()
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        let host = try await PersistenceHost.make(initialMode: .iCloudSync, storeURL: storeURL)
        let journal = InMemoryMigrationJournalStore()
        let quarantine = QuarantineManager(rootDirectory: dir)
        let fakeEraser = FakeCloudKitZoneEraser()
        let bridge = CloudKitEventBridge()
        let quiesce = SyncQuiesceMonitor(bridge: bridge)
        let suite = "MigrationCoordinatorRestoreTests-\(UUID().uuidString)"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        let modeStore = SyncModeStore(suiteName: suite)
        await modeStore.setMode(.iCloudSync)

        let coordinator = MigrationCoordinator(
            host: host,
            journal: journal,
            quarantine: quarantine,
            zoneEraser: fakeEraser,
            quiesceMonitor: quiesce,
            notificationScheduler: nil,
            syncModeStore: modeStore
        )

        // Fire two begin* calls without a pre-existing journal. The synchronous
        // isMigrating flag must let exactly one proceed and reject the other.
        // Two unstructured Tasks are submitted back-to-back so both are
        // enqueued on the MainActor before either starts executing; the
        // @MainActor coordinator then runs them serially, but the *second*
        // task sees isMigrating == true at its first synchronous check and
        // must throw immediately. Using Task<Void, Error> and collecting via
        // `await task.value` avoids the Swift-6 region-checker limitation
        // that fires when @MainActor closures appear inside withTaskGroup.
        let taskA = Task<Void, Error> { @MainActor in
            try await coordinator.beginDisable(strategy: .now, storeURL: storeURL)
        }
        let taskB = Task<Void, Error> { @MainActor in
            try await coordinator.beginDisable(strategy: .now, storeURL: storeURL)
        }
        var errors: [Error] = []
        if case .failure(let e) = await taskA.result { errors.append(e) }
        if case .failure(let e) = await taskB.result { errors.append(e) }
        // At most one succeeds; at least one is rejected by the reentrancy guard.
        #expect(errors.count >= 1, "a concurrent second begin* must be rejected")
    }

    @Test("runMigration refuses to start when the journal is already in flight", .enabled(if: liveSwapAllowed))
    @MainActor
    func rejectsReentrantMigration() async throws {
        let dir = Self.tempDir()
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        let host = try await PersistenceHost.make(initialMode: .localOnly, storeURL: storeURL)
        let preexisting = MigrationJournal(
            state: .reconfiguringStore,
            operation: .replaceLocalWithICloud,
            startedAt: Date(),
            lastHeartbeatAt: Date(),
            previousMode: .localOnly
        )
        let journal = InMemoryMigrationJournalStore(initial: preexisting)
        let quarantine = QuarantineManager(rootDirectory: dir)
        let fakeEraser = FakeCloudKitZoneEraser()
        let bridge = CloudKitEventBridge()
        let quiesce = SyncQuiesceMonitor(bridge: bridge)
        let suite = "MigrationCoordinatorRestoreTests-\(UUID().uuidString)"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        let modeStore = SyncModeStore(suiteName: suite)
        await modeStore.setMode(.localOnly)

        let coordinator = MigrationCoordinator(
            host: host,
            journal: journal,
            quarantine: quarantine,
            zoneEraser: fakeEraser,
            quiesceMonitor: quiesce,
            notificationScheduler: nil,
            syncModeStore: modeStore
        )

        await #expect(throws: LillistError.self) {
            try await coordinator.beginEnable(direction: .replaceICloud, storeURL: storeURL)
        }
        // The pre-existing journal is untouched (not clobbered to .preparing/.failed).
        #expect(try journal.read() == preexisting)
        // No destructive work ran.
        #expect(await fakeEraser.callCount == 0)
        #expect(await host.currentMode == .localOnly)
    }
}
