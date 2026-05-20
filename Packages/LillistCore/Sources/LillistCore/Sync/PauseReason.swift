import Foundation

/// Why iCloud sync is currently paused (Plan 21 status surface).
///
/// The app never blocks when iCloud is unreachable — instead the
/// status indicator flips to "cloud with slash" and tapping it opens
/// `PauseExplainerDialog` keyed on the active reason.
public enum PauseReason: Equatable, Sendable {
    /// No iCloud account is signed in on this device.
    case noAccount
    /// iCloud is restricted (Screen Time / MDM / parental controls).
    case restricted
    /// The signed-in iCloud account changed since the last sync.
    /// `MigrationCoordinator` aborts any active op and surfaces a
    /// dedicated recovery flow.
    case accountChanged
    /// No internet connection. Resumes automatically.
    case noNetwork
    /// iCloud Drive is turned off for Lillist in Settings.
    case iCloudDriveDisabled
    /// Catch-all for unmappable error conditions.
    case unknown
}
