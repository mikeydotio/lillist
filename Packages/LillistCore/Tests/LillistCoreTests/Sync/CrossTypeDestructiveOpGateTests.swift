import Testing
import Foundation
import CloudKit
@testable import LillistCore

/// `S11`: a shared `DestructiveOpGate` must serialize `MigrationCoordinator`
/// and `DataStoreResetService` against EACH OTHER, not just against
/// themselves — neither type's own reentrancy guard did that before this
/// finding's fix. These tests build both types sharing ONE gate instance,
/// matching exactly how `AppEnvironment` wires them in production.
@Suite("DestructiveOpGate cross-type serialization (S11)", .serialized)
struct CrossTypeDestructiveOpGateTests {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CrossGate-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @MainActor
    private func makePair(dir: URL) -> (MigrationCoordinator, DataStoreResetService, DestructiveOpGate) {
        let gate = DestructiveOpGate()
        let host = FakePersistenceReconfigurer(initialMode: .iCloudSync)
        let suite = "CrossGate-\(UUID().uuidString)"
        let modeStore = SyncModeStore(suiteName: suite)
        let coordinator = MigrationCoordinator(
            host: host,
            journal: InMemoryMigrationJournalStore(),
            quarantine: QuarantineManager(rootDirectory: dir),
            zoneEraser: FakeCloudKitZoneEraser(),
            quiesceMonitor: SyncQuiesceMonitor(bridge: CloudKitEventBridge()),
            notificationScheduler: nil,
            syncModeStore: modeStore,
            destructiveOpGate: gate,
            // Never used by disableNow (no quiesce wait), but keep it
            // fast in case a future edit adds one.
            quiesceMinQuietWindow: 0.05,
            quiesceHardTimeout: 1
        )
        let reset = DataStoreResetService(
            host: host,
            quarantine: QuarantineManager(rootDirectory: dir),
            zoneEraser: FakeCloudKitZoneEraser(),
            quiesceMonitor: SyncQuiesceMonitor(bridge: CloudKitEventBridge()),
            notificationScheduler: nil,
            destructiveOpGate: gate,
            quiesceMinQuietWindow: 0.05,
            quiesceHardTimeout: 1
        )
        return (coordinator, reset, gate)
    }

    @Test("A migration holding the gate blocks a concurrent reset")
    @MainActor
    func migrationBlocksReset() async throws {
        let dir = tempDir()
        let (_, reset, gate) = makePair(dir: dir)

        // Manually hold the gate the way runMigration would, without
        // actually running a full migration, so we can assert the
        // reset's rejection deterministically rather than racing two
        // real async operations against each other.
        try gate.acquire(for: .migration(.disableNow))

        await #expect(throws: LillistError.self) {
            try await reset.resetAllData()
        }

        gate.release()
    }

    @Test("A reset holding the gate blocks a concurrent migration")
    @MainActor
    func resetBlocksMigration() async throws {
        let dir = tempDir()
        let (coordinator, _, gate) = makePair(dir: dir)
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        try Data("x".utf8).write(to: storeURL)

        try gate.acquire(for: .reset("resetAndRedownload"))

        await #expect(throws: LillistError.self) {
            try await coordinator.beginDisable(strategy: .now, storeURL: storeURL)
        }

        gate.release()
    }

    @Test("Once released, the gate admits the next operation from either type")
    @MainActor
    func releaseAdmitsNextOperationFromEitherType() async throws {
        let dir = tempDir()
        let (coordinator, reset, gate) = makePair(dir: dir)
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        try Data("x".utf8).write(to: storeURL)

        try gate.acquire(for: .migration(.disableNow))
        gate.release()

        // A real reset now runs to completion — the gate was genuinely
        // freed, not just checked.
        try await reset.resetAllData()
        #expect(gate.currentOwner == nil)

        // And a real migration runs to completion right after.
        try await coordinator.beginDisable(strategy: .now, storeURL: storeURL)
        #expect(gate.currentOwner == nil)
    }
}
