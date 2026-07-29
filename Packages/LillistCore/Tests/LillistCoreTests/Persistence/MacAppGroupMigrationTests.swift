import Testing
import Foundation
@testable import LillistCore

/// `MacAppGroupMigration` is X1's macOS data-safety half: a pure
/// file-system, pre-container migration from the legacy sandbox
/// Application Support store into the shared App Group location. Every
/// test here operates on temp directories only — no live Core Data
/// container is opened, matching the plan's "pure file-level" test
/// requirement (the migration itself never opens either candidate store).
@Suite("MacAppGroupMigration")
struct MacAppGroupMigrationTests {
    private func makeRoot() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacAppGroupMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeStore(at url: URL, mainContent: String, wal: String? = nil, shm: String? = nil) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(mainContent.utf8).write(to: url)
        if let wal { try Data(wal.utf8).write(to: url.appendingPathExtension("wal")) }
        if let shm { try Data(shm.utf8).write(to: url.appendingPathExtension("shm")) }
    }

    private func contents(of url: URL) -> String? {
        guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - notNeeded

    @Test("No legacy store: notNeeded, group store (if any) untouched")
    func notNeeded_noLegacyStore() throws {
        let root = try makeRoot()
        let legacyURL = root.appendingPathComponent("Legacy/Lillist.sqlite")
        let groupURL = root.appendingPathComponent("Group/Lillist.sqlite")
        try writeStore(at: groupURL, mainContent: "group-data")
        let quarantine = QuarantineManager(rootDirectory: root.appendingPathComponent("Group"))

        let outcome = try MacAppGroupMigration.migrateIfNeeded(
            legacyURL: legacyURL, groupURL: groupURL, syncMode: .iCloudSync, quarantine: quarantine
        )

        #expect(outcome == .notNeeded)
        #expect(contents(of: groupURL) == "group-data")
    }

    // MARK: - Simple migration (legacy present, group absent)

    @Test("Legacy present, group absent: migrates, quarantines legacy (never deletes), carries sidecars")
    func migrated_simpleCase() throws {
        let root = try makeRoot()
        let legacyURL = root.appendingPathComponent("Legacy/Lillist.sqlite")
        let groupURL = root.appendingPathComponent("Group/Lillist.sqlite")
        try writeStore(at: legacyURL, mainContent: "legacy-data", wal: "legacy-wal", shm: "legacy-shm")
        let quarantine = QuarantineManager(rootDirectory: root.appendingPathComponent("Group"))

        let outcome = try MacAppGroupMigration.migrateIfNeeded(
            legacyURL: legacyURL, groupURL: groupURL, syncMode: .iCloudSync, quarantine: quarantine
        )

        guard case .migrated(let quarantinedLegacyAt) = outcome else {
            Issue.record("expected .migrated, got \(outcome)")
            return
        }
        // The group location now holds the legacy content + sidecars.
        #expect(contents(of: groupURL) == "legacy-data")
        #expect(contents(of: groupURL.appendingPathExtension("wal")) == "legacy-wal")
        #expect(contents(of: groupURL.appendingPathExtension("shm")) == "legacy-shm")
        // The legacy original is GONE from its old location...
        #expect(FileManager.default.fileExists(atPath: legacyURL.path) == false)
        // ...but recoverable, never deleted, at the quarantine location.
        #expect(contents(of: quarantinedLegacyAt) == "legacy-data")
    }

    @Test("Legacy present, group absent, no sidecars: migrates cleanly")
    func migrated_simpleCase_noSidecars() throws {
        let root = try makeRoot()
        let legacyURL = root.appendingPathComponent("Legacy/Lillist.sqlite")
        let groupURL = root.appendingPathComponent("Group/Lillist.sqlite")
        try writeStore(at: legacyURL, mainContent: "legacy-only")
        let quarantine = QuarantineManager(rootDirectory: root.appendingPathComponent("Group"))

        let outcome = try MacAppGroupMigration.migrateIfNeeded(
            legacyURL: legacyURL, groupURL: groupURL, syncMode: .localOnly, quarantine: quarantine
        )

        guard case .migrated = outcome else {
            Issue.record("expected .migrated, got \(outcome)")
            return
        }
        #expect(contents(of: groupURL) == "legacy-only")
    }

    // MARK: - Both stores populated: iCloudSync branch (council decision)

    @Test("Both stores present, iCloudSync: quarantines the App-Group store, migrates legacy into its place")
    func migratedResolvingConflict_iCloudSync() throws {
        let root = try makeRoot()
        let legacyURL = root.appendingPathComponent("Legacy/Lillist.sqlite")
        let groupURL = root.appendingPathComponent("Group/Lillist.sqlite")
        try writeStore(at: legacyURL, mainContent: "legacy-data")
        try writeStore(at: groupURL, mainContent: "app-group-data")
        let quarantine = QuarantineManager(rootDirectory: root.appendingPathComponent("Group"))

        let outcome = try MacAppGroupMigration.migrateIfNeeded(
            legacyURL: legacyURL, groupURL: groupURL, syncMode: .iCloudSync, quarantine: quarantine
        )

        guard case .migratedResolvingConflict(let quarantinedAppGroupAt, let quarantinedLegacyAt, let legacy, let appGroup) = outcome else {
            Issue.record("expected .migratedResolvingConflict, got \(outcome)")
            return
        }
        // Group location now holds the LEGACY content — legacy wins per
        // the council decision in .iCloudSync mode.
        #expect(contents(of: groupURL) == "legacy-data")
        // Neither original was deleted: both recoverable from quarantine.
        #expect(contents(of: quarantinedAppGroupAt) == "app-group-data")
        #expect(contents(of: quarantinedLegacyAt) == "legacy-data")
        #expect(FileManager.default.fileExists(atPath: legacyURL.path) == false)
        // Forensic footprints describe the PRE-migration state of each store.
        #expect(legacy.sizeBytes == Int64("legacy-data".utf8.count))
        #expect(appGroup.sizeBytes == Int64("app-group-data".utf8.count))
    }

    // MARK: - Both stores populated: localOnly branch (council decision)

    @Test("Both stores present, localOnly: makes NO file mutation — no CloudKit safety net for the App-Group store")
    func conflictDetected_localOnly_noMutation() throws {
        let root = try makeRoot()
        let legacyURL = root.appendingPathComponent("Legacy/Lillist.sqlite")
        let groupURL = root.appendingPathComponent("Group/Lillist.sqlite")
        try writeStore(at: legacyURL, mainContent: "legacy-data")
        try writeStore(at: groupURL, mainContent: "app-group-data")
        let quarantine = QuarantineManager(rootDirectory: root.appendingPathComponent("Group"))

        let outcome = try MacAppGroupMigration.migrateIfNeeded(
            legacyURL: legacyURL, groupURL: groupURL, syncMode: .localOnly, quarantine: quarantine
        )

        guard case .conflictDetected(let legacy, let appGroup) = outcome else {
            Issue.record("expected .conflictDetected, got \(outcome)")
            return
        }
        // Absolutely nothing was touched — the App-Group store has no
        // CloudKit mirror in localOnly mode, so quarantining it would be
        // unconditional, permanent data loss.
        #expect(contents(of: legacyURL) == "legacy-data")
        #expect(contents(of: groupURL) == "app-group-data")
        #expect(legacy.sizeBytes == Int64("legacy-data".utf8.count))
        #expect(appGroup.sizeBytes == Int64("app-group-data".utf8.count))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Group/Quarantine").path) == false)
    }

    // MARK: - migrationFailed (disk space)

    @Test("Insufficient disk space: migrationFailed, both stores left completely untouched")
    func migrationFailed_insufficientDiskSpace_leavesStoresUntouched() throws {
        let root = try makeRoot()
        let legacyURL = root.appendingPathComponent("Legacy/Lillist.sqlite")
        let groupURL = root.appendingPathComponent("Group/Lillist.sqlite")
        try writeStore(at: legacyURL, mainContent: "legacy-data")
        let probe = FakeDiskSpaceProbe(availableBytes: 0, footprintBytes: 4096)
        let quarantine = QuarantineManager(rootDirectory: root.appendingPathComponent("Group"), diskSpaceProbe: probe)

        let outcome = try MacAppGroupMigration.migrateIfNeeded(
            legacyURL: legacyURL, groupURL: groupURL, syncMode: .iCloudSync, quarantine: quarantine
        )

        guard case .migrationFailed(let reason) = outcome else {
            Issue.record("expected .migrationFailed, got \(outcome)")
            return
        }
        #expect(reason.isEmpty == false)
        #expect(contents(of: legacyURL) == "legacy-data")
        #expect(FileManager.default.fileExists(atPath: groupURL.path) == false)
    }

    @Test("Insufficient disk space in the both-stores-populated iCloudSync case also leaves both stores untouched")
    func migrationFailed_conflictCase_leavesBothStoresUntouched() throws {
        let root = try makeRoot()
        let legacyURL = root.appendingPathComponent("Legacy/Lillist.sqlite")
        let groupURL = root.appendingPathComponent("Group/Lillist.sqlite")
        try writeStore(at: legacyURL, mainContent: "legacy-data")
        try writeStore(at: groupURL, mainContent: "app-group-data")
        let probe = FakeDiskSpaceProbe(availableBytes: 0, footprintBytes: 4096)
        let quarantine = QuarantineManager(rootDirectory: root.appendingPathComponent("Group"), diskSpaceProbe: probe)

        let outcome = try MacAppGroupMigration.migrateIfNeeded(
            legacyURL: legacyURL, groupURL: groupURL, syncMode: .iCloudSync, quarantine: quarantine
        )

        guard case .migrationFailed = outcome else {
            Issue.record("expected .migrationFailed, got \(outcome)")
            return
        }
        // Verified BEFORE either live store is touched — a failed stage
        // means neither original moved.
        #expect(contents(of: legacyURL) == "legacy-data")
        #expect(contents(of: groupURL) == "app-group-data")
    }

    // MARK: - verifyStagedCopy (internal seam)

    @Test("verifyStagedCopy throws on a size mismatch")
    func verifyStagedCopy_sizeMismatchThrows() throws {
        let root = try makeRoot()
        let source = root.appendingPathComponent("source.sqlite")
        let staged = root.appendingPathComponent("staged.sqlite")
        try Data("full-content".utf8).write(to: source)
        try Data("trunc".utf8).write(to: staged)
        #expect(throws: (any Error).self) {
            try MacAppGroupMigration.verifyStagedCopy(source: source, staged: staged, fileManager: .default)
        }
    }

    @Test("verifyStagedCopy succeeds when sizes match")
    func verifyStagedCopy_matchingSizesSucceeds() throws {
        let root = try makeRoot()
        let source = root.appendingPathComponent("source.sqlite")
        let staged = root.appendingPathComponent("staged.sqlite")
        try Data("identical".utf8).write(to: source)
        try Data("identical".utf8).write(to: staged)
        try MacAppGroupMigration.verifyStagedCopy(source: source, staged: staged, fileManager: .default)
    }

    // MARK: - footprint

    @Test("footprint reports the actual file size")
    func footprint_reportsActualSize() throws {
        let root = try makeRoot()
        let url = root.appendingPathComponent("Lillist.sqlite")
        try Data("twelve bytes!".utf8).write(to: url)
        let footprint = try MacAppGroupMigration.footprint(of: url, fileManager: .default)
        #expect(footprint.sizeBytes == Int64("twelve bytes!".utf8.count))
        #expect(footprint.url == url)
    }
}
