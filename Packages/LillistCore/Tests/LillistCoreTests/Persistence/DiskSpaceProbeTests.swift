import Testing
import Foundation
@testable import LillistCore

@Suite("DiskSpaceProbe")
struct DiskSpaceProbeTests {
    private func makeTempRoot() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Lillist-diskprobe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Footprint sums the SQLite triplet that exists on disk")
    func footprintSumsTriplet() throws {
        let root = try makeTempRoot()
        let storeURL = root.appendingPathComponent("Lillist.sqlite")
        try Data(repeating: 0xAB, count: 4096).write(to: storeURL)
        try Data(repeating: 0xCD, count: 2048).write(to: storeURL.appendingPathExtension("wal"))
        try Data(repeating: 0xEF, count: 1024).write(to: storeURL.appendingPathExtension("shm"))
        let probe = FileManagerDiskSpaceProbe()
        let footprint = try probe.footprint(of: storeURL)
        // Allocated size rounds up to block boundaries, so assert a
        // lower bound on the logical total rather than an exact figure.
        #expect(footprint >= 4096 + 2048 + 1024)
    }

    @Test("Footprint of a missing store is zero")
    func footprintMissingIsZero() throws {
        let root = try makeTempRoot()
        let probe = FileManagerDiskSpaceProbe()
        #expect(try probe.footprint(of: root.appendingPathComponent("nope.sqlite")) == 0)
    }

    @Test("Available capacity for the temp dir is positive on a real volume")
    func availableIsPositive() throws {
        let root = try makeTempRoot()
        let probe = FileManagerDiskSpaceProbe()
        #expect(try probe.availableCapacity(forVolumeContaining: root) > 0)
    }

    @Test("Fake probe returns its stubbed figures")
    func fakeContract() throws {
        let fake = FakeDiskSpaceProbe(availableBytes: 10, footprintBytes: 7)
        #expect(try fake.availableCapacity(forVolumeContaining: URL(fileURLWithPath: "/")) == 10)
        #expect(try fake.footprint(of: URL(fileURLWithPath: "/anything")) == 7)
    }
}

/// Test double living in the test target so production stays lean.
struct FakeDiskSpaceProbe: DiskSpaceProbing {
    var availableBytes: Int64
    var footprintBytes: Int64
    func availableCapacity(forVolumeContaining url: URL) throws -> Int64 { availableBytes }
    func footprint(of storeURL: URL) throws -> Int64 { footprintBytes }
}
