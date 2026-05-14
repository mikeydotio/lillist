import Foundation

/// A stable per-device identifier used to disambiguate notification
/// request identifiers across devices (design Section 4 cross-device
/// de-duplication: identifiers are `"\(specID)#\(deviceFingerprint)"`).
///
/// Stored in `UserDefaults` so each device's fingerprint persists across
/// launches. NOT synced via CloudKit — that's the point.
public enum DeviceFingerprint {
    static let userDefaultsKey = "com.mikeydotio.lillist.deviceFingerprint"

    /// Returns the fingerprint, generating and persisting a new one on first call.
    public static func current(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: userDefaultsKey), existing.isEmpty == false {
            return existing
        }
        let fresh = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        defaults.set(fresh, forKey: userDefaultsKey)
        return fresh
    }
}
