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
}
