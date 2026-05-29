import Foundation

/// Moves a Core Data SQLite store and its sidecars into a timestamped
/// quarantine directory and prunes expired entries (design Section 8:
/// "Quarantine preserved 30 days then auto-cleaned").
///
/// Operates purely on the filesystem; never opens Core Data. Designed to
/// be invoked while no `NSPersistentCloudKitContainer` has the store open.
public struct QuarantineManager: Sendable {
    public static let retentionInterval: TimeInterval = 30 * 24 * 60 * 60

    /// A quarantine backup created by `copyStore`. Carries the on-disk
    /// folder name so the migration journal can record exactly which
    /// archive to restore (sync-7).
    public struct QuarantinedBackup: Sendable, Equatable {
        /// The leaf folder name under `<root>/Quarantine/`, e.g. the
        /// unix timestamp string.
        public let folderName: String
        /// URL of the main `.sqlite` file inside the backup folder.
        public let storeURL: URL

        public init(folderName: String, storeURL: URL) {
            self.folderName = folderName
            self.storeURL = storeURL
        }
    }

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

    /// Copy the SQLite store (and its `-wal` / `-shm` sidecars, if
    /// present) into `<root>/Quarantine/<unix-timestamp>/`, leaving the
    /// original in place. Used as the pre-swap recovery anchor: the
    /// migration coordinator removes the store from the coordinator
    /// (closing the connection) and then this captures a clean copy
    /// without yanking the live file (persist-3). Returns a named
    /// backup so the journal can record the exact folder (sync-7).
    @discardableResult
    public func copyStore(at storeURL: URL) throws -> QuarantinedBackup {
        guard fm.fileExists(atPath: storeURL.path) else {
            throw LillistError.storeUnavailable(reason: "Cannot quarantine: store missing at \(storeURL.path)")
        }
        let folderName = String(Int(clock().timeIntervalSince1970))
        let quarantineDir = rootDirectory.appendingPathComponent("Quarantine/\(folderName)", isDirectory: true)
        try fm.createDirectory(at: quarantineDir, withIntermediateDirectories: true)

        let dest = quarantineDir.appendingPathComponent(storeURL.lastPathComponent)
        try fm.copyItem(at: storeURL, to: dest)

        for ext in ["wal", "shm"] {
            let sidecar = storeURL.appendingPathExtension(ext)
            if fm.fileExists(atPath: sidecar.path) {
                let sidecarDest = dest.appendingPathExtension(ext)
                try fm.copyItem(at: sidecar, to: sidecarDest)
            }
        }
        return QuarantinedBackup(folderName: folderName, storeURL: dest)
    }

    /// Resolve the main `.sqlite` file for a backup folder recorded by
    /// `copyStore`. Returns `nil` when the folder or file no longer
    /// exists. Recovery uses this to restore the *exact* backup the
    /// journal recorded rather than guessing the latest.
    public func quarantinedStore(folderName: String, filename: String = "Lillist.sqlite") throws -> URL? {
        let candidate = rootDirectory
            .appendingPathComponent("Quarantine/\(folderName)", isDirectory: true)
            .appendingPathComponent(filename)
        return fm.fileExists(atPath: candidate.path) ? candidate : nil
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
