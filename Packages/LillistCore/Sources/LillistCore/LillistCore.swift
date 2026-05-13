import Foundation

/// `LillistCoreInfo` umbrella namespace.
///
/// Named `LillistCoreInfo` (not `LillistCore`) so it does not shadow the
/// module name. With the module name freed, callers can write
/// `LillistCore.Predicate` / `LillistCore.Tag` to disambiguate the package's
/// public types from same-named types in `Foundation` or `Testing`.
///
/// Plan 1 delivered the local-only Core Data layer. Plan 2 promotes that
/// layer to CloudKit sync via `NSPersistentCloudKitContainer` and adds:
///
/// - `iCloudAccountState` and `AccountStateMonitor`
/// - `SyncStatus` and `SyncStatusMonitor` (driven by `CloudKitEventBridge`)
/// - `QuarantineManager` for account-changed local store handling
/// - `CloudKitSchemaInitializer` for DEBUG-only dev schema bootstrap
/// - `AttachmentStore.downloadData(id:)` for explicit lazy attachment download
public enum LillistCoreInfo {
    public static let version = "0.2.0"
}
