import Foundation

/// Where the persistent store lives and how it's loaded.
public enum StoreConfiguration: Sendable {
    /// In-memory store backed by `/dev/null`. For tests and previews.
    case inMemory

    /// On-disk SQLite store at the given file URL.
    case onDisk(url: URL)

    /// Default on-disk location: Application Support / Lillist / Lillist.sqlite
    public static var defaultOnDisk: StoreConfiguration {
        get throws {
            let fm = FileManager.default
            let appSupport = try fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dir = appSupport.appendingPathComponent("Lillist", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return .onDisk(url: dir.appendingPathComponent("Lillist.sqlite"))
        }
    }
}
