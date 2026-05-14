import Testing
import Foundation
@testable import LillistCore

@Suite("CanaryFile")
struct CanaryFileTests {
    /// Synthesize a fresh temp file URL per test so we never touch
    /// real ~/Library state.
    private func makeTempURL() -> URL {
        let tmp = FileManager.default.temporaryDirectory
        return tmp.appendingPathComponent("canary-\(UUID().uuidString).json")
    }

    @Test("writeFresh writes canary JSON to the configured URL")
    func writeFresh_writesFile() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = CanaryFile(url: url)
        let canary = CrashCanary(pid: 7, startedAt: .now, buildVersion: "t", hostname: "h")
        try file.writeFresh(canary)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("readIfPresent returns nil when file does not exist")
    func read_absent_returnsNil() throws {
        let url = makeTempURL()
        let file = CanaryFile(url: url)
        #expect(try file.readIfPresent() == nil)
    }

    @Test("Round trip: write then read returns equal canary")
    func writeThenRead_roundTrip() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = CanaryFile(url: url)
        let canary = CrashCanary(pid: 42, startedAt: Date(timeIntervalSince1970: 100), buildVersion: "v", hostname: "h")
        try file.writeFresh(canary)
        let read = try file.readIfPresent()
        #expect(read == canary)
    }

    @Test("deleteOnCleanExit removes the file")
    func delete_removesFile() throws {
        let url = makeTempURL()
        let file = CanaryFile(url: url)
        try file.writeFresh(CrashCanary(pid: 1, startedAt: .now, buildVersion: "v", hostname: "h"))
        #expect(FileManager.default.fileExists(atPath: url.path))
        try file.deleteOnCleanExit()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("deleteOnCleanExit on missing file is a no-op")
    func delete_missing_isNoop() throws {
        let url = makeTempURL()
        let file = CanaryFile(url: url)
        // No throw expected.
        try file.deleteOnCleanExit()
    }

    @Test("writeFresh creates parent directory if missing")
    func writeFresh_createsParentDirectory() throws {
        let tmp = FileManager.default.temporaryDirectory
        let nested = tmp
            .appendingPathComponent("canary-test-\(UUID().uuidString)")
            .appendingPathComponent("nested")
            .appendingPathComponent("launch.canary")
        defer { try? FileManager.default.removeItem(at: nested.deletingLastPathComponent().deletingLastPathComponent()) }
        let file = CanaryFile(url: nested)
        try file.writeFresh(CrashCanary(pid: 1, startedAt: .now, buildVersion: "v", hostname: "h"))
        #expect(FileManager.default.fileExists(atPath: nested.path))
    }

    @Test("readIfPresent returns nil and discards corrupt file")
    func read_corrupt_returnsNilAndDiscards() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not valid JSON".utf8).write(to: url)
        let file = CanaryFile(url: url)
        #expect(try file.readIfPresent() == nil)
        // Corrupt files are removed so we don't keep trying to read them.
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
