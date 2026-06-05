import Testing
import Foundation
import CloudKit
@testable import LillistCore

@Suite("MigrationCoordinator", .serialized)
struct MigrationCoordinatorTests {
    private static var liveSwapAllowed: Bool {
        Bundle.main.bundleIdentifier?.isEmpty == false
    }

    private static func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MigrationCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Quick-build helper.
    @MainActor
    private static func makeCoordinator() async throws -> (MigrationCoordinator, URL, PersistenceHost, InMemoryMigrationJournalStore, FakeCloudKitZoneEraser, SyncModeStore, URL) {
        let dir = tempDir()
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        let host = try await PersistenceHost.make(initialMode: .iCloudSync, storeURL: storeURL)
        let journal = InMemoryMigrationJournalStore()
        let quarantine = QuarantineManager(rootDirectory: dir)
        let fakeEraser = FakeCloudKitZoneEraser()
        let bridge = CloudKitEventBridge()
        let quiesce = SyncQuiesceMonitor(bridge: bridge)
        let suite = "MigrationCoordinatorTests-\(UUID().uuidString)"
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
        return (coordinator, storeURL, host, journal, fakeEraser, modeStore, dir)
    }

    @Test("Disable Now: iCloud → Local clears journal and flips mode", .enabled(if: liveSwapAllowed))
    func disableNow() async throws {
        let (coordinator, storeURL, host, journal, fakeEraser, modeStore, _) = try await Self.makeCoordinator()
        // Seed a store file so the reordered copy step in runMigration has a file to copy.
        try Data("seed".utf8).write(to: storeURL)
        try await coordinator.beginDisable(strategy: .now, storeURL: storeURL)
        #expect(await host.currentMode == .localOnly)
        #expect(await modeStore.currentMode() == .localOnly)
        #expect(try journal.read() == .idle)
        // Disable should NOT call the zone eraser.
        #expect(await fakeEraser.callCount == 0)
    }

    @Test("Replace iCloud with Local calls the zone eraser once after reconfiguring", .enabled(if: liveSwapAllowed))
    func replaceICloudWithLocal() async throws {
        // Build coordinator starting from LocalOnly so the enable flow runs.
        let dir = Self.tempDir()
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        let host = try await PersistenceHost.make(initialMode: .localOnly, storeURL: storeURL)
        let journal = InMemoryMigrationJournalStore()
        let quarantine = QuarantineManager(rootDirectory: dir)
        let fakeEraser = FakeCloudKitZoneEraser()
        let bridge = CloudKitEventBridge()
        let quiesce = SyncQuiesceMonitor(bridge: bridge)
        let suite = "MigrationCoordinatorTests-\(UUID().uuidString)"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        let modeStore = SyncModeStore(suiteName: suite)
        await modeStore.setMode(.localOnly)
        let coordinator = await MigrationCoordinator(
            host: host,
            journal: journal,
            quarantine: quarantine,
            zoneEraser: fakeEraser,
            quiesceMonitor: quiesce,
            notificationScheduler: nil,
            syncModeStore: modeStore
        )
        // Seed a store file so the reordered copy step in runMigration has a file to copy.
        // (reconfigure runs first, removing the store; then the backup copy; then the CloudKit erase)
        try Data("seed".utf8).write(to: storeURL)
        try await coordinator.beginEnable(direction: .replaceICloud, storeURL: storeURL)
        #expect(await fakeEraser.callCount == 1)
        #expect(await host.currentMode == .iCloudSync)
        #expect(try journal.read() == .idle)
    }

    @Test("resumeOrRecover returns the on-disk journal verbatim")
    @MainActor
    func resumeReadsJournal() async throws {
        let dir = Self.tempDir()
        let suite = "MigrationCoordinatorTests-\(UUID().uuidString)"
        let modeStore = SyncModeStore(suiteName: suite)
        let host = PersistenceHost(
            controller: try await PersistenceController(configuration: .inMemory),
            initialMode: .iCloudSync
        )
        let journal = InMemoryMigrationJournalStore(initial: MigrationJournal(state: .preparing, operation: .replaceLocalWithICloud, previousMode: .localOnly))
        let coordinator = MigrationCoordinator(
            host: host,
            journal: journal,
            quarantine: QuarantineManager(rootDirectory: dir),
            zoneEraser: FakeCloudKitZoneEraser(),
            quiesceMonitor: SyncQuiesceMonitor(bridge: CloudKitEventBridge()),
            notificationScheduler: nil,
            syncModeStore: modeStore
        )
        let observed = try await coordinator.resumeOrRecover()
        #expect(observed.state == .preparing)
        #expect(observed.operation == .replaceLocalWithICloud)
    }

    @Test("runMigration aborts on insufficient disk space before erasing iCloud")
    @MainActor
    func runMigrationRejectsLowDiskSpace() async throws {
        let dir = Self.tempDir()
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        // A non-empty live store so the copy-store block runs its
        // pre-flight (it skips entirely when the file is absent).
        try Data(repeating: 0x01, count: 4096).write(to: storeURL)

        // FakePersistenceReconfigurer keeps the test ungated: it flips
        // its currentMode without a live container, so no liveSwapAllowed.
        let host = FakePersistenceReconfigurer(initialMode: .localOnly)
        let journal = InMemoryMigrationJournalStore()
        // Zero free space, non-zero footprint -> pre-flight must throw.
        let probe = FakeDiskSpaceProbe(availableBytes: 0, footprintBytes: 4096)
        let quarantine = QuarantineManager(rootDirectory: dir, diskSpaceProbe: probe)
        let fakeEraser = FakeCloudKitZoneEraser()
        let quiesce = SyncQuiesceMonitor(bridge: CloudKitEventBridge())
        let suite = "MigrationCoordinatorTests-\(UUID().uuidString)"
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
            // A non-empty local store so the replaceICloudWithLocal
            // precondition passes and we reach reconfigure + copyStore.
            localStoreRowCount: { 1 }
        )

        await #expect(throws: LillistError.self) {
            try await coordinator.beginEnable(direction: .replaceICloud, storeURL: storeURL)
        }
        // Erase must NOT have run — copyStore threw first (step 5 < step 6).
        #expect(await fakeEraser.callCount == 0)
        // Journal left .failed so the recovery sheet can surface it.
        let finalJournal = try journal.read()
        #expect(finalJournal.state == .failed)
        #expect(finalJournal.failureReason?.contains("insufficientDiskSpace") == true)
        // POST-RECONFIGURE state: reconfigure (step 4) ran before
        // copyStore (step 5) threw, so the mode is ALREADY flipped to
        // the target on both the host and the mode store.
        #expect(await host.currentMode == .iCloudSync)
        #expect(await modeStore.currentMode() == .iCloudSync)
        // The live store was never copied out — copyStore threw before
        // touching disk, leaving the original in place.
        #expect(FileManager.default.fileExists(atPath: storeURL.path) == true)
    }
}
