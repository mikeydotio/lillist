import Testing
import Foundation
@testable import LillistCore

@Suite("QuarantineManager")
struct QuarantineManagerTests {
    func makeTempRoot() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Lillist-quarantine-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Quarantine moves the SQLite triplet under the quarantine directory")
    func movesFiles() throws {
        let root = try makeTempRoot()
        let storeURL = root.appendingPathComponent("Lillist.sqlite")
        try Data("main".utf8).write(to: storeURL)
        try Data("wal".utf8).write(to: storeURL.appendingPathExtension("wal"))
        try Data("shm".utf8).write(to: storeURL.appendingPathExtension("shm"))
        let mgr = QuarantineManager(rootDirectory: root, clock: { Date(timeIntervalSince1970: 1_700_000_000) })
        let dest = try mgr.quarantineStore(at: storeURL)
        #expect(FileManager.default.fileExists(atPath: storeURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: dest.path) == true)
        #expect(FileManager.default.fileExists(atPath: dest.appendingPathExtension("wal").path) == true)
        #expect(FileManager.default.fileExists(atPath: dest.appendingPathExtension("shm").path) == true)
    }

    @Test("Quarantine handles missing WAL/SHM gracefully")
    func missingSidecars() throws {
        let root = try makeTempRoot()
        let storeURL = root.appendingPathComponent("Lillist.sqlite")
        try Data("main".utf8).write(to: storeURL)
        let mgr = QuarantineManager(rootDirectory: root, clock: { Date(timeIntervalSince1970: 1_700_000_000) })
        let dest = try mgr.quarantineStore(at: storeURL)
        #expect(FileManager.default.fileExists(atPath: dest.path) == true)
    }

    @Test("Cleanup deletes quarantine subfolders older than 30 days")
    func cleanupOld() throws {
        let root = try makeTempRoot()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let mgr = QuarantineManager(rootDirectory: root, clock: { now })

        // Create one fresh and one expired quarantine folder.
        let fresh = root.appendingPathComponent("Quarantine/fresh", isDirectory: true)
        let expired = root.appendingPathComponent("Quarantine/expired", isDirectory: true)
        try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: expired, withIntermediateDirectories: true)

        let oldDate = now.addingTimeInterval(-31 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: expired.path)

        try mgr.cleanupExpired()
        #expect(FileManager.default.fileExists(atPath: fresh.path) == true)
        #expect(FileManager.default.fileExists(atPath: expired.path) == false)
    }

    @Test("Cleanup leaves folders younger than 30 days intact")
    func cleanupYoung() throws {
        let root = try makeTempRoot()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let mgr = QuarantineManager(rootDirectory: root, clock: { now })
        let young = root.appendingPathComponent("Quarantine/young", isDirectory: true)
        try FileManager.default.createDirectory(at: young, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-15 * 24 * 60 * 60)], ofItemAtPath: young.path)
        try mgr.cleanupExpired()
        #expect(FileManager.default.fileExists(atPath: young.path) == true)
    }

    @Test("Quarantine on a missing store URL throws")
    func missingStore() throws {
        let root = try makeTempRoot()
        let mgr = QuarantineManager(rootDirectory: root, clock: { Date() })
        let bogus = root.appendingPathComponent("nope.sqlite")
        #expect(throws: (any Error).self) {
            _ = try mgr.quarantineStore(at: bogus)
        }
    }

    @Test("copyStore throws insufficientDiskSpace when the probe reports too little headroom")
    func copyStoreRejectsLowDiskSpace() throws {
        let root = try makeTempRoot()
        let storeURL = root.appendingPathComponent("Lillist.sqlite")
        try Data(repeating: 0x01, count: 4096).write(to: storeURL)
        // Footprint stubbed at 4096; require 2x headroom = 8192; only
        // 8191 available -> short by one byte.
        let probe = FakeDiskSpaceProbe(availableBytes: 8191, footprintBytes: 4096)
        let mgr = QuarantineManager(rootDirectory: root, diskSpaceProbe: probe, clock: { Date(timeIntervalSince1970: 1_700_000_000) })
        #expect(throws: LillistError.insufficientDiskSpace(neededBytes: 8192, availableBytes: 8191)) {
            _ = try mgr.copyStore(at: storeURL)
        }
        // The live store must remain in place — the check is pre-flight
        // and copyStore never moves the original.
        #expect(FileManager.default.fileExists(atPath: storeURL.path) == true)
    }

    @Test("copyStore proceeds when the probe reports ample headroom")
    func copyStoreAcceptsAmpleDiskSpace() throws {
        let root = try makeTempRoot()
        let storeURL = root.appendingPathComponent("Lillist.sqlite")
        try Data(repeating: 0x01, count: 4096).write(to: storeURL)
        let probe = FakeDiskSpaceProbe(availableBytes: 1_000_000, footprintBytes: 4096)
        let mgr = QuarantineManager(rootDirectory: root, diskSpaceProbe: probe, clock: { Date(timeIntervalSince1970: 1_700_000_000) })
        let backup = try mgr.copyStore(at: storeURL)
        // Copy, not move: the original stays put and the backup exists.
        #expect(FileManager.default.fileExists(atPath: storeURL.path) == true)
        #expect(FileManager.default.fileExists(atPath: backup.storeURL.path) == true)
    }

    @Test("requiredBytesForQuarantine is twice the live footprint")
    func requiredBytesIsDoubleFootprint() throws {
        let root = try makeTempRoot()
        let storeURL = root.appendingPathComponent("Lillist.sqlite")
        try Data(repeating: 0x01, count: 4096).write(to: storeURL)
        let probe = FakeDiskSpaceProbe(availableBytes: 0, footprintBytes: 4096)
        let mgr = QuarantineManager(rootDirectory: root, diskSpaceProbe: probe, clock: { Date() })
        #expect(try mgr.requiredBytesForQuarantine(of: storeURL) == 8192)
    }
}
