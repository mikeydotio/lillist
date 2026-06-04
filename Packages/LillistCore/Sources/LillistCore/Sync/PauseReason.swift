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
    /// The signed-in iCloud account changed since the last sync. The
    /// status badge surfaces this and `PauseExplainerDialog` explains it;
    /// when an account change is detected, `MigrationCoordinator` refuses
    /// the irreversible iCloud zone erase (the `replaceICloudWithLocal`
    /// path) and leaves the journal `.failed` for the recovery sheet,
    /// rather than wiping the wrong account's data.
    case accountChanged
    /// No internet connection. Resumes automatically.
    case noNetwork
    /// iCloud Drive is turned off for Lillist in Settings.
    case iCloudDriveDisabled
    /// Catch-all for unmappable error conditions.
    case unknown
}
