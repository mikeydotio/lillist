import Testing
import Foundation
@testable import LillistCore

/// Wave 3 — daily timestamped zip snapshots (issue #7).
@Suite("BackupSnapshotManager")
struct BackupSnapshotManagerTests {
    /// A controllable clock so due-logic and filename ordering are deterministic.
    private final class TestClock: @unchecked Sendable {
        private let lock = NSLock()
        private var current: Date
        init(_ start: Date) { current = start }
        var now: Date { lock.lock(); defer { lock.unlock() }; return current }
        func advance(by interval: TimeInterval) { lock.lock(); current += interval; lock.unlock() }
        var closure: @Sendable () -> Date { { [self] in now } }
    }

    private func makeRoot() -> (package: URL, snapshots: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("lillist-snap-\(UUID().uuidString)", isDirectory: true)
        return (root.appendingPathComponent("Package", isDirectory: true),
                root.appendingPathComponent("Snapshots", isDirectory: true))
    }

    /// Write a minimal non-empty package so there is something to zip.
    private func seedPackage(_ dir: URL, marker: String = "hello") throws {
        let tasks = dir.appendingPathComponent("tasks", isDirectory: true)
        try FileManager.default.createDirectory(at: tasks, withIntermediateDirectories: true)
        try Data(marker.utf8).write(to: tasks.appendingPathComponent("\(UUID().uuidString).json"))
    }

    @Test("snapshot is due when none exists")
    func dueWhenEmpty() throws {
        let (pkg, snaps) = makeRoot()
        defer { try? FileManager.default.removeItem(at: pkg.deletingLastPathComponent()) }
        try seedPackage(pkg)
        let mgr = BackupSnapshotManager(packageDirectory: pkg, snapshotsDirectory: snaps)
        #expect(try mgr.isSnapshotDue())
    }

    @Test("createSnapshot produces a non-empty zip and clears the due flag")
    func createsNonEmptyZip() throws {
        let (pkg, snaps) = makeRoot()
        defer { try? FileManager.default.removeItem(at: pkg.deletingLastPathComponent()) }
        try seedPackage(pkg)
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let mgr = BackupSnapshotManager(packageDirectory: pkg, snapshotsDirectory: snaps, clock: clock.closure)

        let url = try mgr.createSnapshot()
        #expect(FileManager.default.fileExists(atPath: url.path))
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        #expect(size > 0)
        #expect(try mgr.listSnapshots().count == 1)
        #expect(try mgr.isSnapshotDue() == false)
    }

    @Test("due again only after the interval elapses")
    func dueAfterInterval() throws {
        let (pkg, snaps) = makeRoot()
        defer { try? FileManager.default.removeItem(at: pkg.deletingLastPathComponent()) }
        try seedPackage(pkg)
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let mgr = BackupSnapshotManager(packageDirectory: pkg, snapshotsDirectory: snaps, clock: clock.closure)
        _ = try mgr.createSnapshot()

        clock.advance(by: 23 * 60 * 60)
        #expect(try mgr.isSnapshotDue() == false)
        clock.advance(by: 2 * 60 * 60)  // now 25h
        #expect(try mgr.isSnapshotDue())
        #expect(try mgr.createSnapshotIfDue() != nil)
    }

    @Test("retention prunes to retentionCount, keeping the newest")
    func retentionPrunes() throws {
        let (pkg, snaps) = makeRoot()
        defer { try? FileManager.default.removeItem(at: pkg.deletingLastPathComponent()) }
        try seedPackage(pkg)
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let mgr = BackupSnapshotManager(packageDirectory: pkg, snapshotsDirectory: snaps, clock: clock.closure)

        let total = BackupSnapshotManager.retentionCount + 3
        var lastURL: URL?
        for _ in 0..<total {
            lastURL = try mgr.createSnapshot()
            clock.advance(by: 24 * 60 * 60)  // distinct daily filename each time
        }

        let kept = try mgr.listSnapshots()
        #expect(kept.count == BackupSnapshotManager.retentionCount)
        // The most recent snapshot survives the prune. Compare by filename:
        // listSnapshots() resolves /var → /private/var, so full URLs differ.
        #expect(kept.first?.url.lastPathComponent == lastURL?.lastPathComponent)
        // Newest-first ordering.
        #expect(kept == kept.sorted { $0.createdAt > $1.createdAt })
    }

    @Test("unzip restores the package contents")
    func unzipRoundTrip() throws {
        let (pkg, snaps) = makeRoot()
        defer { try? FileManager.default.removeItem(at: pkg.deletingLastPathComponent()) }
        try seedPackage(pkg, marker: "round-trip-payload")
        let mgr = BackupSnapshotManager(packageDirectory: pkg, snapshotsDirectory: snaps)
        let zip = try mgr.createSnapshot()

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("lillist-unzip-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dest) }
        try BackupSnapshotManager.unzip(zip, to: dest)

        // The package's tasks/ folder and its file must reappear at the root.
        let tasksDir = dest.appendingPathComponent("tasks")
        let files = try FileManager.default.contentsOfDirectory(atPath: tasksDir.path)
        #expect(files.count == 1)
        let payload = try Data(contentsOf: tasksDir.appendingPathComponent(files[0]))
        #expect(String(data: payload, encoding: .utf8) == "round-trip-payload")
    }

    @Test("snapshot filename round-trips to its timestamp")
    func filenameRoundTrip() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let name = BackupSnapshotManager.snapshotFilename(at: date)
        #expect(name.hasSuffix(".zip"))
        #expect(!name.contains(":"))  // filesystem-safe
        #expect(BackupSnapshotManager.date(fromFilename: name) == date)
    }
}
