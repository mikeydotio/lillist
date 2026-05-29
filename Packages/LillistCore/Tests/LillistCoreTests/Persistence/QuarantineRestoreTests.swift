import Testing
import Foundation
@testable import LillistCore

@Suite("QuarantineManager restore + copy-backup")
struct QuarantineRestoreTests {
    private func makeTempRoot() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Lillist-quarantine-restore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("copyStore leaves the original in place and returns a named backup")
    func copyLeavesOriginal() throws {
        let root = try makeTempRoot()
        let storeURL = root.appendingPathComponent("Lillist.sqlite")
        try Data("main".utf8).write(to: storeURL)
        try Data("wal".utf8).write(to: storeURL.appendingPathExtension("wal"))
        let mgr = QuarantineManager(rootDirectory: root, clock: { Date(timeIntervalSince1970: 1_700_000_000) })

        let backup = try mgr.copyStore(at: storeURL)

        // Original survives (copy, not move).
        #expect(FileManager.default.fileExists(atPath: storeURL.path) == true)
        // Backup folder name is non-empty and the main file copied.
        #expect(backup.folderName.isEmpty == false)
        #expect(FileManager.default.fileExists(atPath: backup.storeURL.path) == true)
        #expect(FileManager.default.fileExists(atPath: backup.storeURL.appendingPathExtension("wal").path) == true)
        // The folder name resolves back to the same store via the
        // by-name lookup.
        let resolved = try mgr.quarantinedStore(folderName: backup.folderName, filename: "Lillist.sqlite")
        #expect(resolved?.path == backup.storeURL.path)
    }

    @Test("restore copies a quarantined store back to the target")
    func restoreRoundTrip() throws {
        let root = try makeTempRoot()
        let storeURL = root.appendingPathComponent("Lillist.sqlite")
        try Data("original".utf8).write(to: storeURL)
        let mgr = QuarantineManager(rootDirectory: root, clock: { Date(timeIntervalSince1970: 1_700_000_000) })
        let backup = try mgr.copyStore(at: storeURL)

        // Wipe the live store, then restore.
        try FileManager.default.removeItem(at: storeURL)
        let restored = try mgr.restore(quarantinedStore: backup.storeURL, to: storeURL)
        #expect(restored.path == storeURL.path)
        #expect(try String(contentsOf: storeURL, encoding: .utf8) == "original")
    }

    @Test("latestQuarantinedStore finds the most recent copy backup")
    func latestFindsCopy() throws {
        let root = try makeTempRoot()
        let storeURL = root.appendingPathComponent("Lillist.sqlite")
        try Data("data".utf8).write(to: storeURL)
        let mgr = QuarantineManager(rootDirectory: root, clock: { Date(timeIntervalSince1970: 1_700_000_000) })
        _ = try mgr.copyStore(at: storeURL)
        let latest = try mgr.latestQuarantinedStore(filename: "Lillist.sqlite")
        #expect(latest != nil)
        #expect(latest?.lastPathComponent == "Lillist.sqlite")
    }
}
