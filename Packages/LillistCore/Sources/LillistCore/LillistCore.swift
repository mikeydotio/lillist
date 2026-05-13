import Foundation

/// `LillistCore` umbrella namespace.
///
/// Plan 1 delivered the local-only Core Data layer. Plan 2 promotes that
/// layer to CloudKit sync via `NSPersistentCloudKitContainer` and adds:
///
/// - `iCloudAccountState` and `AccountStateMonitor`
/// - `SyncStatus` and `SyncStatusMonitor` (driven by `CloudKitEventBridge`)
/// - `QuarantineManager` for account-changed local store handling
/// - `CloudKitSchemaInitializer` for DEBUG-only dev schema bootstrap
/// - `AttachmentStore.downloadData(id:)` for explicit lazy attachment download
public enum LillistCore {
    public static let version = "0.2.0"
}
