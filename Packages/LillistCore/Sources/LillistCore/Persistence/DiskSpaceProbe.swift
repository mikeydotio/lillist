import Foundation

/// Pure, injectable probe for the two filesystem facts the recovery
/// pre-flight needs: how much room a volume has, and how big the live
/// store currently is. A protocol so the disk-full path is testable
/// without actually exhausting a real volume.
///
/// Operates purely on the filesystem; never opens Core Data.
public protocol DiskSpaceProbing: Sendable {
    /// Free bytes the OS reports as available for "important" usage on
    /// the volume that contains `url`. Uses
    /// `volumeAvailableCapacityForImportantUsageKey`, which reflects
    /// space the system would free up (purgeables) for a real write —
    /// the honest figure for a backup copy.
    func availableCapacity(forVolumeContaining url: URL) throws -> Int64

    /// Total on-disk footprint of the SQLite store at `storeURL` plus
    /// its `-wal` / `-shm` sidecars. Returns `0` if the main file is
    /// absent (nothing to back up).
    func footprint(of storeURL: URL) throws -> Int64
}

/// Production implementation backed by `FileManager` / `URLResourceValues`.
public struct FileManagerDiskSpaceProbe: DiskSpaceProbing {
    public init() {}

    public func availableCapacity(forVolumeContaining url: URL) throws -> Int64 {
        // Resolve against the parent directory: `url` may not exist yet
        // (e.g. a target restore location), but its containing volume
        // always does.
        let probeURL = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        let values = try probeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let capacity = values.volumeAvailableCapacityForImportantUsage else {
            throw LillistError.storeUnavailable(reason: "Could not read free space for \(probeURL.path)")
        }
        return capacity
    }

    public func footprint(of storeURL: URL) throws -> Int64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: storeURL.path) else { return 0 }
        var total: Int64 = 0
        for url in [storeURL, storeURL.appendingPathExtension("wal"), storeURL.appendingPathExtension("shm")] {
            guard fm.fileExists(atPath: url.path) else { continue }
            let values = try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            // Prefer allocated size (true on-disk cost); fall back to
            // logical size if the volume doesn't report allocation.
            if let allocated = values.totalFileAllocatedSize {
                total += Int64(allocated)
            } else if let logical = values.fileSize {
                total += Int64(logical)
            }
        }
        return total
    }
}
