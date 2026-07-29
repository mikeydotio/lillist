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
        dir: URL,
        tokenSuiteName: String? = nil
    ) -> (LocalBackupCoordinator, TaskBackupStore) {
        let store = TaskBackupStore(packageDirectory: dir)
        let tokens = PersistentHistoryTokenStore(
            // A caller-supplied suite name simulates the SAME device's
            // watermark persisting across two coordinator instances
            // representing two app launches (LIL-87's own scenario) — in
            // production this is App-Group UserDefaults, which survives a
            // relaunch. The default (a fresh UUID per call) preserves every
            // existing test's isolated-watermark behavior.
            suiteName: tokenSuiteName ?? "backup-test-\(UUID().uuidString)",
            consumer: .backup
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

    @Test("X3: a smart filter change refreshes the smartFilters sidecar")
    func smartFilterChangeUpdatesSidecar() async throws {
        let p = try await TestStore.make()
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (coord, _) = makeCoordinator(p, dir: dir)
        coord.start()
        defer { coord.stop() }

        let filters = SmartFilterStore(persistence: p)
        _ = try await filters.create(name: "Overdue", group: .init(combinator: .all, predicates: []))

        let reader = BackupPackageReader(packageDirectory: dir)
        #expect(await waitUntil {
            ((try? reader.assembleDocument().smartFilters) ?? []).contains { $0.name == "Overdue" }
        })
    }

    @Test("X3: a series creation refreshes the series sidecar and its seed task's file carries seriesID")
    func seriesCreationUpdatesSidecarAndTaskFile() async throws {
        let p = try await TestStore.make()
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (coord, _) = makeCoordinator(p, dir: dir)
        coord.start()
        defer { coord.stop() }

        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let seedID = try await tasks.create(title: "Water plants")
        let seriesID = try await series.create(
            fromSeedTask: seedID,
            rule: .calendar(.init(freq: .daily, interval: 1))
        )

        let reader = BackupPackageReader(packageDirectory: dir)
        #expect(await waitUntil {
            ((try? reader.assembleDocument().series) ?? []).contains { $0.id == seriesID }
        })
        // Series creation also mutates the seed task's own `series`
        // relationship (LillistTask, not just Series) — the seed task's own
        // file, refreshed via the local-save path (not the sidecar path),
        // must carry the matching seriesID.
        #expect(await waitUntil { readRecord(dir, seedID)?.task.seriesID == seriesID })
    }

    @Test("X3: a notification spec add/remove appears in its owning task's own backup file")
    func notificationSpecChangeUpdatesTaskFile() async throws {
        let p = try await TestStore.make()
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (coord, _) = makeCoordinator(p, dir: dir)
        coord.start()
        defer { coord.stop() }

        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "Pay rent")
        let specID = try await specs.add(
            taskID: taskID, kind: .offsetDeadline, offsetMinutes: 60, fireDate: Date(timeIntervalSince1970: 2_000_000_000)
        )

        #expect(await waitUntil {
            readRecord(dir, taskID)?.notificationSpecs.contains { $0.id == specID } ?? false
        })

        try await specs.delete(id: specID)
        #expect(await waitUntil {
            (readRecord(dir, taskID)?.notificationSpecs.isEmpty) ?? false
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

    // MARK: - LIL-87: launch-time history catch-up

    @Test("bootstrapAtLaunch catches up on foreign history that arrived while no coordinator was observing")
    func bootstrapAtLaunchCatchesUpWithoutALiveNotification() async throws {
        let storeURL = tempDir().appendingPathComponent("Lillist.sqlite")
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let packageDir = tempDir()
        defer { try? FileManager.default.removeItem(at: packageDir) }
        // Shared across both "launches" below — the same device's
        // watermark persisting across relaunches (App-Group UserDefaults
        // in production), so the SECOND coordinator resumes from where the
        // FIRST left off rather than re-scanning from the beginning of
        // history (which would catch the foreign task by accident,
        // proving nothing about LIL-87's actual fix).
        let tokenSuite = "LocalBackupCoordinatorTests-LIL87-\(UUID().uuidString)"

        // First "launch": a local task exists, and bootstrapAtLaunch()
        // seeds the package via seedPackageIfEmpty()'s full reconcile —
        // this is the ONLY path that would otherwise mask LIL-87's fix
        // (a fresh, still-empty package gets fully rebuilt regardless of
        // any history catch-up). Deliberately populating the package
        // first, then tearing this coordinator down, forces the SECOND
        // bootstrap below to hit the genuinely-empty branch of
        // seedPackageIfEmpty() (already-populated → no-op), isolating the
        // explicit processRemoteChange() catch-up as the only remaining
        // mechanism that could pick up what comes next.
        let firstLaunchController = try await PersistenceController(
            configuration: .onDisk(url: storeURL, syncMode: .localOnly),
            transactionAuthor: PersistenceController.localTransactionAuthor
        )
        _ = try await TaskStore(persistence: firstLaunchController).create(title: "Existing at first launch")
        let (firstCoord, firstStore) = makeCoordinator(firstLaunchController, dir: packageDir, tokenSuiteName: tokenSuite)
        await firstCoord.bootstrapAtLaunch()
        #expect(try await firstStore.taskFileCount() == 1)
        firstCoord.stop()

        // "Another process" (mirrors MultiProcessStoreHarnessTests) writes
        // a SECOND task to the same on-disk store file while nothing is
        // observing — no coordinator instance exists at all right now, so
        // there is no live NSManagedObjectContextDidSave/
        // .NSPersistentStoreRemoteChange observer anywhere to catch it.
        let foreignController = try await PersistenceController(
            configuration: .onDisk(url: storeURL, syncMode: .localOnly),
            transactionAuthor: PersistenceController.cliTransactionAuthor
        )
        let foreignTaskID = try await TaskStore(persistence: foreignController).create(title: "Written by another process")

        // "Second launch": a fresh controller + a fresh coordinator
        // instance over the SAME already-populated package — the
        // realistic cold-relaunch shape. Only bootstrapAtLaunch() runs;
        // seedPackageIfEmpty() no-ops (the package already has one file),
        // so the foreign task can only appear via the explicit
        // processRemoteChange() catch-up LIL-87 adds.
        let secondLaunchController = try await PersistenceController(
            configuration: .onDisk(url: storeURL, syncMode: .localOnly),
            transactionAuthor: PersistenceController.localTransactionAuthor
        )
        await secondLaunchController.container.viewContext.perform {
            secondLaunchController.container.viewContext.refreshAllObjects()
        }
        let (secondCoord, secondStore) = makeCoordinator(secondLaunchController, dir: packageDir, tokenSuiteName: tokenSuite)

        await secondCoord.bootstrapAtLaunch()

        #expect(taskFileExists(packageDir, foreignTaskID))
        #expect(try await secondStore.taskFileCount() == 2, "the pre-existing file must survive alongside the newly-caught-up one")
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

    // MARK: - S4/S23: processRemoteChange never prunes mid-destructive-op

    @Test("processRemoteChange skips pruning while the destructive-op gate is held, and prunes once released (S4/S23)")
    @MainActor
    func processRemoteChangeSkipsPruneWhileGateHeld() async throws {
        // The live store is left completely empty (TestStore.make()) —
        // this test seeds the PACKAGE directly via store.upsert, never
        // going through the coordinator's own live-change observers, so
        // there is no risk of an observer-dispatched processRemoteChange
        // task racing the explicit, controlled calls below (a real risk:
        // NSPersistentStoreRemoteChange can fire from a plain local save
        // too, and coord.stop() only unregisters FUTURE notifications —
        // it can't cancel a Task already spawned from an earlier one).
        // An empty live store with one on-disk task file is exactly the
        // "stale file, no live counterpart" precondition the prune step
        // reacts to — however it came to exist in production.
        let p = try await TestStore.make()
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TaskBackupStore(packageDirectory: dir)
        let dto = ExportSchema.TaskDTO(
            id: UUID(), title: "Stale file with no live counterpart", notes: "", status: 0,
            start: nil, startHasTime: false, deadline: nil, deadlineHasTime: false,
            position: 1, isPinned: false, parentID: nil, tagIDs: [],
            createdAt: nil, modifiedAt: nil, closedAt: nil, deletedAt: nil,
            schemaVersion: CloudKitSchema.currentVersion
        )
        try await store.upsert([
            BackupPackageSchema.TaskBackupRecord(
                backupSchemaVersion: BackupPackageSchema.version,
                cloudKitSchemaVersion: dto.schemaVersion,
                task: dto, journalEntries: [], attachments: []
            )
        ], assets: [])
        #expect(try await store.taskFileCount() == 1)

        let tokens = PersistentHistoryTokenStore(
            suiteName: "backup-test-\(UUID().uuidString)",
            consumer: .backup
        )
        let gate = DestructiveOpGate()
        let coord = LocalBackupCoordinator(
            persistence: p,
            preferences: PreferencesStore(persistence: p),
            store: store,
            tokenStore: tokens,
            destructiveOpGate: gate
        )

        // Hold the gate (simulating an in-flight reset/restore) and call
        // processRemoteChange directly — the prune step must be skipped
        // even though the live store has zero matching rows.
        try gate.acquire(for: .restore)
        await coord.processRemoteChange()
        #expect(try await store.taskFileCount() == 1)

        // Release the gate and call again — now the same stale file must
        // be pruned, proving the guard is a genuine gate (not a permanent
        // disable) and the mechanism itself still works.
        gate.release()
        await coord.processRemoteChange()
        #expect(try await store.taskFileCount() == 0)
    }
}
