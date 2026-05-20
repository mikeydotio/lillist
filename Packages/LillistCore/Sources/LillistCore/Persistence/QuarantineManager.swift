import Foundation

/// Moves a Core Data SQLite store and its sidecars into a timestamped
/// quarantine directory and prunes expired entries (design Section 8:
/// "Quarantine preserved 30 days then auto-cleaned").
///
/// Operates purely on the filesystem; never opens Core Data. Designed to
/// be invoked while no `NSPersistentCloudKitContainer` has the store open.
public struct QuarantineManager: Sendable {
    public static let retentionInterval: TimeInterval = 30 * 24 * 60 * 60

    public let rootDirectory: URL
    private let clock: @Sendable () -> Date
    private var fm: FileManager { FileManager.default }

    public init(rootDirectory: URL, clock: @escaping @Sendable () -> Date = Date.init) {
        self.rootDirectory = rootDirectory
        self.clock = clock
    }

    /// Move the SQLite store (and its `-wal` / `-shm` sidecars, if present)
    /// into `<root>/Quarantine/<unix-timestamp>/`. Returns the destination
    /// URL of the main store file.
    @discardableResult
    public func quarantineStore(at storeURL: URL) throws -> URL {
        guard fm.fileExists(atPath: storeURL.path) else {
            throw LillistError.storeUnavailable(reason: "Cannot quarantine: store missing at \(storeURL.path)")
        }
        let timestamp = Int(clock().timeIntervalSince1970)
        let quarantineDir = rootDirectory.appendingPathComponent("Quarantine/\(timestamp)", isDirectory: true)
        try fm.createDirectory(at: quarantineDir, withIntermediateDirectories: true)

        let dest = quarantineDir.appendingPathComponent(storeURL.lastPathComponent)
        try fm.moveItem(at: storeURL, to: dest)

        for ext in ["wal", "shm"] {
            let sidecar = storeURL.appendingPathExtension(ext)
            if fm.fileExists(atPath: sidecar.path) {
                let sidecarDest = dest.appendingPathExtension(ext)
                try fm.moveItem(at: sidecar, to: sidecarDest)
            }
        }
        return dest
    }

    /// Delete every quarantine subfolder whose modification date is older
    /// than `retentionInterval`.
    public func cleanupExpired() throws {
        let quarantineRoot = rootDirectory.appendingPathComponent("Quarantine", isDirectory: true)
        guard fm.fileExists(atPath: quarantineRoot.path) else { return }
        let now = clock()
        let contents = try fm.contentsOfDirectory(at: quarantineRoot, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        for url in contents {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
            if let mod = values.contentModificationDate, now.timeIntervalSince(mod) > Self.retentionInterval {
                try fm.removeItem(at: url)
            }
        }
    }

    // MARK: - Plan 21: restore-from-backup recovery

    /// Plan 21: copy a previously-quarantined store back into place
    /// at `targetURL`. Used by the migration recovery flow when a
    /// destructive sync-mode change crashed mid-flight and the user
    /// asks to revert.
    ///
    /// The caller is responsible for ensuring no
    /// `NSPersistentCloudKitContainer` has the target open; this
    /// helper operates purely on the filesystem.
    ///
    /// - Parameters:
    ///   - quarantinedStore: URL of the main `.sqlite` file inside
    ///     `<root>/Quarantine/<timestamp>/`.
    ///   - targetURL: The live store location to restore *to*.
    /// - Returns: The URL the store was restored to (same as
    ///   `targetURL`).
    @discardableResult
    public func restore(quarantinedStore: URL, to targetURL: URL) throws -> URL {
        guard fm.fileExists(atPath: quarantinedStore.path) else {
            throw LillistError.storeUnavailable(reason: "Quarantine backup missing at \(quarantinedStore.path)")
        }
        // If there's currently a store at the target, move it out of
        // the way (into a fresh quarantine entry) so the restore is
        // recoverable in turn.
        if fm.fileExists(atPath: targetURL.path) {
            try quarantineStore(at: targetURL)
        }
        let parent = targetURL.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        try fm.copyItem(at: quarantinedStore, to: targetURL)
        for ext in ["wal", "shm"] {
            let sidecar = quarantinedStore.appendingPathExtension(ext)
            if fm.fileExists(atPath: sidecar.path) {
                let sidecarDest = targetURL.appendingPathExtension(ext)
                if fm.fileExists(atPath: sidecarDest.path) {
                    try fm.removeItem(at: sidecarDest)
                }
                try fm.copyItem(at: sidecar, to: sidecarDest)
            }
        }
        return targetURL
    }

    /// Locate the most-recently-quarantined backup's main `.sqlite`
    /// file, or `nil` when no quarantine folder exists yet.
    public func latestQuarantinedStore(filename: String = "Lillist.sqlite") throws -> URL? {
        let quarantineRoot = rootDirectory.appendingPathComponent("Quarantine", isDirectory: true)
        guard fm.fileExists(atPath: quarantineRoot.path) else { return nil }
        let contents = try fm.contentsOfDirectory(at: quarantineRoot, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        let sortedByDateDescending = contents.compactMap { url -> (URL, Date)? in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            guard let date = values?.contentModificationDate else { return nil }
            return (url, date)
        }.sorted { $0.1 > $1.1 }
        for (dir, _) in sortedByDateDescending {
            let candidate = dir.appendingPathComponent(filename)
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}
