import Testing
import Foundation
import CloudKit
import CoreData
@testable import LillistCore

/// `DataStoreResetService` orchestration, exercised end-to-end against
/// fakes (no live `NSPersistentCloudKitContainer`). The live destroy +
/// rebuild primitives are covered by `PersistenceHostTests`
/// (`liveSwapAllowed`-gated); here we assert the *ordering* and
/// *branching* the service is responsible for.
@Suite("DataStoreResetService", .serialized)
struct DataStoreResetServiceTests {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ResetSvc-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @MainActor
    private func makeService(
        startMode: SyncMode,
        host: FakePersistenceReconfigurer,
        eraser: any CloudKitZoneEraser,
        accountStateProvider: AccountStateProviding? = nil,
        propagator: ResetPropagator? = nil,
        exporter: Exporter? = nil,
        importer: Importer? = nil,
        backupReconciler: (any BackupPackageReconciling)? = nil,
        syncStatusReset: (@Sendable () async -> Void)? = nil,
        historyWatermarksReset: (() async -> Void)? = nil,
        widgetCacheReset: (() async -> Void)? = nil,
        quiesceMinQuietWindow: TimeInterval = 5,
        quiesceHardTimeout: TimeInterval = 300
    ) -> DataStoreResetService {
        DataStoreResetService(
            host: host,
            quarantine: QuarantineManager(rootDirectory: tempDir()),
            zoneEraser: eraser,
            quiesceMonitor: SyncQuiesceMonitor(bridge: CloudKitEventBridge()),
            notificationScheduler: nil,
            cloudKitContainerIdentifier: "iCloud.test",
            accountStateProvider: accountStateProvider,
            propagator: propagator,
            exporter: exporter,
            importer: importer,
            backupReconciler: backupReconciler,
            quiesceMinQuietWindow: quiesceMinQuietWindow,
            quiesceHardTimeout: quiesceHardTimeout,
            syncStatusReset: syncStatusReset,
            historyWatermarksReset: historyWatermarksReset,
            widgetCacheReset: widgetCacheReset
        )
    }

    @Test("localOnly: tears down then rebuilds, never erases the CloudKit zone")
    @MainActor
    func localOnlyWipesLocally() async throws {
        let host = FakePersistenceReconfigurer(initialMode: .localOnly)
        let eraser = FakeCloudKitZoneEraser()
        let service = makeService(startMode: .localOnly, host: host, eraser: eraser)

        try await service.resetAllData()

        #expect(await host.resetSteps == ["tearDown", "rebuild"])
        #expect(await eraser.callCount == 0)
    }

    @Test("iCloudSync: erases the zone exactly once and rebuilds empty")
    @MainActor
    func iCloudSyncErasesAndRebuilds() async throws {
        let host = FakePersistenceReconfigurer(initialMode: .iCloudSync)
        let eraser = FakeCloudKitZoneEraser()
        let service = makeService(startMode: .iCloudSync, host: host, eraser: eraser)

        // NOTE: the iCloudSync path waits on quiesceMonitor (minQuietWindow: 5s)
        // after the rebuild — this test intentionally takes ~5s to complete,
        // mirroring `MigrationRunnerExecutingTests.replaceICloudWithLocalExecutes`.
        try await service.resetAllData()

        #expect(await host.resetSteps == ["tearDown", "rebuild"])
        #expect(await eraser.callCount == 1)
        #expect(await eraser.lastContainerID == "iCloud.test")
    }

    @Test("iCloudSync: a post-rebuild quiesce timeout still COMPLETES the reset (S14 — nothing left to revert)")
    @MainActor
    func postRebuildQuiesceTimeoutStillCompletes() async throws {
        let host = FakePersistenceReconfigurer(initialMode: .iCloudSync)
        let eraser = FakeCloudKitZoneEraser()
        // No events ever fire, and hardTimeout sits below minQuietWindow,
        // so the wait can only ever time out — the destructive work
        // (tear down + erase + rebuild) already succeeded by that point,
        // so this must still complete rather than throw.
        let service = DataStoreResetService(
            host: host,
            quarantine: QuarantineManager(rootDirectory: tempDir()),
            zoneEraser: eraser,
            quiesceMonitor: SyncQuiesceMonitor(bridge: CloudKitEventBridge()),
            notificationScheduler: nil,
            cloudKitContainerIdentifier: "iCloud.test",
            quiesceMinQuietWindow: 1.0,
            quiesceHardTimeout: 0.05
        )

        try await service.resetAllData()

        #expect(await host.resetSteps == ["tearDown", "rebuild"])
        #expect(await eraser.callCount == 1)
    }

    @Test("iCloudSync: a failed zone erase re-attaches the store and never rebuilds")
    @MainActor
    func eraseFailureReattachesAndRethrows() async throws {
        let host = FakePersistenceReconfigurer(initialMode: .iCloudSync)
        let eraser = ThrowingZoneEraser()
        let service = makeService(startMode: .iCloudSync, host: host, eraser: eraser)

        await #expect(throws: LillistError.self) {
            try await service.resetAllData()
        }

        // Tear-down happened, the erase failed, so we re-attached the
        // original store and must NOT have destroyed/rebuilt anything.
        #expect(await host.resetSteps == ["tearDown", "reattach"])
        #expect(await eraser.callCount == 1)
    }

    @Test("localOnly: a failed rebuildEmptyStore re-attaches before rethrowing (S12)")
    @MainActor
    func rebuildFailureReattachesAndRethrows() async throws {
        // Unlike the erase-failure path above, this step had NO reattach
        // handler at all before S12 — a failure here left the
        // coordinator store-less until the next relaunch.
        let host = FakePersistenceReconfigurer(initialMode: .localOnly)
        await host.failOnRebuild()
        let eraser = FakeCloudKitZoneEraser()
        let service = makeService(startMode: .localOnly, host: host, eraser: eraser)

        await #expect(throws: LillistError.self) {
            try await service.resetAllData()
        }

        #expect(await host.resetSteps == ["tearDown", "rebuild", "reattach"])
        // localOnly never erases, regardless of the rebuild failure.
        #expect(await eraser.callCount == 0)
    }

    @Test("account-changed pre-flight aborts before any teardown or erase")
    @MainActor
    func accountChangedAbortsBeforeDestructiveWork() async throws {
        let host = FakePersistenceReconfigurer(initialMode: .iCloudSync)
        let eraser = FakeCloudKitZoneEraser()
        let provider: AccountStateProviding = { .accountChanged }
        let service = makeService(
            startMode: .iCloudSync, host: host, eraser: eraser, accountStateProvider: provider
        )

        await #expect(throws: LillistError.self) {
            try await service.resetAllData()
        }

        // Bailed before the store was touched and before the irreversible erase.
        #expect(await host.resetSteps == [])
        #expect(await eraser.callCount == 0)
    }

    // MARK: - Reset & Download (local rebuild, CloudKit zone preserved)

    @Test("redownload: tears down then rebuilds, never erases the CloudKit zone")
    @MainActor
    func redownloadRebuildsWithoutErasing() async throws {
        let host = FakePersistenceReconfigurer(initialMode: .iCloudSync)
        let eraser = FakeCloudKitZoneEraser()
        let service = makeService(startMode: .iCloudSync, host: host, eraser: eraser)

        // NOTE: like the iCloudSync wipe path, this waits on quiesceMonitor
        // (minQuietWindow: 5s) after the rebuild — the window in which the
        // surviving zone re-imports — so this test intentionally takes ~5s.
        try await service.resetAndRedownload()

        #expect(await host.resetSteps == ["tearDown", "rebuild"])
        // The whole point of redownload: the zone is preserved so it re-imports.
        #expect(await eraser.callCount == 0)
    }

    @Test("redownload: refuses in local-only mode (nothing to download) before any teardown")
    @MainActor
    func redownloadRequiresICloud() async throws {
        let host = FakePersistenceReconfigurer(initialMode: .localOnly)
        let eraser = FakeCloudKitZoneEraser()
        let service = makeService(startMode: .localOnly, host: host, eraser: eraser)

        await #expect(throws: LillistError.self) {
            try await service.resetAndRedownload()
        }

        // Guarded before any destructive work — no wipe, no erase.
        #expect(await host.resetSteps == [])
        #expect(await eraser.callCount == 0)
    }

    // MARK: - Reset Everywhere to Empty (propagating, issue #71)

    @Test("resetEverywhereToEmpty: wipes exactly like resetAllData, then broadcasts to every known peer")
    @MainActor
    func resetEverywhereToEmptyWipesThenBroadcasts() async throws {
        let host = FakePersistenceReconfigurer(initialMode: .iCloudSync)
        let eraser = FakeCloudKitZoneEraser()
        let kv = InMemoryKeyValueSyncStore()
        let roster = DeviceRoster(kv: kv)
        let inbox = ControlInbox(kv: kv)
        roster.register(id: "device-B", displayName: "Vertumnus")
        let propagator = ResetPropagator(
            roster: roster, inbox: inbox, deviceID: "device-A", deviceDisplayName: "Nephele"
        )
        let service = makeService(
            startMode: .iCloudSync, host: host, eraser: eraser, propagator: propagator
        )

        let outcome = try await service.resetEverywhereToEmpty()

        // Exactly the same wipe steps resetAllData() runs.
        #expect(await host.resetSteps == ["tearDown", "rebuild"])
        #expect(await eraser.callCount == 1)
        // ...and the peer was signalled.
        let pending = inbox.pendingEvents(for: "device-B")
        #expect(pending.count == 1)
        #expect(pending.first?.kind == .resetToEmpty)
        #expect(outcome == .notified(peerCount: 1))
    }

    @Test("resetEverywhereToEmpty: with no propagator configured, still wipes correctly and reports notConfigured")
    @MainActor
    func resetEverywhereToEmptyWithoutPropagatorStillWipes() async throws {
        let host = FakePersistenceReconfigurer(initialMode: .iCloudSync)
        let eraser = FakeCloudKitZoneEraser()
        let service = makeService(startMode: .iCloudSync, host: host, eraser: eraser)

        let outcome = try await service.resetEverywhereToEmpty()

        #expect(await host.resetSteps == ["tearDown", "rebuild"])
        #expect(await eraser.callCount == 1)
        #expect(outcome == .notConfigured)
    }

    @Test("S20: resetEverywhereToEmpty with a propagator but no known peers still wipes correctly and reports rosterEmpty, not silent success")
    @MainActor
    func resetEverywhereToEmptyWithNoKnownPeersReportsRosterEmpty() async throws {
        let host = FakePersistenceReconfigurer(initialMode: .iCloudSync)
        let eraser = FakeCloudKitZoneEraser()
        let kv = InMemoryKeyValueSyncStore()
        let roster = DeviceRoster(kv: kv)
        let inbox = ControlInbox(kv: kv)
        // No peers ever registered — e.g. a fresh install.
        let propagator = ResetPropagator(
            roster: roster, inbox: inbox, deviceID: "device-A", deviceDisplayName: "Nephele"
        )
        let service = makeService(
            startMode: .iCloudSync, host: host, eraser: eraser, propagator: propagator
        )

        let outcome = try await service.resetEverywhereToEmpty()

        #expect(await host.resetSteps == ["tearDown", "rebuild"])
        #expect(outcome == .rosterEmpty)
    }

    @Test("resetEverywhereToEmpty: a failed wipe never reaches the broadcast step")
    @MainActor
    func resetEverywhereToEmptyFailureSkipsBroadcast() async throws {
        let host = FakePersistenceReconfigurer(initialMode: .iCloudSync)
        let eraser = ThrowingZoneEraser()
        let kv = InMemoryKeyValueSyncStore()
        let roster = DeviceRoster(kv: kv)
        let inbox = ControlInbox(kv: kv)
        roster.register(id: "device-B", displayName: "Vertumnus")
        let propagator = ResetPropagator(
            roster: roster, inbox: inbox, deviceID: "device-A", deviceDisplayName: "Nephele"
        )
        let service = makeService(
            startMode: .iCloudSync, host: host, eraser: eraser, propagator: propagator
        )

        await #expect(throws: LillistError.self) {
            try await service.resetEverywhereToEmpty()
        }

        #expect(inbox.pendingEvents(for: "device-B").isEmpty)
    }

    // MARK: - Reset & Re-seed from this device (propagating, issue #71)

    @Test("resetAndReseedFromThisDevice: throws immediately without exporter/importer configured, no destructive work")
    @MainActor
    func resetAndReseedWithoutExporterImporterThrows() async throws {
        let host = FakePersistenceReconfigurer(initialMode: .iCloudSync)
        let eraser = FakeCloudKitZoneEraser()
        let service = makeService(startMode: .iCloudSync, host: host, eraser: eraser)

        await #expect(throws: LillistError.self) {
            try await service.resetAndReseedFromThisDevice()
        }

        #expect(await host.resetSteps == [])
        #expect(await eraser.callCount == 0)
    }

    @Test("resetAndReseedFromThisDevice: exports current data, wipes, re-imports it, then broadcasts — round-tripping real data through a real store")
    @MainActor
    func resetAndReseedRoundTripsRealData() async throws {
        // A REAL in-memory store, seeded with a task, so this test proves
        // the export -> wipe -> reimport sequence is actually
        // data-preserving — not just that the steps ran in order. The wipe
        // itself is exercised via the fake host (as every other test in
        // this suite does); the export/reimport pair operates on the real
        // controller underneath.
        let persistence = try await TestStore.make()
        let preferences = PreferencesStore(persistence: persistence)
        _ = try await preferences.read()
        let tasks = TaskStore(persistence: persistence)
        let seededID = try await tasks.create(title: "Buy milk")

        let host = FakePersistenceReconfigurer(initialMode: .iCloudSync)
        let eraser = FakeCloudKitZoneEraser()
        let kv = InMemoryKeyValueSyncStore()
        let roster = DeviceRoster(kv: kv)
        let inbox = ControlInbox(kv: kv)
        roster.register(id: "device-B", displayName: "Vertumnus")
        let propagator = ResetPropagator(
            roster: roster, inbox: inbox, deviceID: "device-A", deviceDisplayName: "Nephele"
        )
        let service = makeService(
            startMode: .iCloudSync, host: host, eraser: eraser,
            propagator: propagator,
            exporter: Exporter(persistence: persistence, preferences: preferences),
            importer: Importer(persistence: persistence),
            // S9c added a SECOND post-reimport quiesce wait beyond the
            // wipe's own — fast windows keep this test from doubling its
            // wall-clock time against the real 5s default.
            quiesceMinQuietWindow: 0.05, quiesceHardTimeout: 1
        )

        let outcome = try await service.resetAndReseedFromThisDevice()

        // The (faked) local+iCloud wipe ran exactly like resetAllData()'s.
        #expect(await host.resetSteps == ["tearDown", "rebuild"])
        #expect(await eraser.callCount == 1)
        // The exported snapshot survived the round trip back into the
        // (real) store.
        let survivor = try await tasks.fetch(id: seededID)
        #expect(survivor.title == "Buy milk")
        // ...and the peer was told to converge on this device's data.
        let pending = inbox.pendingEvents(for: "device-B")
        #expect(pending.count == 1)
        #expect(pending.first?.kind == .resetAndReseed)
        #expect(outcome == .notified(peerCount: 1))
    }

    @Test("resetAndReseedFromThisDevice: an attachment's bytes survive the reseed round trip (S9a)")
    @MainActor
    func resetAndReseedPreservesAttachmentBytes() async throws {
        // S9a: importBundle(at:conflictPolicy:) was called without
        // assetsDirectory, so the Importer's attachment-restore branch never
        // ran and every attachment was silently dropped on reseed.
        //
        // FakePersistenceReconfigurer (used by every other test in this
        // suite) never actually clears the underlying store, so a plain
        // before/after row check here would pass regardless of the bug —
        // the never-wiped original row would still be sitting there. This
        // test uses `RealWipingResetHost` instead, which genuinely deletes
        // every row in `tearDownStore`, so the post-reseed state can only
        // come from the reimport — the actual mechanism this finding is
        // about.
        let persistence = try await TestStore.make()
        let preferences = PreferencesStore(persistence: persistence)
        _ = try await preferences.read()
        let tasks = TaskStore(persistence: persistence)
        let attachments = AttachmentStore(persistence: persistence)
        let seededID = try await tasks.create(title: "Buy milk")
        let bytes = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let attachmentID = try await attachments.addFile(
            taskID: seededID, filename: "receipt.bin", uti: "public.data", data: bytes
        )

        let host = RealWipingResetHost(persistence: persistence, initialMode: .iCloudSync)
        let eraser = FakeCloudKitZoneEraser()
        let service = DataStoreResetService(
            host: host,
            quarantine: QuarantineManager(rootDirectory: tempDir()),
            zoneEraser: eraser,
            quiesceMonitor: SyncQuiesceMonitor(bridge: CloudKitEventBridge()),
            notificationScheduler: nil,
            cloudKitContainerIdentifier: "iCloud.test",
            exporter: Exporter(persistence: persistence, preferences: preferences),
            importer: Importer(persistence: persistence),
            // S9c's post-reimport quiesce wait — fast windows, see the
            // identical rationale in resetAndReseedRoundTripsRealData.
            quiesceMinQuietWindow: 0.05, quiesceHardTimeout: 1
        )

        try await service.resetAndReseedFromThisDevice()

        let survivor = try await attachments.fetch(id: attachmentID)
        #expect(survivor.byteSize == Int64(bytes.count))
        let restoredBytes = try await attachments.downloadData(id: attachmentID)
        #expect(restoredBytes == bytes)
        // The task itself must also have round-tripped — proves the wipe
        // was real (not merely a no-op the never-cleared original satisfied).
        let survivingTask = try await tasks.fetch(id: seededID)
        #expect(survivingTask.title == "Buy milk")
    }

    // MARK: - S9c: reseed broadcast waits for the re-export quiesce

    @Test("resetAndReseedFromThisDevice: a re-export quiesce timeout skips the broadcast (peers would otherwise pull a partial zone), but the reseed itself still reports success locally (S9c)")
    @MainActor
    func resetAndReseedQuiesceTimeoutSkipsBroadcast() async throws {
        let persistence = try await TestStore.make()
        let preferences = PreferencesStore(persistence: persistence)
        _ = try await preferences.read()
        let tasks = TaskStore(persistence: persistence)
        let seededID = try await tasks.create(title: "Buy milk")

        let host = FakePersistenceReconfigurer(initialMode: .iCloudSync)
        let eraser = FakeCloudKitZoneEraser()
        let kv = InMemoryKeyValueSyncStore()
        let roster = DeviceRoster(kv: kv)
        let inbox = ControlInbox(kv: kv)
        roster.register(id: "device-B", displayName: "Vertumnus")
        let propagator = ResetPropagator(
            roster: roster, inbox: inbox, deviceID: "device-A", deviceDisplayName: "Nephele"
        )
        // hardTimeout below minQuietWindow: no events ever fire, so the
        // wait can only ever time out — mirrors
        // postRebuildQuiesceTimeoutStillCompletes's identical setup.
        let service = DataStoreResetService(
            host: host,
            quarantine: QuarantineManager(rootDirectory: tempDir()),
            zoneEraser: eraser,
            quiesceMonitor: SyncQuiesceMonitor(bridge: CloudKitEventBridge()),
            notificationScheduler: nil,
            cloudKitContainerIdentifier: "iCloud.test",
            propagator: propagator,
            exporter: Exporter(persistence: persistence, preferences: preferences),
            importer: Importer(persistence: persistence),
            quiesceMinQuietWindow: 1.0, quiesceHardTimeout: 0.05
        )

        let outcome = try await service.resetAndReseedFromThisDevice()

        #expect(outcome == .skippedQuiesceTimedOut)
        // Nobody was told to redownload a possibly-partial zone.
        #expect(inbox.pendingEvents(for: "device-B").isEmpty)
        // The reseed itself still succeeded locally — this is a
        // propagation-only skip, not a failure.
        let survivor = try await tasks.fetch(id: seededID)
        #expect(survivor.title == "Buy milk")
    }

    @Test("resetAndReseedFromThisDevice: a localOnly reseed broadcasts without waiting for the re-export quiesce (S9c) — nothing to export or wait for")
    @MainActor
    func resetAndReseedLocalOnlyBroadcastsWithoutWaiting() async throws {
        let persistence = try await TestStore.make()
        let preferences = PreferencesStore(persistence: persistence)
        _ = try await preferences.read()

        let host = FakePersistenceReconfigurer(initialMode: .localOnly)
        let eraser = FakeCloudKitZoneEraser()
        let kv = InMemoryKeyValueSyncStore()
        let roster = DeviceRoster(kv: kv)
        let inbox = ControlInbox(kv: kv)
        roster.register(id: "device-B", displayName: "Vertumnus")
        let propagator = ResetPropagator(
            roster: roster, inbox: inbox, deviceID: "device-A", deviceDisplayName: "Nephele"
        )
        let service = makeService(
            startMode: .localOnly, host: host, eraser: eraser,
            propagator: propagator,
            exporter: Exporter(persistence: persistence, preferences: preferences),
            importer: Importer(persistence: persistence)
        )

        let outcome = try await service.resetAndReseedFromThisDevice()

        #expect(outcome == .notified(peerCount: 1))
        #expect(inbox.pendingEvents(for: "device-B").count == 1)
    }

    @Test("resetAndReseedFromThisDevice: cleans up its durable staging directory and journal on success (S9b)")
    @MainActor
    func resetAndReseedCleansUpTempDirectory() async throws {
        // S9b: staging moved from FileManager.default.temporaryDirectory
        // (OS-purgeable) to quarantine.rootDirectory/Reseed/<uuid>
        // (durable) — this test now proves that durable location is
        // cleaned up on success, not the old temp-dir location (which
        // this flow no longer touches at all).
        let persistence = try await TestStore.make()
        let preferences = PreferencesStore(persistence: persistence)
        _ = try await preferences.read()
        let host = FakePersistenceReconfigurer(initialMode: .iCloudSync)
        let eraser = FakeCloudKitZoneEraser()
        let quarantineRoot = tempDir()
        let reseedJournal = InMemoryReseedJournalStore()

        let service = DataStoreResetService(
            host: host,
            quarantine: QuarantineManager(rootDirectory: quarantineRoot),
            zoneEraser: eraser,
            quiesceMonitor: SyncQuiesceMonitor(bridge: CloudKitEventBridge()),
            notificationScheduler: nil,
            cloudKitContainerIdentifier: "iCloud.test",
            exporter: Exporter(persistence: persistence, preferences: preferences),
            importer: Importer(persistence: persistence),
            reseedJournal: reseedJournal,
            // S9c's post-reimport quiesce wait — fast windows, see the
            // identical rationale in resetAndReseedRoundTripsRealData.
            quiesceMinQuietWindow: 0.05, quiesceHardTimeout: 1
        )
        try await service.resetAndReseedFromThisDevice()

        let reseedRoot = quarantineRoot.appendingPathComponent("Reseed", isDirectory: true)
        let remaining = (try? FileManager.default.contentsOfDirectory(atPath: reseedRoot.path)) ?? []
        #expect(remaining.isEmpty)
        #expect(try reseedJournal.read() == .idle)
    }

    // MARK: - S9b: reseed durability + recovery

    @Test("resetAndReseedFromThisDevice: a failure BEFORE the wipe completes leaves localDataWiped=false and the staged bundle intact (S9b)")
    @MainActor
    func resetAndReseedPreWipeFailureLeavesLocalDataWipedFalse() async throws {
        let persistence = try await TestStore.make()
        let preferences = PreferencesStore(persistence: persistence)
        _ = try await preferences.read()
        let tasks = TaskStore(persistence: persistence)
        _ = try await tasks.create(title: "must survive an aborted reseed")

        let host = FakePersistenceReconfigurer(initialMode: .iCloudSync)
        // The erase fails — performReset re-attaches and rethrows BEFORE
        // rebuildEmptyStore ever runs, so the live store's data is
        // genuinely untouched.
        let eraser = ThrowingZoneEraser()
        let quarantineRoot = tempDir()
        let reseedJournal = InMemoryReseedJournalStore()
        let service = DataStoreResetService(
            host: host,
            quarantine: QuarantineManager(rootDirectory: quarantineRoot),
            zoneEraser: eraser,
            quiesceMonitor: SyncQuiesceMonitor(bridge: CloudKitEventBridge()),
            notificationScheduler: nil,
            cloudKitContainerIdentifier: "iCloud.test",
            exporter: Exporter(persistence: persistence, preferences: preferences),
            importer: Importer(persistence: persistence),
            reseedJournal: reseedJournal
        )

        await #expect(throws: LillistError.self) {
            try await service.resetAndReseedFromThisDevice()
        }

        let entry = try reseedJournal.read()
        #expect(entry.phase == .failed)
        #expect(entry.localDataWiped == false)
        let stagedPath = try #require(entry.stagedBundlePath)
        // The staged bundle is the recovery anchor on failure — it must
        // NOT be cleaned up (only a full success removes it).
        #expect(FileManager.default.fileExists(atPath: stagedPath))
    }

    @Test("recoverInterruptedReseed: an idle journal is a no-op (S9b)")
    @MainActor
    func recoverInterruptedReseedNoOpWhenIdle() async throws {
        let host = FakePersistenceReconfigurer(initialMode: .localOnly)
        let reseedJournal = InMemoryReseedJournalStore()
        let service = DataStoreResetService(
            host: host,
            quarantine: QuarantineManager(rootDirectory: tempDir()),
            zoneEraser: FakeCloudKitZoneEraser(),
            quiesceMonitor: SyncQuiesceMonitor(bridge: CloudKitEventBridge()),
            notificationScheduler: nil,
            cloudKitContainerIdentifier: "iCloud.test",
            reseedJournal: reseedJournal
        )

        let outcome = try await service.recoverInterruptedReseed()

        #expect(outcome == .notInterrupted)
        #expect(await host.resetSteps == [])
    }

    @Test("recoverInterruptedReseed: discards safely when the wipe never reached the live store (S9b)")
    @MainActor
    func recoverInterruptedReseedDiscardsWhenNotWiped() async throws {
        let host = FakePersistenceReconfigurer(initialMode: .localOnly)
        let stageDir = tempDir()
        try FileManager.default.createDirectory(at: stageDir, withIntermediateDirectories: true)
        try Data("stale export".utf8).write(to: stageDir.appendingPathComponent("marker"))
        let reseedJournal = InMemoryReseedJournalStore(initial: ReseedJournal(
            phase: .exporting,
            startedAt: Date(),
            lastHeartbeatAt: Date(),
            stagedBundlePath: stageDir.path,
            localDataWiped: false
        ))
        let service = DataStoreResetService(
            host: host,
            quarantine: QuarantineManager(rootDirectory: tempDir()),
            zoneEraser: FakeCloudKitZoneEraser(),
            quiesceMonitor: SyncQuiesceMonitor(bridge: CloudKitEventBridge()),
            notificationScheduler: nil,
            cloudKitContainerIdentifier: "iCloud.test",
            reseedJournal: reseedJournal
        )

        let outcome = try await service.recoverInterruptedReseed()

        #expect(outcome == .discardedSafely)
        // The live store was never touched — no destructive step ran.
        #expect(await host.resetSteps == [])
        #expect(try reseedJournal.read() == .idle)
        #expect(FileManager.default.fileExists(atPath: stageDir.path) == false)
    }

    @Test("recoverInterruptedReseed: resumes the import when the wipe already ran, restoring real data (S9b class-kill)")
    @MainActor
    func recoverInterruptedReseedResumesImportAfterWipe() async throws {
        let persistence = try await TestStore.make()
        let preferences = PreferencesStore(persistence: persistence)
        _ = try await preferences.read()
        let tasks = TaskStore(persistence: persistence)
        let seededID = try await tasks.create(title: "Buy milk")

        // Export the pre-wipe data into a durable stage dir, exactly as
        // resetAndReseedFromThisDevice would have before a crash.
        let stageDir = tempDir()
        try FileManager.default.createDirectory(at: stageDir, withIntermediateDirectories: true)
        try await Exporter(persistence: persistence, preferences: preferences).export(to: stageDir)

        // Simulate "the wipe already happened": RealWipingResetHost's
        // tearDownStore genuinely deletes every row, matching the exact
        // state a real crash-after-wipe would leave.
        let host = RealWipingResetHost(persistence: persistence, initialMode: .iCloudSync)
        _ = try await host.tearDownStore(backupVia: nil)
        let survivorBeforeRecovery = try? await tasks.fetch(id: seededID)
        #expect(survivorBeforeRecovery == nil)  // genuinely wiped

        let reseedJournal = InMemoryReseedJournalStore(initial: ReseedJournal(
            phase: .importing,
            startedAt: Date(),
            lastHeartbeatAt: Date(),
            stagedBundlePath: stageDir.path,
            localDataWiped: true
        ))
        let service = DataStoreResetService(
            host: host,
            quarantine: QuarantineManager(rootDirectory: tempDir()),
            zoneEraser: FakeCloudKitZoneEraser(),
            quiesceMonitor: SyncQuiesceMonitor(bridge: CloudKitEventBridge()),
            notificationScheduler: nil,
            cloudKitContainerIdentifier: "iCloud.test",
            importer: Importer(persistence: persistence),
            reseedJournal: reseedJournal
        )

        let outcome = try await service.recoverInterruptedReseed()

        #expect(outcome == .resumed)
        #expect(try reseedJournal.read() == .idle)
        #expect(FileManager.default.fileExists(atPath: stageDir.path) == false)
        let recovered = try await tasks.fetch(id: seededID)
        #expect(recovered.title == "Buy milk")
    }

    @Test("recoverInterruptedReseed: a wiped journal with no staged path throws instead of silently losing data (S9b)")
    @MainActor
    func recoverInterruptedReseedThrowsWhenPathMissing() async throws {
        let host = FakePersistenceReconfigurer(initialMode: .localOnly)
        let reseedJournal = InMemoryReseedJournalStore(initial: ReseedJournal(
            phase: .failed,
            startedAt: Date(),
            lastHeartbeatAt: Date(),
            stagedBundlePath: nil,
            localDataWiped: true
        ))
        let service = DataStoreResetService(
            host: host,
            quarantine: QuarantineManager(rootDirectory: tempDir()),
            zoneEraser: FakeCloudKitZoneEraser(),
            quiesceMonitor: SyncQuiesceMonitor(bridge: CloudKitEventBridge()),
            notificationScheduler: nil,
            cloudKitContainerIdentifier: "iCloud.test",
            reseedJournal: reseedJournal
        )

        await #expect(throws: LillistError.self) {
            try await service.recoverInterruptedReseed()
        }
        // The (corrupt) journal is left as-is — never silently cleared.
        #expect(try reseedJournal.read().phase == .failed)
    }

    // MARK: - S23: post-reset backup-package reconcile

    @Test("resetAllData: a successful reset resyncs the backup package exactly once (S23)")
    @MainActor
    func resetAllDataResyncsBackupPackageOnSuccess() async throws {
        let host = FakePersistenceReconfigurer(initialMode: .localOnly)
        let eraser = FakeCloudKitZoneEraser()
        let reconciler = SpyBackupPackageReconciler()
        let service = makeService(startMode: .localOnly, host: host, eraser: eraser, backupReconciler: reconciler)

        try await service.resetAllData()

        #expect(await reconciler.callCount == 1)
    }

    @Test("resetAllData: a failed reset never resyncs the backup package (S23)")
    @MainActor
    func resetAllDataDoesNotResyncOnFailure() async throws {
        let host = FakePersistenceReconfigurer(initialMode: .localOnly)
        await host.failOnRebuild()
        let eraser = FakeCloudKitZoneEraser()
        let reconciler = SpyBackupPackageReconciler()
        let service = makeService(startMode: .localOnly, host: host, eraser: eraser, backupReconciler: reconciler)

        await #expect(throws: LillistError.self) {
            try await service.resetAllData()
        }

        #expect(await reconciler.callCount == 0)
    }

    @Test("resetAndReseedFromThisDevice: resyncs the backup package after both the wipe and the reimport (S23)")
    @MainActor
    func resetAndReseedResyncsBackupPackageTwice() async throws {
        let persistence = try await TestStore.make()
        let preferences = PreferencesStore(persistence: persistence)
        _ = try await preferences.read()
        let host = FakePersistenceReconfigurer(initialMode: .iCloudSync)
        let eraser = FakeCloudKitZoneEraser()
        let reconciler = SpyBackupPackageReconciler()
        let service = makeService(
            startMode: .iCloudSync, host: host, eraser: eraser,
            exporter: Exporter(persistence: persistence, preferences: preferences),
            importer: Importer(persistence: persistence),
            backupReconciler: reconciler,
            // S9c's post-reimport quiesce wait — fast windows, see the
            // identical rationale in resetAndReseedRoundTripsRealData.
            quiesceMinQuietWindow: 0.05, quiesceHardTimeout: 1
        )

        try await service.resetAndReseedFromThisDevice()

        // Once from performReset's own wipe-success chokepoint, once
        // more explicitly after the reimport — deliberate, not relying
        // on the local-save observer's incidental timing.
        #expect(await reconciler.callCount == 2)
    }

    // MARK: - X11: history-watermark + widget-cache clearing after a destructive reset

    @Test("X11: every reset flavor destroys/rebuilds the store, so every flavor clears history watermarks and the widget cache on success")
    @MainActor
    func everyResetFlavorClearsWatermarksAndWidgetCache() async throws {
        let host = FakePersistenceReconfigurer(initialMode: .localOnly)
        let eraser = FakeCloudKitZoneEraser()
        let watermarks = CallCounter()
        let widgets = CallCounter()
        let service = makeService(
            startMode: .localOnly, host: host, eraser: eraser,
            historyWatermarksReset: { await watermarks.bump() },
            widgetCacheReset: { await widgets.bump() }
        )

        try await service.resetAllData()

        #expect(await watermarks.count == 1)
        #expect(await widgets.count == 1)
    }

    @Test("X11: a failed reset never clears history watermarks or the widget cache — the store was never actually rebuilt")
    @MainActor
    func failedResetDoesNotClearWatermarks() async throws {
        let host = FakePersistenceReconfigurer(initialMode: .localOnly)
        await host.failOnRebuild()
        let eraser = FakeCloudKitZoneEraser()
        let watermarks = CallCounter()
        let widgets = CallCounter()
        let service = makeService(
            startMode: .localOnly, host: host, eraser: eraser,
            historyWatermarksReset: { await watermarks.bump() },
            widgetCacheReset: { await widgets.bump() }
        )

        await #expect(throws: LillistError.self) {
            try await service.resetAllData()
        }

        #expect(await watermarks.count == 0)
        #expect(await widgets.count == 0)
    }

    @Test("X11: resetAndReseedFromThisDevice clears the widget cache twice — once from the wipe, once more deterministically after the reimport (mirrors S23's backupReconciler double-call) — but the watermarks only once")
    @MainActor
    func resetAndReseedClearsWidgetCacheTwiceWatermarksOnce() async throws {
        let persistence = try await TestStore.make()
        let preferences = PreferencesStore(persistence: persistence)
        _ = try await preferences.read()
        let host = FakePersistenceReconfigurer(initialMode: .iCloudSync)
        let eraser = FakeCloudKitZoneEraser()
        let watermarks = CallCounter()
        let widgets = CallCounter()
        let service = makeService(
            startMode: .iCloudSync, host: host, eraser: eraser,
            exporter: Exporter(persistence: persistence, preferences: preferences),
            importer: Importer(persistence: persistence),
            historyWatermarksReset: { await watermarks.bump() },
            widgetCacheReset: { await widgets.bump() },
            quiesceMinQuietWindow: 0.05, quiesceHardTimeout: 1
        )

        try await service.resetAndReseedFromThisDevice()

        // historyWatermarksReset only fires from performReset's single
        // destroy/rebuild chokepoint — no second call after the reimport
        // (nothing about the reimport needs the watermarks cleared again).
        #expect(await watermarks.count == 1)
        // widgetCacheReset fires from performReset AND explicitly again
        // after the reimport, deterministically reflecting the reseeded
        // content rather than waiting on the local-save observer.
        #expect(await widgets.count == 2)
    }

    // MARK: - S3: account-mismatch resolution (narrow, re-validating entry point)

    /// Fast quiesce timing so the iCloudSync-only `.redownload` path
    /// doesn't wait the real 5s default — mirrors
    /// `postRebuildQuiesceTimeoutStillCompletes`'s pattern above.
    @MainActor
    private func makeFastService(
        host: FakePersistenceReconfigurer,
        eraser: any CloudKitZoneEraser,
        accountStateProvider: AccountStateProviding?
    ) -> DataStoreResetService {
        DataStoreResetService(
            host: host,
            quarantine: QuarantineManager(rootDirectory: tempDir()),
            zoneEraser: eraser,
            quiesceMonitor: SyncQuiesceMonitor(bridge: CloudKitEventBridge()),
            notificationScheduler: nil,
            cloudKitContainerIdentifier: "iCloud.test",
            accountStateProvider: accountStateProvider,
            quiesceMinQuietWindow: 0.05,
            quiesceHardTimeout: 0.1
        )
    }

    @Test("test_S3_resolveAccountMismatchByRedownloadingRequiresActiveMismatch")
    @MainActor
    func resolveAccountMismatchRequiresActiveMismatch() async throws {
        let host = FakePersistenceReconfigurer(initialMode: .iCloudSync)
        let eraser = FakeCloudKitZoneEraser()
        // No provider at all — the method has nothing to re-validate against.
        let service = makeFastService(host: host, eraser: eraser, accountStateProvider: nil)

        await #expect(throws: LillistError.self) {
            try await service.resolveAccountMismatchByRedownloading()
        }
        #expect(await host.resetSteps == [], "must not touch the store when there is nothing to resolve")

        // A provider that reports anything OTHER than .accountChanged must
        // also refuse — this is a re-validation, not a rubber stamp.
        let calmProvider: AccountStateProviding = { .available }
        let calmService = makeFastService(host: host, eraser: eraser, accountStateProvider: calmProvider)
        await #expect(throws: LillistError.self) {
            try await calmService.resolveAccountMismatchByRedownloading()
        }
    }

    @Test("test_S3_resolveAccountMismatchByRedownloadingBypassesPreflightOnce")
    @MainActor
    func resolveAccountMismatchBypassesPreflightOnce() async throws {
        let host = FakePersistenceReconfigurer(initialMode: .iCloudSync)
        let eraser = FakeCloudKitZoneEraser()
        let provider: AccountStateProviding = { .accountChanged }
        let service = makeFastService(host: host, eraser: eraser, accountStateProvider: provider)

        // Must NOT throw despite the provider reporting .accountChanged —
        // this one call is the confirmed resolution flow itself.
        try await service.resolveAccountMismatchByRedownloading()

        #expect(await host.resetSteps == ["tearDown", "rebuild"])
        // .redownload scope never erases the zone.
        #expect(await eraser.callCount == 0)
    }

    @Test("test_S3_resetAndRedownloadStillBlockedDuringActiveMismatch")
    @MainActor
    func resetAndRedownloadStillBlockedDuringActiveMismatch() async throws {
        // Proves resetAndRedownload() itself is completely unmodified —
        // ResetSignalMonitor's automatic peer-triggered path calls this
        // exact method and must stay blocked during a real mismatch.
        let host = FakePersistenceReconfigurer(initialMode: .iCloudSync)
        let eraser = FakeCloudKitZoneEraser()
        let provider: AccountStateProviding = { .accountChanged }
        let service = makeFastService(host: host, eraser: eraser, accountStateProvider: provider)

        await #expect(throws: LillistError.self) {
            try await service.resetAndRedownload()
        }
        #expect(await host.resetSteps == [])
    }

    // MARK: - S21: sync-status stall-state reset on successful reset

    private actor CallCounter {
        private(set) var count = 0
        func bump() { count += 1 }
    }

    @Test("test_S21_successfulResetResetsSyncStallState")
    @MainActor
    func successfulResetResetsSyncStallState() async throws {
        let host = FakePersistenceReconfigurer(initialMode: .localOnly)
        let eraser = FakeCloudKitZoneEraser()
        let counter = CallCounter()
        let service = makeService(
            startMode: .localOnly, host: host, eraser: eraser,
            syncStatusReset: { await counter.bump() }
        )

        try await service.resetAllData()

        #expect(await counter.count == 1)
    }

    @Test("test_S21_failedResetDoesNotResetSyncStallState")
    @MainActor
    func failedResetDoesNotResetSyncStallState() async throws {
        let host = FakePersistenceReconfigurer(initialMode: .localOnly)
        await host.failOnRebuild()
        let eraser = FakeCloudKitZoneEraser()
        let counter = CallCounter()
        let service = makeService(
            startMode: .localOnly, host: host, eraser: eraser,
            syncStatusReset: { await counter.bump() }
        )

        await #expect(throws: LillistError.self) {
            try await service.resetAllData()
        }

        #expect(await counter.count == 0)
    }

    @Test("test_S3_failedResolutionReattachDoesNotRearmMirroring")
    @MainActor
    func failedResolutionReattachDoesNotRearmMirroring() async throws {
        // Class-kill for the PersistenceHost fix (plan-3a §5): even though
        // this test drives the FAKE host (which doesn't itself carry
        // armsCloudKitMirroring — that property lives on the real
        // PersistenceHost, proven directly in PersistenceHostTests), the
        // ordering assertion here proves DataStoreResetService's own
        // contribution to the guarantee: a failed rebuild during a
        // confirmed mismatch resolution still reattaches (never leaves the
        // coordinator store-less) and still surfaces the failure — the
        // caller (the resolution UI) must not call adoptCurrentIdentity()
        // on this path, exactly per the council decision's binding
        // ordering.
        let host = FakePersistenceReconfigurer(initialMode: .iCloudSync)
        await host.failOnRebuild()
        let eraser = FakeCloudKitZoneEraser()
        let provider: AccountStateProviding = { .accountChanged }
        let service = makeFastService(host: host, eraser: eraser, accountStateProvider: provider)

        await #expect(throws: LillistError.self) {
            try await service.resolveAccountMismatchByRedownloading()
        }

        #expect(await host.resetSteps == ["tearDown", "rebuild", "reattach"])
    }
}

/// Zone eraser that records the call then throws, for the reset
/// rollback path. (The shared `FakeCloudKitZoneEraser` always succeeds.)
private actor ThrowingZoneEraser: CloudKitZoneEraser {
    private(set) var callCount = 0

    nonisolated func eraseManagedZones(
        in containerIdentifier: String,
        progress: @Sendable (Double) async -> Void
    ) async throws -> CloudKitEraseSummary {
        await bump()
        throw LillistError.storeUnavailable(reason: "fake erase failure")
    }

    private func bump() { callCount += 1 }
}

/// A `PersistenceResetting` conformer that genuinely deletes every row in
/// `persistence` on `tearDownStore`, instead of merely recording that the
/// step happened (`FakePersistenceReconfigurer`'s behavior, which every
/// other test in this suite relies on for pure ordering/branching
/// assertions). Used where a test must prove data did NOT survive a step it
/// doesn't otherwise control — e.g. S9a's attachment-restore regression,
/// where a never-actually-wiped store would satisfy a naive before/after
/// row check regardless of whether the bug is present.
private actor RealWipingResetHost: PersistenceResetting {
    private let persistence: PersistenceController
    private let mode: SyncMode

    init(persistence: PersistenceController, initialMode: SyncMode) {
        self.persistence = persistence
        self.mode = initialMode
    }

    var currentMode: SyncMode { mode }

    func tearDownStore(backupVia quarantine: QuarantineManager?) async throws -> QuarantineManager.QuarantinedBackup? {
        let ctx = persistence.container.viewContext
        try await ctx.perform {
            for entityName in ["Attachment", "JournalEntry", "NotificationSpec", "LillistTask", "Tag", "Series", "SmartFilter"] {
                let req = NSFetchRequest<NSManagedObject>(entityName: entityName)
                for row in try ctx.fetch(req) {
                    ctx.delete(row)
                }
            }
            if ctx.hasChanges { try ctx.save() }
        }
        return nil
    }

    func rebuildEmptyStore() async throws {}

    func reattachStore() async throws {}

    func attachStore(at newMode: SyncMode) async throws {}
}

/// Records `reconcileFull()` call count — proves `S23`'s post-reset
/// resync wiring without needing a real `LocalBackupCoordinator`/live
/// package.
private actor SpyBackupPackageReconciler: BackupPackageReconciling {
    private(set) var callCount = 0

    func reconcileFull() async {
        callCount += 1
    }
}
