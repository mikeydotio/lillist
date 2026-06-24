import Testing
import Foundation
import CoreData
@testable import LillistCore

/// Wave 2 — the live change hook. Drives real `TaskStore` mutations and asserts
/// the per-task files appear / update / disappear. The backup write is a
/// detached `Task` fired off the save notification, so assertions poll with a
/// bounded timeout rather than assuming synchronous completion.
@Suite("LocalBackupCoordinator")
struct LocalBackupCoordinatorTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("lillist-coord-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeCoordinator(
        _ p: PersistenceController,
        dir: URL
    ) -> (LocalBackupCoordinator, TaskBackupStore) {
        let store = TaskBackupStore(packageDirectory: dir)
        let tokens = PersistentHistoryTokenStore(
            suiteName: "backup-test-\(UUID().uuidString)",
            key: PersistentHistoryTokenStore.backupKey
        )
        let coord = LocalBackupCoordinator(
            persistence: p,
            preferences: PreferencesStore(persistence: p),
            store: store,
            tokenStore: tokens
        )
        return (coord, store)
    }

    /// Poll `condition` up to `timeout`, yielding between checks so the
    /// coordinator's detached backup task can run.
    private func waitUntil(timeout: TimeInterval = 5.0, _ condition: @Sendable () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 15_000_000)
        }
        return await condition()
    }

    private func taskFileExists(_ dir: URL, _ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent("tasks/\(id.uuidString).json").path)
    }

    private func readRecord(_ dir: URL, _ id: UUID) -> BackupPackageSchema.TaskBackupRecord? {
        let url = dir.appendingPathComponent("tasks/\(id.uuidString).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(BackupPackageSchema.TaskBackupRecord.self, from: data)
    }

    @Test("create writes a per-task file")
    func createWritesFile() async throws {
        let p = try await TestStore.make()
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (coord, _) = makeCoordinator(p, dir: dir)
        coord.start()
        defer { coord.stop() }

        let tasks = TaskStore(persistence: p)
        let id = try await tasks.create(title: "Backed up")
        #expect(await waitUntil { taskFileExists(dir, id) })
        let record = readRecord(dir, id)
        #expect(record?.task.title == "Backed up")
        #expect(record?.cloudKitSchemaVersion == CloudKitSchema.currentVersion)
    }

    @Test("update rewrites the per-task file")
    func updateRewritesFile() async throws {
        let p = try await TestStore.make()
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (coord, _) = makeCoordinator(p, dir: dir)
        coord.start()
        defer { coord.stop() }

        let tasks = TaskStore(persistence: p)
        let id = try await tasks.create(title: "Before")
        #expect(await waitUntil { taskFileExists(dir, id) })
        try await tasks.update(id: id) { $0.title = "After" }
        #expect(await waitUntil { readRecord(dir, id)?.task.title == "After" })
    }

    @Test("hard delete removes the per-task file")
    func hardDeleteRemovesFile() async throws {
        let p = try await TestStore.make()
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (coord, _) = makeCoordinator(p, dir: dir)
        coord.start()
        defer { coord.stop() }

        let tasks = TaskStore(persistence: p)
        let id = try await tasks.create(title: "Doomed")
        #expect(await waitUntil { taskFileExists(dir, id) })
        try await tasks.hardDelete(id: id)
        #expect(await waitUntil { !taskFileExists(dir, id) })
    }

    @Test("soft delete keeps the file (the task still exists, trashed)")
    func softDeleteKeepsFile() async throws {
        let p = try await TestStore.make()
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (coord, _) = makeCoordinator(p, dir: dir)
        coord.start()
        defer { coord.stop() }

        let tasks = TaskStore(persistence: p)
        let id = try await tasks.create(title: "Trash me")
        #expect(await waitUntil { taskFileExists(dir, id) })
        try await tasks.softDelete(id: id)
        // The record should now carry a deletedAt; the file persists.
        #expect(await waitUntil { readRecord(dir, id)?.task.deletedAt != nil })
        #expect(taskFileExists(dir, id))
    }

    @Test("recurrence spawn writes BOTH the closed and spawned task files")
    func recurrenceSpawnWritesBothFiles() async throws {
        let p = try await TestStore.make()
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (coord, store) = makeCoordinator(p, dir: dir)
        coord.start()
        defer { coord.stop() }

        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let seedID = try await tasks.create(title: "Daily standup")
        try await tasks.update(id: seedID) { $0.start = Date(timeIntervalSince1970: 1_800_000_000) }
        _ = try await series.create(fromSeedTask: seedID, rule: .calendar(.init(freq: .daily, interval: 1)))
        #expect(await waitUntil { taskFileExists(dir, seedID) })

        // Closing the instance updates the seed AND inserts a spawn — both must
        // land in the package via the single did-save chokepoint.
        try await tasks.transition(id: seedID, to: .closed)
        #expect(await waitUntil { (try? await store.taskFileCount()) == 2 })
    }

    @Test("purgeAll removes files for every trashed task")
    func purgeAllRemovesFiles() async throws {
        let p = try await TestStore.make()
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (coord, store) = makeCoordinator(p, dir: dir)
        coord.start()
        defer { coord.stop() }

        let tasks = TaskStore(persistence: p)
        let a = try await tasks.create(title: "A")
        let b = try await tasks.create(title: "B")
        #expect(await waitUntil { (try? await store.taskFileCount()) == 2 })
        try await tasks.softDelete(id: a)
        try await tasks.softDelete(id: b)
        _ = try await tasks.purgeAll()
        #expect(await waitUntil { (try? await store.taskFileCount()) == 0 })
    }

    @Test("a tag change refreshes the tags sidecar")
    func tagChangeUpdatesSidecar() async throws {
        let p = try await TestStore.make()
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (coord, _) = makeCoordinator(p, dir: dir)
        coord.start()
        defer { coord.stop() }

        let tags = TagStore(persistence: p)
        _ = try await tags.create(name: "Work", tintColor: "#FF0000")

        let reader = BackupPackageReader(packageDirectory: dir)
        #expect(await waitUntil {
            ((try? reader.assembleDocument().tags) ?? []).contains { $0.name == "Work" }
        })
    }

    @Test("seedPackageIfEmpty backs up tasks that predate the coordinator")
    func seedBacksUpExisting() async throws {
        let p = try await TestStore.make()
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Create BEFORE the coordinator exists, so nothing is auto-backed-up.
        let tasks = TaskStore(persistence: p)
        let a = try await tasks.create(title: "Pre-existing A")
        let b = try await tasks.create(title: "Pre-existing B")

        let (coord, store) = makeCoordinator(p, dir: dir)
        await coord.seedPackageIfEmpty()
        #expect(try await store.taskFileCount() == 2)
        #expect(taskFileExists(dir, a))
        #expect(taskFileExists(dir, b))
    }

    @Test("seedPackageIfEmpty is a no-op once the package is populated")
    func seedNoOpWhenPopulated() async throws {
        let p = try await TestStore.make()
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tasks = TaskStore(persistence: p)
        _ = try await tasks.create(title: "Only one")

        let (coord, store) = makeCoordinator(p, dir: dir)
        await coord.seedPackageIfEmpty()
        #expect(try await store.taskFileCount() == 1)
        // A second seed must not duplicate or wipe.
        await coord.seedPackageIfEmpty()
        #expect(try await store.taskFileCount() == 1)
    }

    @Test("stress: rapid create/delete cycles converge to an empty package")
    func stressCreateDeleteCycles() async throws {
        let p = try await TestStore.make()
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (coord, store) = makeCoordinator(p, dir: dir)
        coord.start()
        defer { coord.stop() }

        let tasks = TaskStore(persistence: p)
        for i in 0..<25 {
            let id = try await tasks.create(title: "cycle-\(i)")
            try await tasks.hardDelete(id: id)
        }
        // Every created file must eventually be removed by its delete.
        #expect(await waitUntil(timeout: 10.0) { (try? await store.taskFileCount()) == 0 })
    }
}
