import Foundation
import CloudKit

/// The four iCloud account states `LillistCore` recognizes (design Section 8).
///
/// Note the Swift-unusual `iCloudAccountState` casing: this matches Apple's
/// own `iCloud` brand spelling exactly as requested in the Plan 2 brief.
public enum iCloudAccountState: Sendable, Equatable, Hashable {
    /// User signed in and the account is usable.
    case available
    /// No iCloud account configured on this device.
    case noAccount
    /// Account exists but is restricted (parental controls, MDM, or temporarily unavailable).
    case restricted
    /// The iCloud account changed since the last launch — store must be quarantined.
    case accountChanged

    /// Maps a `CKAccountStatus` to a Lillist account state.
    ///
    /// `.couldNotDetermine` is treated as `.noAccount` because we cannot
    /// safely write CloudKit-bound data when we have no evidence of an
    /// account. `.temporarilyUnavailable` maps to `.restricted` so the UI
    /// surfaces a banner without quarantining the store.
    public static func from(ckAccountStatus: CKAccountStatus) -> iCloudAccountState {
        switch ckAccountStatus {
        case .available:
            return .available
        case .noAccount:
            return .noAccount
        case .restricted:
            return .restricted
        case .couldNotDetermine:
            return .noAccount
        case .temporarilyUnavailable:
            return .restricted
        @unknown default:
            return .noAccount
        }
    }
}
