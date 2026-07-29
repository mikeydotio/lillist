import Testing
import Foundation
@testable import LillistCore

/// Wave 3 — daily timestamped zip snapshots (issue #7).
///
/// S23: `createSnapshot`/`createSnapshotIfDue` now zip through a
/// `TaskBackupStore` actor (`via:`) rather than `FileManager` directly —
/// every test here constructs one alongside the manager, mirroring how
/// production wiring (`LocalBackupCoordinator`) always owns both together.
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
    func createsNonEmptyZip() async throws {
        let (pkg, snaps) = makeRoot()
        defer { try? FileManager.default.removeItem(at: pkg.deletingLastPathComponent()) }
        try seedPackage(pkg)
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let mgr = BackupSnapshotManager(packageDirectory: pkg, snapshotsDirectory: snaps, clock: clock.closure)
        let store = TaskBackupStore(packageDirectory: pkg)

        let url = try await mgr.createSnapshot(via: store)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        #expect(size > 0)
        #expect(try mgr.listSnapshots().count == 1)
        #expect(try mgr.isSnapshotDue() == false)
    }

    @Test("due again only after the interval elapses")
    func dueAfterInterval() async throws {
        let (pkg, snaps) = makeRoot()
        defer { try? FileManager.default.removeItem(at: pkg.deletingLastPathComponent()) }
        try seedPackage(pkg)
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let mgr = BackupSnapshotManager(packageDirectory: pkg, snapshotsDirectory: snaps, clock: clock.closure)
        let store = TaskBackupStore(packageDirectory: pkg)
        _ = try await mgr.createSnapshot(via: store)

        clock.advance(by: 23 * 60 * 60)
        #expect(try mgr.isSnapshotDue() == false)
        clock.advance(by: 2 * 60 * 60)  // now 25h
        #expect(try mgr.isSnapshotDue())
        #expect(try await mgr.createSnapshotIfDue(via: store) != nil)
    }

    @Test("retention prunes to retentionCount, keeping the newest")
    func retentionPrunes() async throws {
        let (pkg, snaps) = makeRoot()
        defer { try? FileManager.default.removeItem(at: pkg.deletingLastPathComponent()) }
        try seedPackage(pkg)
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let mgr = BackupSnapshotManager(packageDirectory: pkg, snapshotsDirectory: snaps, clock: clock.closure)
        let store = TaskBackupStore(packageDirectory: pkg)

        let total = BackupSnapshotManager.retentionCount + 3
        var lastURL: URL?
        for _ in 0..<total {
            lastURL = try await mgr.createSnapshot(via: store)
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
    func unzipRoundTrip() async throws {
        let (pkg, snaps) = makeRoot()
        defer { try? FileManager.default.removeItem(at: pkg.deletingLastPathComponent()) }
        try seedPackage(pkg, marker: "round-trip-payload")
        let mgr = BackupSnapshotManager(packageDirectory: pkg, snapshotsDirectory: snaps)
        let store = TaskBackupStore(packageDirectory: pkg)
        let zip = try await mgr.createSnapshot(via: store)

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

    // MARK: - S23: zip runs through the TaskBackupStore actor

    @Test("createSnapshot zips through the SAME TaskBackupStore actor a concurrent write is serialized on (S23)")
    func zipSerializesAgainstConcurrentWrites() async throws {
        // A stress-style proof (matching CLAUDE.md's convention for
        // actor-boundary code): fire many concurrent replaceAll writes
        // and zipPackage calls at the SAME TaskBackupStore actor. Since
        // none of upsert/remove/replaceAll/zipPackage suspend mid-body,
        // actor isolation makes a torn read structurally impossible —
        // every resulting zip must be a valid, openable archive whose
        // task-file count matches SOME real snapshot of the sequence,
        // never a corrupt/partial one.
        let (pkg, snaps) = makeRoot()
        defer { try? FileManager.default.removeItem(at: pkg.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: snaps, withIntermediateDirectories: true)
        let store = TaskBackupStore(packageDirectory: pkg)

        func makeRecords(_ n: Int) -> [BackupPackageSchema.TaskBackupRecord] {
            (0..<n).map { _ in
                let dto = ExportSchema.TaskDTO(
                    id: UUID(), title: "t", notes: "", status: 0,
                    start: nil, startHasTime: false, deadline: nil, deadlineHasTime: false,
                    position: 1, isPinned: false, parentID: nil, tagIDs: [],
                    createdAt: nil, modifiedAt: nil, closedAt: nil, deletedAt: nil,
                    schemaVersion: CloudKitSchema.currentVersion
                )
                return BackupPackageSchema.TaskBackupRecord(
                    backupSchemaVersion: BackupPackageSchema.version,
                    cloudKitSchemaVersion: dto.schemaVersion,
                    task: dto, journalEntries: [], attachments: []
                )
            }
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    try await store.replaceAll(
                        records: makeRecords(5), assets: [],
                        tags: [], series: [], smartFilters: [], preferences: .fallback,
                        cloudKitSchemaVersion: CloudKitSchema.currentVersion, updatedAt: Date()
                    )
                }
                group.addTask {
                    let dest = snaps.appendingPathComponent("stress-\(i)-\(UUID().uuidString).zip")
                    let zipURL = try await store.zipPackage(to: dest)
                    // Every produced zip must be a genuinely valid, openable
                    // archive whose contents unzip cleanly — never a torn
                    // partial write.
                    let unzipDest = snaps.appendingPathComponent("verify-\(i)-\(UUID().uuidString)")
                    try BackupSnapshotManager.unzip(zipURL, to: unzipDest)
                    let tasksDir = unzipDest.appendingPathComponent("tasks")
                    // Every replaceAll writes exactly 5 fresh records
                    // after removing whatever was there — so a genuine
                    // snapshot can only ever be 0 (raced before the
                    // first replaceAll ever completed) or 5 (captured
                    // after some replaceAll's full remove+rewrite). Any
                    // OTHER count (1-4) would mean the zip captured a
                    // directory mid-remove-then-rewrite — a torn read.
                    let files = (try? FileManager.default.contentsOfDirectory(atPath: tasksDir.path)) ?? []
                    #expect(
                        files.count == 0 || files.count == 5,
                        "zip #\(i) captured a torn/partial state: \(files.count) files"
                    )
                }
            }
            try await group.waitForAll()
        }
    }
}
