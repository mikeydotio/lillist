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
        try await prefs.update { $0.trashRetentionDays = 14 }

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

    private func count(_ entity: String, in p: PersistenceController) async -> Int {
        await p.container.viewContext.perform {
            let req = NSFetchRequest<NSFetchRequestResult>(entityName: entity)
            return (try? p.container.viewContext.count(for: req)) ?? -1
        }
    }

    private func makeService(
        into p: PersistenceController, packageDir: URL, reset: any BackupDataResetting,
        diagnosticLog: DiagnosticSink? = nil, process: DiagProcess = .app
    ) -> BackupRestoreService {
        BackupRestoreService(
            reset: reset,
            importer: Importer(persistence: p),
            preferences: PreferencesStore(persistence: p),
            packageDirectory: packageDir,
            diagnosticLog: diagnosticLog,
            process: process
        )
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
        let zip = try BackupSnapshotManager(packageDirectory: dir, snapshotsDirectory: snaps).createSnapshot()

        let target = try await TestStore.make()
        let service = makeService(into: target, packageDir: dir, reset: FakeResetter())
        let summary = try await service.restore(from: .snapshotZip(zip))
        #expect(summary.tasksInserted == 1)
        #expect(await count("LillistTask", in: target) == 1)
    }

    @Test("a schema-mismatched package is refused and never resets")
    func incompatibleRefused() async throws {
        let dir = tempDir("pkg")
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try await buildPopulatedPackage(into: dir)

        // Rewrite the manifest with a future schema version.
        let store = TaskBackupStore(packageDirectory: dir)
        try await store.writeManifest(.init(
            backupSchemaVersion: BackupPackageSchema.version,
            cloudKitSchemaVersion: CloudKitSchema.currentVersion + 1,
            updatedAt: Date(),
            taskCount: 1
        ))

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
}
