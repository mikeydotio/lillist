import Foundation

/// Where the persistent store lives, how it's loaded, and which iCloud
/// container it mirrors to.
///
/// Plan 1 used a simple enum (`inMemory` / `onDisk(url:)`). Plan 2 wraps the
/// underlying store kind alongside a CloudKit container identifier so a single
/// value carries everything `PersistenceController` needs to call
/// `NSPersistentCloudKitContainer`.
public struct StoreConfiguration: Sendable {
    /// Production CloudKit container identifier (design Section 3).
    public static let defaultCloudKitContainerIdentifier = "iCloud.com.mikeydotio.lillist"

    /// The on-disk vs in-memory choice.
    public enum StoreKind: Sendable {
        case inMemory
        case onDisk(url: URL)
    }

    public var storeKind: StoreKind
    public var cloudKitContainerIdentifier: String

    public init(storeKind: StoreKind, cloudKitContainerIdentifier: String = StoreConfiguration.defaultCloudKitContainerIdentifier) {
        self.storeKind = storeKind
        self.cloudKitContainerIdentifier = cloudKitContainerIdentifier
    }

    /// In-memory store backed by `/dev/null`. For tests and previews.
    public static var inMemory: StoreConfiguration {
        StoreConfiguration(storeKind: .inMemory)
    }

    /// On-disk SQLite store at the given file URL.
    public static func onDisk(url: URL) -> StoreConfiguration {
        StoreConfiguration(storeKind: .onDisk(url: url))
    }

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

    /// On-disk SQLite store inside the App Group's shared container. Use
    /// when the main app and its extensions (Share / App Intents) need to
    /// see the same store. Returns `nil` if the group container is not
    /// reachable (entitlement missing or running outside a signed sandbox).
    public static func appGroupOnDisk(groupID: String) -> StoreConfiguration? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)
        else { return nil }
        let dir = container.appendingPathComponent("Lillist", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return .onDisk(url: dir.appendingPathComponent("Lillist.sqlite"))
    }

    /// Returns a copy with the given CloudKit container identifier substituted in.
    public func withCloudKitContainer(_ identifier: String) -> StoreConfiguration {
        StoreConfiguration(storeKind: storeKind, cloudKitContainerIdentifier: identifier)
    }
}
