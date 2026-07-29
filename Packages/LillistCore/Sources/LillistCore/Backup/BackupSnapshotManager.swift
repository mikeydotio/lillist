import Foundation
import ZIPFoundation

/// Rolls the live backup package up into timestamped `.zip` snapshots and prunes
/// old ones (issue #7). A durable, point-in-time copy taken daily so a CloudKit
/// wipe (or an accidental package corruption) is recoverable.
///
/// Zipping uses ZIPFoundation (`FileManager.zipItem`) — a real `.zip` the user
/// can open anywhere, and which the restore path unzips back. Snapshots are
/// named with a filesystem-safe ISO-8601 timestamp so they sort chronologically
/// by filename.
public struct BackupSnapshotManager: Sendable {
    /// Minimum age of the newest snapshot before a new one is due.
    public static let snapshotInterval: TimeInterval = 24 * 60 * 60
    /// How many snapshots to keep (count-based, deterministic). Older ones are
    /// pruned newest-first.
    public static let retentionCount = 14

    public let packageDirectory: URL
    public let snapshotsDirectory: URL
    private let clock: @Sendable () -> Date

    public struct SnapshotInfo: Sendable, Equatable {
        public let url: URL
        public let createdAt: Date
        public let byteSize: Int64
        public init(url: URL, createdAt: Date, byteSize: Int64) {
            self.url = url
            self.createdAt = createdAt
            self.byteSize = byteSize
        }
    }

    public init(
        packageDirectory: URL,
        snapshotsDirectory: URL,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.packageDirectory = packageDirectory
        self.snapshotsDirectory = snapshotsDirectory
        self.clock = clock
    }

    /// `true` when there is no snapshot yet, or the newest is at least
    /// `snapshotInterval` old.
    public func isSnapshotDue() throws -> Bool {
        guard let newest = try listSnapshots().first else { return true }
        return clock().timeIntervalSince(newest.createdAt) >= Self.snapshotInterval
    }

    /// Zip `packageDirectory` into `Snapshots/<ISO8601>.zip`, then prune to
    /// `retentionCount`. Returns the new snapshot URL.
    ///
    /// `S23`: the zip runs through `store.zipPackage(to:)` — the
    /// `TaskBackupStore` actor's own zip method — rather than calling
    /// `FileManager.zipItem` directly on `packageDirectory`. Every write
    /// to the package (`upsert`/`remove`/`replaceAll`/etc.) is already
    /// serialized on that actor; routing the read through it too closes
    /// the race where a snapshot captures a directory `replaceAll` is
    /// concurrently tearing down and rewriting (manifest `taskCount` and
    /// the real on-disk record count disagreeing is the symptom this
    /// produces). `store` must be the SAME instance backing the live
    /// package's writes — passing an unrelated `TaskBackupStore` pointed
    /// at the same directory would defeat the actor serialization this
    /// exists for.
    @discardableResult
    public func createSnapshot(via store: TaskBackupStore) async throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: snapshotsDirectory, withIntermediateDirectories: true)
        let destination = snapshotsDirectory.appendingPathComponent(Self.snapshotFilename(at: clock()))
        // `shouldKeepParent: false` puts the package *contents* (tasks/, assets/,
        // sidecars) at the archive root, so unzipping yields a ready-to-read
        // package directory.
        try await store.zipPackage(to: destination, shouldKeepParent: false)
        try pruneToRetention()
        return destination
    }

    /// Create a snapshot only if one is due. Returns the new URL, or `nil` when
    /// nothing was due.
    @discardableResult
    public func createSnapshotIfDue(via store: TaskBackupStore) async throws -> URL? {
        guard try isSnapshotDue() else { return nil }
        return try await createSnapshot(via: store)
    }

    /// Existing snapshots, newest first.
    public func listSnapshots() throws -> [SnapshotInfo] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: snapshotsDirectory.path) else { return [] }
        let urls = try fm.contentsOfDirectory(
            at: snapshotsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ).filter { $0.pathExtension == "zip" }

        let infos = urls.map { url -> SnapshotInfo in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let created = Self.date(fromFilename: url.lastPathComponent)
                ?? values?.contentModificationDate
                ?? Date(timeIntervalSince1970: 0)
            let size = Int64(values?.fileSize ?? 0)
            return SnapshotInfo(url: url, createdAt: created, byteSize: size)
        }
        return infos.sorted { $0.createdAt > $1.createdAt }
    }

    /// Unzip a snapshot into `destination` (used by restore). The destination is
    /// created if absent; entries land at its root (a ready-to-read package).
    public static func unzip(_ zipURL: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        try fm.unzipItem(at: zipURL, to: destination)
    }

    // MARK: - Internals

    private func pruneToRetention() throws {
        let snapshots = try listSnapshots()
        guard snapshots.count > Self.retentionCount else { return }
        for stale in snapshots[Self.retentionCount...] {
            try? FileManager.default.removeItem(at: stale.url)
        }
    }

    /// `2026-06-23T14-30-00Z.zip` — ISO-8601 with the time `:` swapped for `-`
    /// (filesystem-safe) while the date `-` are left intact.
    static func snapshotFilename(at date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        let stamp = formatter.string(from: date)  // 2026-06-23T14:30:00Z
        // Swap only the time colons: split on "T", replace "-" in the time half.
        guard let tIndex = stamp.firstIndex(of: "T") else {
            return "\(stamp.replacingOccurrences(of: ":", with: "-")).zip"
        }
        let datePart = stamp[..<tIndex]
        let timePart = stamp[stamp.index(after: tIndex)...].replacingOccurrences(of: ":", with: "-")
        return "\(datePart)T\(timePart).zip"
    }

    static func date(fromFilename name: String) -> Date? {
        guard name.hasSuffix(".zip") else { return nil }
        let base = String(name.dropLast(4))  // 2026-06-23T14-30-00Z
        guard let tIndex = base.firstIndex(of: "T") else { return nil }
        let datePart = base[..<tIndex]
        let timePart = base[base.index(after: tIndex)...].replacingOccurrences(of: "-", with: ":")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: "\(datePart)T\(timePart)")
    }
}
