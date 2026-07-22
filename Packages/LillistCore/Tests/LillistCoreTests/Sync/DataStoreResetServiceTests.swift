import Testing
import Foundation
import CloudKit
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
        importer: Importer? = nil
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
            importer: importer
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

        try await service.resetEverywhereToEmpty()

        // Exactly the same wipe steps resetAllData() runs.
        #expect(await host.resetSteps == ["tearDown", "rebuild"])
        #expect(await eraser.callCount == 1)
        // ...and the peer was signalled.
        let pending = inbox.pendingEvents(for: "device-B")
        #expect(pending.count == 1)
        #expect(pending.first?.kind == .resetToEmpty)
    }

    @Test("resetEverywhereToEmpty: with no propagator configured, still wipes correctly")
    @MainActor
    func resetEverywhereToEmptyWithoutPropagatorStillWipes() async throws {
        let host = FakePersistenceReconfigurer(initialMode: .iCloudSync)
        let eraser = FakeCloudKitZoneEraser()
        let service = makeService(startMode: .iCloudSync, host: host, eraser: eraser)

        try await service.resetEverywhereToEmpty()

        #expect(await host.resetSteps == ["tearDown", "rebuild"])
        #expect(await eraser.callCount == 1)
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
            importer: Importer(persistence: persistence)
        )

        try await service.resetAndReseedFromThisDevice()

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
    }

    @Test("resetAndReseedFromThisDevice: cleans up its temp export directory")
    @MainActor
    func resetAndReseedCleansUpTempDirectory() async throws {
        let persistence = try await TestStore.make()
        let preferences = PreferencesStore(persistence: persistence)
        _ = try await preferences.read()
        let host = FakePersistenceReconfigurer(initialMode: .iCloudSync)
        let eraser = FakeCloudKitZoneEraser()
        let tempRoot = FileManager.default.temporaryDirectory
        let before = (try? FileManager.default.contentsOfDirectory(atPath: tempRoot.path).filter {
            $0.hasPrefix("lillist-reseed-")
        }) ?? []

        let service = makeService(
            startMode: .iCloudSync, host: host, eraser: eraser,
            exporter: Exporter(persistence: persistence, preferences: preferences),
            importer: Importer(persistence: persistence)
        )
        try await service.resetAndReseedFromThisDevice()

        let after = (try? FileManager.default.contentsOfDirectory(atPath: tempRoot.path).filter {
            $0.hasPrefix("lillist-reseed-")
        }) ?? []
        #expect(after.count == before.count)
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
