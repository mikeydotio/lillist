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
        accountStateProvider: AccountStateProviding? = nil
    ) -> DataStoreResetService {
        DataStoreResetService(
            host: host,
            quarantine: QuarantineManager(rootDirectory: tempDir()),
            zoneEraser: eraser,
            quiesceMonitor: SyncQuiesceMonitor(bridge: CloudKitEventBridge()),
            notificationScheduler: nil,
            cloudKitContainerIdentifier: "iCloud.test",
            accountStateProvider: accountStateProvider
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
