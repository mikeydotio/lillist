import Testing
import Foundation
import CoreData
@testable import LillistCore

/// Wave 4 — schema-gated destructive restore (issue #7). The real
/// `DataStoreResetService` wipes a live CloudKit zone, so these tests inject a
/// fake resetter and restore into a *fresh empty* store — exercising the
/// preflight gate + assembleDocument + atomic import + preferences, without
/// touching iCloud.
@MainActor
@Suite("BackupRestoreService")
struct BackupRestoreServiceTests {
    final class FakeResetter: BackupDataResetting {
        private(set) var resetCount = 0
        func resetAllData() async throws { resetCount += 1 }
    }

    private func tempDir(_ prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("lillist-\(prefix)-\(UUID().uuidString)", isDirectory: true)
    }

    /// Seed a store with one of each entity, then write a full package from it.
    private func buildPopulatedPackage(into packageDir: URL) async throws -> PersistenceController {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let tags = TagStore(persistence: p)
        let journals = JournalStore(persistence: p)
        let attach = AttachmentStore(persistence: p)
        let prefs = PreferencesStore(persistence: p)

        let tag = try await tags.create(name: "Work", tintColor: "#FF0000")
        let task = try await tasks.create(title: "Recover me")
        try await tasks.assignTag(taskID: task, tagID: tag)
        _ = try await journals.appendNote(taskID: task, body: "a note")
        _ = try await attach.addFile(taskID: task, filename: "blob.bin", uti: "public.data", data: Data([0xAB, 0xCD, 0xEF]))
        try await prefs.update {
            $0.trashRetentionDays = 14
            $0.defaultTagTintHex = "#123ABC"
        }

        let store = TaskBackupStore(packageDirectory: packageDir)
        let coord = LocalBackupCoordinator(
            persistence: p,
            preferences: prefs,
            store: store,
            tokenStore: PersistentHistoryTokenStore(suiteName: "rt-\(UUID().uuidString)", key: PersistentHistoryTokenStore.backupKey)
        )
        await coord.reconcileFull()
        return p
    }

    /// S23: `preflight` now derives compatibility from the MINIMUM
    /// `cloudKitSchemaVersion` across the package's actual task records,
    /// not the manifest (which always reflects the CURRENT build's
    /// constant — see `LocalBackupCoordinator.updateManifest()` — and so
    /// is no longer authoritative for "what does this package actually
    /// contain"). Simulating an incompatible package now requires
    /// bumping the real per-task record(s), not just the manifest.
    private func bumpTaskRecordSchemaVersions(in dir: URL, to version: Int) async throws {
        let reader = BackupPackageReader(packageDirectory: dir)
        let records = try reader.readTaskRecords()
        var bumped: [BackupPackageSchema.TaskBackupRecord] = []
        for record in records {
            var r = record
            r.cloudKitSchemaVersion = version
            bumped.append(r)
        }
        try await TaskBackupStore(packageDirectory: dir).upsert(bumped, assets: [])
    }

    private func count(_ entity: String, in p: PersistenceController) async -> Int {
        await p.container.viewContext.perform {
            let req = NSFetchRequest<NSFetchRequestResult>(entityName: entity)
            return (try? p.container.viewContext.count(for: req)) ?? -1
        }
    }

    private func makeService(
        into p: PersistenceController, packageDir: URL, reset: any BackupDataResetting,
        diagnosticLog: DiagnosticSink? = nil, process: DiagProcess = .app,
        propagator: ResetPropagator? = nil, backupReconciler: (any BackupPackageReconciling)? = nil
    ) -> BackupRestoreService {
        BackupRestoreService(
            reset: reset,
            importer: Importer(persistence: p),
            preferences: PreferencesStore(persistence: p),
            packageDirectory: packageDir,
            diagnosticLog: diagnosticLog,
            process: process,
            propagator: propagator,
            backupReconciler: backupReconciler
        )
    }

    @Test("S23: preflight trusts a stale per-record schema version even when the manifest lies (claims current)")
    func preflightDistrustsManifestOverStaleRecord() async throws {
        // The exact mechanism S23 describes: `updateManifest()` always
        // writes THIS BUILD's CloudKitSchema.currentVersion, regardless
        // of what any individual task record actually carries — so a
        // manifest claiming "current" is not proof every record is.
        // Here the manifest is left alone (still claims current) but the
        // one real task record is stale (an older build's version) —
        // preflight must catch this from the record, not the manifest.
        let dir = tempDir("pkg")
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try await buildPopulatedPackage(into: dir)
        try await bumpTaskRecordSchemaVersions(in: dir, to: CloudKitSchema.currentVersion - 1)
        // Deliberately do NOT touch the manifest — it still (correctly,
        // per production behavior) claims CloudKitSchema.currentVersion.

        let target = try await TestStore.make()
        let service = makeService(into: target, packageDir: dir, reset: FakeResetter())
        let pre = try await service.preflight(.livePackage)

        #expect(pre.fileCloudKitSchemaVersion == CloudKitSchema.currentVersion - 1)
        #expect(!pre.isCompatible)
    }

    @Test("preflight reports compatible for a current-schema package")
    func preflightCompatible() async throws {
        let dir = tempDir("pkg")
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try await buildPopulatedPackage(into: dir)

        let target = try await TestStore.make()
        let service = makeService(into: target, packageDir: dir, reset: FakeResetter())
        let pre = try await service.preflight(.livePackage)
        #expect(pre.isCompatible)
        #expect(pre.fileCloudKitSchemaVersion == CloudKitSchema.currentVersion)
        #expect(pre.taskCount == 1)
    }

    @Test("full restore reconstructs tasks, tags, journal, attachment bytes, prefs")
    func fullRestoreRoundTrip() async throws {
        let dir = tempDir("pkg")
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try await buildPopulatedPackage(into: dir)

        let target = try await TestStore.make()
        let reset = FakeResetter()
        let service = makeService(into: target, packageDir: dir, reset: reset)

        let summary = try await service.restore(from: .livePackage)
        #expect(reset.resetCount == 1)
        #expect(summary.tasksInserted == 1)

        #expect(await count("LillistTask", in: target) == 1)
        #expect(await count("Tag", in: target) == 1)
        // Two journal entries: the user note + the `.attachment` entry that
        // `addFile` creates to own the blob.
        #expect(await count("JournalEntry", in: target) == 2)
        #expect(await count("Attachment", in: target) == 1)

        let bytes = await target.container.viewContext.perform {
            let req = NSFetchRequest<LillistCore.Attachment>(entityName: "Attachment")
            return try? target.container.viewContext.fetch(req).first?.data
        }
        #expect(bytes == Data([0xAB, 0xCD, 0xEF]))

        let restoredPrefs = try await PreferencesStore(persistence: target).read()
        #expect(restoredPrefs.trashRetentionDays == 14)
        // X3 (discovered): applyPreferences never copied defaultTagTintHex,
        // so a restore silently reset it even though it round-tripped
        // correctly through export/import up to that point.
        #expect(restoredPrefs.defaultTagTintHex == "#123ABC")
    }

    @Test("issue #71: a successful restore broadcasts a resetAndReseed control event to known peers")
    func successfulRestoreBroadcastsToKnownPeers() async throws {
        let dir = tempDir("pkg")
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try await buildPopulatedPackage(into: dir)

        let target = try await TestStore.make()
        let kv = InMemoryKeyValueSyncStore()
        let roster = DeviceRoster(kv: kv)
        let inbox = ControlInbox(kv: kv)
        roster.register(id: "device-B", displayName: "Vertumnus")
        let propagator = ResetPropagator(
            roster: roster, inbox: inbox, deviceID: "device-A", deviceDisplayName: "Nephele"
        )
        let service = makeService(
            into: target, packageDir: dir, reset: FakeResetter(), propagator: propagator
        )

        _ = try await service.restore(from: .livePackage)

        let pending = inbox.pendingEvents(for: "device-B")
        #expect(pending.count == 1)
        #expect(pending.first?.kind == .resetAndReseed)
    }

    @Test("issue #71: a refused (schema-mismatched) restore never broadcasts")
    func refusedRestoreDoesNotBroadcast() async throws {
        let dir = tempDir("pkg")
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try await buildPopulatedPackage(into: dir)
        let store = TaskBackupStore(packageDirectory: dir)
        try await store.writeManifest(.init(
            backupSchemaVersion: BackupPackageSchema.version,
            cloudKitSchemaVersion: CloudKitSchema.currentVersion + 1,
            updatedAt: Date(),
            taskCount: 1
        ))
        try await bumpTaskRecordSchemaVersions(in: dir, to: CloudKitSchema.currentVersion + 1)

        let target = try await TestStore.make()
        let kv = InMemoryKeyValueSyncStore()
        let roster = DeviceRoster(kv: kv)
        let inbox = ControlInbox(kv: kv)
        roster.register(id: "device-B", displayName: "Vertumnus")
        let propagator = ResetPropagator(
            roster: roster, inbox: inbox, deviceID: "device-A", deviceDisplayName: "Nephele"
        )
        let service = makeService(
            into: target, packageDir: dir, reset: FakeResetter(), propagator: propagator
        )

        await #expect(throws: LillistError.self) {
            try await service.restore(from: .livePackage)
        }

        #expect(inbox.pendingEvents(for: "device-B").isEmpty)
    }

    @Test("restore from a snapshot zip works end to end")
    func restoreFromSnapshotZip() async throws {
        let dir = tempDir("pkg")
        let snaps = tempDir("snaps")
        defer {
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.removeItem(at: snaps)
        }
        _ = try await buildPopulatedPackage(into: dir)
        let zip = try await BackupSnapshotManager(packageDirectory: dir, snapshotsDirectory: snaps)
            .createSnapshot(via: TaskBackupStore(packageDirectory: dir))

        let target = try await TestStore.make()
        let service = makeService(into: target, packageDir: dir, reset: FakeResetter())
        let summary = try await service.restore(from: .snapshotZip(zip))
        #expect(summary.tasksInserted == 1)
        #expect(await count("LillistTask", in: target) == 1)
    }

    // MARK: - S4: live-package restore must survive a mid-reset prune

    /// A `BackupDataResetting` that deletes the entire live package
    /// directory during `resetAllData()` — the worst-case, deterministic
    /// stand-in for S4's real trigger (a remote-change notification
    /// landing mid-reset drives `LocalBackupCoordinator.processRemoteChange`
    /// to prune every package file as "stale" against the now-empty live
    /// store).
    final class PackageWipingResetter: BackupDataResetting {
        let packageDirectory: URL
        init(packageDirectory: URL) { self.packageDirectory = packageDirectory }
        func resetAllData() async throws {
            try? FileManager.default.removeItem(at: packageDirectory)
        }
    }

    @Test("S4: restore(from: .livePackage) survives the live package being destroyed mid-reset")
    func liveRestoreSurvivesPackagePruneDuringReset() async throws {
        let dir = tempDir("pkg")
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try await buildPopulatedPackage(into: dir)

        let target = try await TestStore.make()
        let resetter = PackageWipingResetter(packageDirectory: dir)
        let service = makeService(into: target, packageDir: dir, reset: resetter)

        let summary = try await service.restore(from: .livePackage)

        // Even though resetAllData() (simulating S4's mid-reset prune)
        // deleted the ENTIRE live package directory, the restore still
        // recovers the pre-wipe data — proving it was staged BEFORE the
        // destructive step ran, not read from the live path afterward.
        #expect(summary.tasksInserted == 1)
        #expect(await count("LillistTask", in: target) == 1)
        #expect(await count("Tag", in: target) == 1)
    }

    @Test("a schema-mismatched package is refused and never resets")
    func incompatibleRefused() async throws {
        let dir = tempDir("pkg")
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try await buildPopulatedPackage(into: dir)

        // Rewrite the manifest AND the real task record with a future
        // schema version — S23: only the record is actually authoritative.
        let store = TaskBackupStore(packageDirectory: dir)
        try await store.writeManifest(.init(
            backupSchemaVersion: BackupPackageSchema.version,
            cloudKitSchemaVersion: CloudKitSchema.currentVersion + 1,
            updatedAt: Date(),
            taskCount: 1
        ))
        try await bumpTaskRecordSchemaVersions(in: dir, to: CloudKitSchema.currentVersion + 1)

        let target = try await TestStore.make()
        let reset = FakeResetter()
        let service = makeService(into: target, packageDir: dir, reset: reset)

        let pre = try await service.preflight(.livePackage)
        #expect(!pre.isCompatible)

        await #expect(throws: LillistError.self) {
            try await service.restore(from: .livePackage)
        }
        // The gate must fire BEFORE the destructive reset.
        #expect(reset.resetCount == 0)
        #expect(await count("LillistTask", in: target) == 0)
    }

    // MARK: - Issue #66: restore emits a diagnostic event

    /// A `BackupDataResetting` that always throws, so the failure path can be
    /// exercised without a schema mismatch.
    final class ThrowingResetter: BackupDataResetting {
        func resetAllData() async throws { throw LillistError.storeUnavailable(reason: "simulated") }
    }

    @Test("A successful restore emits one backup.restore event naming the source and outcome")
    func successfulRestoreEmitsEvent() async throws {
        let dir = tempDir("pkg")
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try await buildPopulatedPackage(into: dir)

        let target = try await TestStore.make()
        let spy = SpyDiagnosticSink()
        let service = makeService(into: target, packageDir: dir, reset: FakeResetter(), diagnosticLog: spy, process: .macApp)

        _ = try await service.restore(from: .livePackage)

        let events = await spy.events
        let event = try #require(events.last { $0.name == "backup.restore" })
        #expect(event.category == .data)
        #expect(event.process == .macApp)
        #expect(event.payload["source"] == .string("livePackage"))
        #expect(event.payload["outcome"] == .string("completed"))
        #expect(event.payload["tasksInserted"] == .int(1))
    }

    @Test("A schema-mismatch refusal emits backup.restore with outcome:incompatible")
    func incompatibleRestoreEmitsEvent() async throws {
        let dir = tempDir("pkg")
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try await buildPopulatedPackage(into: dir)
        let store = TaskBackupStore(packageDirectory: dir)
        try await store.writeManifest(.init(
            backupSchemaVersion: BackupPackageSchema.version,
            cloudKitSchemaVersion: CloudKitSchema.currentVersion + 1,
            updatedAt: Date(),
            taskCount: 1
        ))
        try await bumpTaskRecordSchemaVersions(in: dir, to: CloudKitSchema.currentVersion + 1)

        let target = try await TestStore.make()
        let spy = SpyDiagnosticSink()
        let service = makeService(into: target, packageDir: dir, reset: FakeResetter(), diagnosticLog: spy)

        await #expect(throws: LillistError.self) {
            try await service.restore(from: .livePackage)
        }

        let events = await spy.events
        let event = try #require(events.last { $0.name == "backup.restore" })
        #expect(event.payload["outcome"] == .string("incompatible"))
    }

    @Test("A reset failure emits backup.restore with outcome:failed")
    func resetFailureEmitsEvent() async throws {
        let dir = tempDir("pkg")
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try await buildPopulatedPackage(into: dir)

        let target = try await TestStore.make()
        let spy = SpyDiagnosticSink()
        let service = makeService(into: target, packageDir: dir, reset: ThrowingResetter(), diagnosticLog: spy)

        await #expect(throws: LillistError.self) {
            try await service.restore(from: .livePackage)
        }

        let events = await spy.events
        let event = try #require(events.last { $0.name == "backup.restore" })
        #expect(event.payload["outcome"] == .string("failed"))
    }

    @Test("No diagnostic sink means no emission, and restore still works")
    func nilSinkEmitsNothing() async throws {
        let dir = tempDir("pkg")
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try await buildPopulatedPackage(into: dir)

        let target = try await TestStore.make()
        // No diagnosticLog: — the default-nil param must not be required at
        // the existing call sites above.
        let service = makeService(into: target, packageDir: dir, reset: FakeResetter())
        let summary = try await service.restore(from: .livePackage)
        #expect(summary.tasksInserted == 1)
    }

    // MARK: - S23: post-restore backup-package reconcile

    /// Records `reconcileFull()` call count.
    private actor SpyBackupPackageReconciler: BackupPackageReconciling {
        private(set) var callCount = 0
        func reconcileFull() async { callCount += 1 }
    }

    @Test("restore: a successful restore resyncs the backup package exactly once (S23)")
    func restoreResyncsBackupPackageOnSuccess() async throws {
        let dir = tempDir("pkg")
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try await buildPopulatedPackage(into: dir)

        let target = try await TestStore.make()
        let reconciler = SpyBackupPackageReconciler()
        let service = makeService(into: target, packageDir: dir, reset: FakeResetter(), backupReconciler: reconciler)

        _ = try await service.restore(from: .livePackage)

        #expect(await reconciler.callCount == 1)
    }

    @Test("restore: a schema-mismatch refusal never resyncs the backup package (S23)")
    func refusedRestoreDoesNotResyncBackupPackage() async throws {
        let dir = tempDir("pkg")
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try await buildPopulatedPackage(into: dir)
        try await bumpTaskRecordSchemaVersions(in: dir, to: CloudKitSchema.currentVersion + 1)

        let target = try await TestStore.make()
        let reconciler = SpyBackupPackageReconciler()
        let service = makeService(into: target, packageDir: dir, reset: FakeResetter(), backupReconciler: reconciler)

        await #expect(throws: LillistError.self) {
            try await service.restore(from: .livePackage)
        }

        #expect(await reconciler.callCount == 0)
    }
}
