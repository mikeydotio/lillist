import Foundation

/// Copies the pre-Plan-21 device-local fields out of Core Data's
/// `AppPreferences` row into `DevicePreferencesStore` once.
///
/// Before Plan 21 every preference lived in a single CloudKit-mirrored
/// `AppPreferences` row. Plan 21 partitions per-device fields out into
/// `DevicePreferencesStore` (App Group `UserDefaults`) so destructive
/// sync-mode migrations don't accidentally wipe local hotkey
/// configuration, onboarding state, etc.
///
/// The migrator is idempotent — once
/// `DevicePreferencesStore.migrationFromCoreDataCompleted` is `true`,
/// subsequent calls are a single async hop and a flag check.
///
/// The Core Data `AppPreferences` row's device-local fields are
/// intentionally *not* removed from the model. They remain readable
/// (and writable, but only by legacy code paths that have not yet
/// migrated). Eliminating the attributes can wait for a future model
/// version bump; see the engineering notes for the Plan 21 entry.
public struct AppPreferencesPartitionMigrator: Sendable {
    private let preferences: PreferencesStore
    private let devicePreferences: DevicePreferencesStore

    public init(preferences: PreferencesStore, devicePreferences: DevicePreferencesStore) {
        self.preferences = preferences
        self.devicePreferences = devicePreferences
    }

    /// Run the migration if it hasn't been run on this device. Safe to
    /// call on every app launch; subsequent invocations short-circuit
    /// after the marker is set.
    @discardableResult
    public func runIfNeeded() async throws -> Outcome {
        if await devicePreferences.migrationFromCoreDataCompleted {
            return .alreadyMigrated
        }
        let snapshot = try await preferences.read()
        await devicePreferences.setHasCompletedOnboarding(snapshot.hasCompletedOnboarding)
        await devicePreferences.setQuickCaptureEnabled(snapshot.quickCaptureEnabled)
        await devicePreferences.setQuickCaptureHotkey(snapshot.quickCaptureHotkey)
        await devicePreferences.setStatusBarItemVisible(snapshot.statusBarItemVisible)
        await devicePreferences.setCrashPromptsEnabled(snapshot.crashPromptsEnabled)
        await devicePreferences.markMigrationFromCoreDataCompleted()
        return .migrated
    }

    public enum Outcome: Sendable, Equatable {
        case alreadyMigrated
        case migrated
    }
}
