import Foundation

/// Umbrella namespace for the crash-reporting subsystem.
///
/// Implements design Section 8: canary-based crash detection,
/// opt-in redacted reporting, user-mediated `mailto:` delivery.
public enum CrashReporting {
    /// Stable subsystem string used for OSLog and as a sanity marker
    /// in tests. Never change after release.
    public static let subsystemIdentifier = "io.mikeydotio.lillist.crash"
}
