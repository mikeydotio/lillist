import Testing
import Foundation
import CloudKit
@testable import LillistCore

@Suite("MigrationCoordinator runner (executing, no live store)", .serialized)
struct MigrationRunnerExecutingTests {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MigRunner-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @MainActor
    private func makeCoordinator(
        startMode: SyncMode,
        rowCount: @escaping @Sendable () async -> Int = { 1 },
        journal: InMemoryMigrationJournalStore = InMemoryMigrationJournalStore(),
        eraser: FakeCloudKitZoneEraser = FakeCloudKitZoneEraser()
    ) -> (MigrationCoordinator, FakePersistenceReconfigurer, InMemoryMigrationJournalStore, FakeCloudKitZoneEraser, URL) {
        let dir = tempDir()
        let recon = FakePersistenceReconfigurer(initialMode: startMode)
        let suite = "MigRunner-\(UUID().uuidString)"
        let modeStore = SyncModeStore(suiteName: suite)
        let coordinator = MigrationCoordinator(
            host: recon,
            journal: journal,
            quarantine: QuarantineManager(rootDirectory: dir),
            zoneEraser: eraser,
            quiesceMonitor: SyncQuiesceMonitor(bridge: CloudKitEventBridge()),
            notificationScheduler: nil,
            syncModeStore: modeStore,
            localStoreRowCount: rowCount
        )
        return (coordinator, recon, journal, eraser, dir)
    }

    @Test("replaceICloudWithLocal on an empty local store throws before erasing")
    @MainActor
    func emptyStorePreconditionBlocksErase() async throws {
        let (coordinator, _, journal, eraser, dir) = makeCoordinator(startMode: .localOnly, rowCount: { 0 })
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        try Data("x".utf8).write(to: storeURL)
        await #expect(throws: LillistError.self) {
            try await coordinator.beginEnable(direction: .replaceICloud, storeURL: storeURL)
        }
        // The eraser must NOT have been called — we bailed before the
        // irreversible step.
        #expect(await eraser.callCount == 0)
        // Journal is left .failed for the recovery sheet.
        #expect(try journal.read().state == .failed)
    }
}
