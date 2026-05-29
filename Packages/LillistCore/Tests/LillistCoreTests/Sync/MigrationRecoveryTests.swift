import Testing
import Foundation
import CloudKit
@testable import LillistCore

@Suite("MigrationCoordinator recovery + failure injection (executing)", .serialized)
struct MigrationRecoveryTests {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MigRecovery-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @MainActor
    private func makeCoordinator(
        startMode: SyncMode,
        journal: MigrationJournalStore,
        quarantineRoot: URL,
        quarantineClock: @escaping @Sendable () -> Date = Date.init
    ) -> (MigrationCoordinator, FakePersistenceReconfigurer, FakeCloudKitZoneEraser) {
        let recon = FakePersistenceReconfigurer(initialMode: startMode)
        let eraser = FakeCloudKitZoneEraser()
        let suite = "MigRecovery-\(UUID().uuidString)"
        let modeStore = SyncModeStore(suiteName: suite)
        let coordinator = MigrationCoordinator(
            host: recon,
            journal: journal,
            quarantine: QuarantineManager(rootDirectory: quarantineRoot, clock: quarantineClock),
            zoneEraser: eraser,
            quiesceMonitor: SyncQuiesceMonitor(bridge: CloudKitEventBridge()),
            notificationScheduler: nil,
            syncModeStore: modeStore,
            localStoreRowCount: { 1 }
        )
        return (coordinator, recon, eraser)
    }

    @Test("restoreFromBackup restores contents, reverts mode, clears journal")
    @MainActor
    func restoreHappyPath() async throws {
        let dir = tempDir()
        // Seed a quarantined backup via copyStore.
        let liveURL = dir.appendingPathComponent("Lillist.sqlite")
        try Data("backup-content".utf8).write(to: liveURL)
        let quarantine = QuarantineManager(rootDirectory: dir)
        _ = try quarantine.copyStore(at: liveURL)
        // Wipe the live store to simulate a crashed, half-swapped state.
        try FileManager.default.removeItem(at: liveURL)

        let journal = InMemoryMigrationJournalStore(initial: MigrationJournal(
            state: .reconfiguringStore,
            operation: .replaceICloudWithLocal,
            previousMode: .iCloudSync
        ))
        let (coordinator, recon, _) = makeCoordinator(startMode: .localOnly, journal: journal, quarantineRoot: dir)

        try await coordinator.restoreFromBackup(filename: "Lillist.sqlite", targetURL: liveURL)

        #expect(try String(contentsOf: liveURL, encoding: .utf8) == "backup-content")
        #expect(await recon.mode == .iCloudSync)   // reverted to previousMode
        #expect(try journal.read() == .idle)        // cleared
    }

    @Test("restoreFromBackup with no backup throws storeUnavailable")
    @MainActor
    func restoreNoBackupThrows() async throws {
        let dir = tempDir()
        let liveURL = dir.appendingPathComponent("Lillist.sqlite")
        let journal = InMemoryMigrationJournalStore(initial: MigrationJournal(state: .failed, previousMode: .iCloudSync))
        let (coordinator, _, _) = makeCoordinator(startMode: .localOnly, journal: journal, quarantineRoot: dir)

        await #expect(throws: LillistError.self) {
            try await coordinator.restoreFromBackup(filename: "Lillist.sqlite", targetURL: liveURL)
        }
    }

    @Test("restoreFromBackup honors the journal's recorded folder, NOT the latest backup")
    @MainActor
    func restoreHonorsRecordedFolder() async throws {
        let dir = tempDir()
        let liveURL = dir.appendingPathComponent("Lillist.sqlite")

        // Seed an OLDER backup (the one the journal will record), then a
        // NEWER backup (the "latest" a naive restore would pick). Drive
        // distinct folder names AND distinct mtimes via an injected clock
        // so latestQuarantinedStore can tell them apart.
        let olderTimestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let newerTimestamp = Date(timeIntervalSince1970: 1_700_000_100)

        // Older backup: distinctive content "older-recorded".
        try Data("older-recorded".utf8).write(to: liveURL)
        let olderQuarantine = QuarantineManager(rootDirectory: dir, clock: { olderTimestamp })
        let olderBackup = try olderQuarantine.copyStore(at: liveURL)

        // Newer backup: distinctive content "newer-latest".
        try Data("newer-latest".utf8).write(to: liveURL)
        let newerQuarantine = QuarantineManager(rootDirectory: dir, clock: { newerTimestamp })
        let newerBackup = try newerQuarantine.copyStore(at: liveURL)

        // Force the newer backup's folder to have a strictly later mtime
        // so latestQuarantinedStore would prefer it — proving the
        // recorded-folder restore is a deliberate choice, not an accident
        // of ordering.
        let newerDir = dir.appendingPathComponent("Quarantine/\(newerBackup.folderName)", isDirectory: true)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 2_000_000_000)],
            ofItemAtPath: newerDir.path
        )
        let olderDir = dir.appendingPathComponent("Quarantine/\(olderBackup.folderName)", isDirectory: true)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000_000_000)],
            ofItemAtPath: olderDir.path
        )
        #expect(olderBackup.folderName != newerBackup.folderName)

        // Sanity: latestQuarantinedStore points at the NEWER backup, so
        // an honest "use recorded folder" path must override it.
        let latest = try newerQuarantine.latestQuarantinedStore(filename: "Lillist.sqlite")
        #expect(try String(contentsOf: latest!, encoding: .utf8) == "newer-latest")

        // Wipe the live store, then record the OLDER folder in the
        // journal and restore.
        try FileManager.default.removeItem(at: liveURL)
        let journal = InMemoryMigrationJournalStore(initial: MigrationJournal(
            state: .reconfiguringStore,
            operation: .replaceICloudWithLocal,
            previousMode: .iCloudSync,
            quarantineFolderName: olderBackup.folderName
        ))
        let (coordinator, recon, _) = makeCoordinator(startMode: .localOnly, journal: journal, quarantineRoot: dir)

        try await coordinator.restoreFromBackup(filename: "Lillist.sqlite", targetURL: liveURL)

        // The OLDER recorded backup's contents must be restored, NOT the
        // newer "latest" one.
        #expect(try String(contentsOf: liveURL, encoding: .utf8) == "older-recorded")
        #expect(await recon.mode == .iCloudSync)
        #expect(try journal.read() == .idle)
    }

    @Test("restoreFromBackup falls back to latest when the journal has no folder name (legacy)")
    @MainActor
    func restoreFallsBackToLatestWhenNoFolderRecorded() async throws {
        let dir = tempDir()
        let liveURL = dir.appendingPathComponent("Lillist.sqlite")
        try Data("legacy-content".utf8).write(to: liveURL)
        let quarantine = QuarantineManager(rootDirectory: dir)
        _ = try quarantine.copyStore(at: liveURL)
        try FileManager.default.removeItem(at: liveURL)

        // Legacy-style journal: no quarantineFolderName recorded.
        let journal = InMemoryMigrationJournalStore(initial: MigrationJournal(
            state: .reconfiguringStore,
            operation: .replaceICloudWithLocal,
            previousMode: .iCloudSync,
            quarantineFolderName: nil
        ))
        let (coordinator, recon, _) = makeCoordinator(startMode: .localOnly, journal: journal, quarantineRoot: dir)

        try await coordinator.restoreFromBackup(filename: "Lillist.sqlite", targetURL: liveURL)

        // Falls back to the only (latest) backup.
        #expect(try String(contentsOf: liveURL, encoding: .utf8) == "legacy-content")
        #expect(await recon.mode == .iCloudSync)
        #expect(try journal.read() == .idle)
    }

    @Test("A secondary journal-write failure in the catch does not mask the original error")
    @MainActor
    func secondaryWriteFailureDoesNotMask() async throws {
        let dir = tempDir()
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        try Data("x".utf8).write(to: storeURL)
        // The reconfigure throws (call 1). The catch then attempts to
        // write the .failed journal — make that write throw too. The
        // ORIGINAL reconfigure error must still propagate.
        let inner = InMemoryMigrationJournalStore()
        // write sequence under disableNow: 1=preparing, 2=reconfiguring,
        // then reconfigure throws → catch write is the 3rd write.
        let journal = ThrowingMigrationJournalStore(underlying: inner, throwOnWrite: 3)
        let (coordinator, recon, _) = makeCoordinator(startMode: .iCloudSync, journal: journal, quarantineRoot: dir)
        await recon.failOnReconfigure(call: 1)

        do {
            try await coordinator.beginDisable(strategy: .now, storeURL: storeURL)
            Issue.record("expected beginDisable to throw")
        } catch let error as LillistError {
            // The original reconfigure failure, not the catch-write
            // failure, surfaces. Both are storeUnavailable here, so we
            // assert the reason carries the reconfigure message.
            if case .storeUnavailable(let reason) = error {
                #expect(reason.contains("fake reconfigure failure"))
            } else {
                Issue.record("unexpected error \(error)")
            }
        }
    }
}
