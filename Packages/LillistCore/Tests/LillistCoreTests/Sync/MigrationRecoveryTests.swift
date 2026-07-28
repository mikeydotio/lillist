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

    @Test("restoreFromBackup at the SAME mode still reopens a fresh connection (S2)")
    @MainActor
    func restoreSameModeStillReattaches() async throws {
        // The exact crash scenario S2 reports: previousMode == the mode
        // the coordinator is already reading. Before the fix,
        // `host.reconfigure(to: prev)` would have been a silent no-op
        // here — nothing would ever have called tearDownStore or
        // attachStore, and the coordinator would have kept its stale
        // pre-restore connection.
        let dir = tempDir()
        let liveURL = dir.appendingPathComponent("Lillist.sqlite")
        try Data("backup-content".utf8).write(to: liveURL)
        let quarantine = QuarantineManager(rootDirectory: dir)
        _ = try quarantine.copyStore(at: liveURL)
        try FileManager.default.removeItem(at: liveURL)

        let journal = InMemoryMigrationJournalStore(initial: MigrationJournal(
            state: .reconfiguringStore,
            operation: .syncFirstThenDisable,
            previousMode: .localOnly
        ))
        // startMode == previousMode: both .localOnly.
        let (coordinator, recon, _) = makeCoordinator(startMode: .localOnly, journal: journal, quarantineRoot: dir)

        try await coordinator.restoreFromBackup(filename: "Lillist.sqlite", targetURL: liveURL)

        #expect(try String(contentsOf: liveURL, encoding: .utf8) == "backup-content")
        #expect(await recon.mode == .localOnly)
        // The new mechanism ran even though the mode never changed —
        // this is the observable proof the same-mode no-op is gone.
        #expect(await recon.resetSteps == ["tearDown"])
        #expect(await recon.attachCalls == [.localOnly])
        // The OLD mechanism (reconfigure) must never fire for this path.
        #expect(await recon.reconfigureCalls == [])
        #expect(try journal.read() == .idle)
    }

    @Test("restoreFromBackup: a failed attachStore best-effort reattaches and leaves the journal untouched (S2)")
    @MainActor
    func restoreAttachFailureReattachesWithoutClobberingJournal() async throws {
        let dir = tempDir()
        let liveURL = dir.appendingPathComponent("Lillist.sqlite")
        try Data("backup-content".utf8).write(to: liveURL)
        let quarantine = QuarantineManager(rootDirectory: dir)
        _ = try quarantine.copyStore(at: liveURL)
        try FileManager.default.removeItem(at: liveURL)

        let preexisting = MigrationJournal(
            state: .failed,
            operation: .replaceICloudWithLocal,
            previousMode: .iCloudSync,
            failureReason: "original migration crash"
        )
        let journal = InMemoryMigrationJournalStore(initial: preexisting)
        let (coordinator, recon, _) = makeCoordinator(startMode: .localOnly, journal: journal, quarantineRoot: dir)
        await recon.failOnAttachStore(call: 1)

        await #expect(throws: LillistError.self) {
            try await coordinator.restoreFromBackup(filename: "Lillist.sqlite", targetURL: liveURL)
        }

        // tearDown ran, attachStore failed, and the catch's best-effort
        // reattach ran too — the coordinator must never be left
        // store-less on this failure path (mirrors S12's pattern).
        #expect(await recon.resetSteps == ["tearDown", "reattach"])
        // The journal is left EXACTLY as it was — restoreFromBackup never
        // writes to it on failure, so the recovery sheet's existing
        // .failed entry (and its original failureReason) survives for
        // another attempt, rather than being silently cleared or
        // overwritten with a new, less-informative failure.
        #expect(try journal.read() == preexisting)
    }

    @Test("A secondary journal-write failure in the catch does not mask the original error")
    @MainActor
    func secondaryWriteFailureDoesNotMask() async throws {
        let dir = tempDir()
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        try Data("x".utf8).write(to: storeURL)
        // The attachStore swap throws (call 1). The catch then attempts
        // to write the .failed journal — make that write throw too. The
        // ORIGINAL attachStore error must still propagate.
        let inner = InMemoryMigrationJournalStore()
        // write sequence under disableNow (post S1/S6/S7/S8 reorder):
        // 1=preparing, 2=quarantining, 3=quarantining+folderName (a real
        // file exists at storeURL, and the fake is pointed at it via
        // setStoreURL below, so tearDownStore's quarantine copy is real
        // and its write runs too), 4=reconfiguringStore, then
        // attachStore throws → catch write is the 5th write.
        let journal = ThrowingMigrationJournalStore(underlying: inner, throwOnWrite: 5)
        let (coordinator, recon, _) = makeCoordinator(startMode: .iCloudSync, journal: journal, quarantineRoot: dir)
        await recon.setStoreURL(storeURL)
        await recon.failOnAttachStore(call: 1)

        do {
            try await coordinator.beginDisable(strategy: .now, storeURL: storeURL)
            Issue.record("expected beginDisable to throw")
        } catch let error as LillistError {
            // The original attachStore failure, not the catch-write
            // failure, surfaces. Both are storeUnavailable here, so we
            // assert the reason carries the attachStore message.
            if case .storeUnavailable(let reason) = error {
                #expect(reason.contains("fake attachStore failure"))
            } else {
                Issue.record("unexpected error \(error)")
            }
        }
    }
}
