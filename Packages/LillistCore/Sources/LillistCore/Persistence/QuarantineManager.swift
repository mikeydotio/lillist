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
}
