import Foundation

/// Which persistence behavior the user has chosen for this device.
///
/// Plan 21 introduces a user-controlled sync mode so the app stays
/// usable without iCloud. The mode is persisted in App Group
/// `UserDefaults` and consulted by `PersistenceController` when
/// building the store description for the underlying Core Data store.
///
/// The raw values are stable storage literals — they appear in App
/// Group `UserDefaults` and the `MigrationJournal` JSON file. Renaming
/// a case requires a migration; do not change the raw value without
/// also bumping the storage schema.
public enum SyncMode: String, Codable, Sendable, CaseIterable {
    /// Plain Core Data with no CloudKit mirroring. The store stays on
    /// this device; nothing leaves it.
    case localOnly = "localOnly"

    /// `NSPersistentCloudKitContainer` with `cloudKitContainerOptions`
    /// attached, mirroring to the user's private iCloud CloudKit
    /// database.
    case iCloudSync = "iCloudSync"

    /// Default mode for a fresh install on a device with iCloud
    /// available, and the assumed mode when no value is present in
    /// `SyncModeStore` (preserves existing-user behavior on upgrade
    /// from a Plan 20 or earlier build).
    public static let `default`: SyncMode = .iCloudSync
}
