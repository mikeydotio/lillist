import Foundation

/// On-by-default during development; flips OFF in Release (App Store) builds.
///
/// `deployit` archives Debug, so TestFlight/dev builds log by default; only a
/// true Release configuration disables diagnostic logging at ship. This mirrors
/// the existing `#if DEBUG` ship-flip used by `CloudKitSchemaInitializer`
/// (design §1, §8). The toggle in `DevicePreferencesStore` reads this as its
/// unset default, so an explicit user choice always wins.
public enum DiagnosticDefaults {
    public static let enabledByDefault: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()
}
