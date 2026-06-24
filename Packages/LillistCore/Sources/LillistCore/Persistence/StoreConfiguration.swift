import Foundation

/// Where the persistent store lives, how it's loaded, which iCloud
/// container it mirrors to, and whether iCloud mirroring is active.
///
/// Plan 1 used a simple enum (`inMemory` / `onDisk(url:)`). Plan 2
/// wrapped the store kind alongside a CloudKit container identifier
/// so a single value carried everything `PersistenceController`
/// needed to call `NSPersistentCloudKitContainer`. Plan 21 adds
/// `syncMode`: when `.localOnly`, the on-disk store still uses
/// `NSPersistentCloudKitContainer` (so the runtime type stays stable
/// across mode swaps), but the store description is built *without*
/// `cloudKitContainerOptions`, which keeps the store from mirroring
/// to iCloud.
public struct StoreConfiguration: Sendable {
    /// Production CloudKit container identifier (design Section 3).
    public static let defaultCloudKitContainerIdentifier = "iCloud.io.mikey.lillist"

    /// The on-disk vs in-memory choice.
    public enum StoreKind: Sendable {
        case inMemory
        case onDisk(url: URL)
    }

    public var storeKind: StoreKind
    public var cloudKitContainerIdentifier: String
    /// Plan 21: per-device sync mode. `.iCloudSync` attaches
    /// `cloudKitContainerOptions` to the on-disk store description;
    /// `.localOnly` omits them. Honored only when `storeKind` is
    /// `.onDisk` — in-memory stores never mirror regardless of mode.
    public var syncMode: SyncMode

    public init(
        storeKind: StoreKind,
        cloudKitContainerIdentifier: String = StoreConfiguration.defaultCloudKitContainerIdentifier,
        syncMode: SyncMode = .default
    ) {
        self.storeKind = storeKind
        self.cloudKitContainerIdentifier = cloudKitContainerIdentifier
        self.syncMode = syncMode
    }

    /// In-memory store backed by `/dev/null`. For tests and previews.
    public static var inMemory: StoreConfiguration {
        StoreConfiguration(storeKind: .inMemory)
    }

    /// On-disk SQLite store at the given file URL.
    public static func onDisk(url: URL, syncMode: SyncMode = .default) -> StoreConfiguration {
        StoreConfiguration(storeKind: .onDisk(url: url), syncMode: syncMode)
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
    public static func appGroupOnDisk(
        groupID: String,
        syncMode: SyncMode = .default
    ) -> StoreConfiguration? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)
        else { return nil }
        let dir = container.appendingPathComponent("Lillist", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return .onDisk(url: dir.appendingPathComponent("Lillist.sqlite"), syncMode: syncMode)
    }

    /// Returns a copy with the given CloudKit container identifier substituted in.
    public func withCloudKitContainer(_ identifier: String) -> StoreConfiguration {
        StoreConfiguration(
            storeKind: storeKind,
            cloudKitContainerIdentifier: identifier,
            syncMode: syncMode
        )
    }

    /// Returns a copy with the given sync mode substituted in.
    public func withSyncMode(_ mode: SyncMode) -> StoreConfiguration {
        StoreConfiguration(
            storeKind: storeKind,
            cloudKitContainerIdentifier: cloudKitContainerIdentifier,
            syncMode: mode
        )
    }
}
