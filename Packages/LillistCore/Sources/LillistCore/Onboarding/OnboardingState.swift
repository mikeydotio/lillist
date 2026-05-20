import Foundation

/// First-launch state for Lillist.
///
/// Reads and writes the `hasCompletedOnboarding` flag via
/// `DevicePreferencesStore` (App Group `UserDefaults`). Prior to Plan
/// 21 this flag lived on Core Data's `AppPreferences` row, where it was
/// vulnerable to destructive sync-mode migrations wiping the local
/// store. The partition migrator copies the legacy value forward on
/// first launch after the partition lands; from that point on the flag
/// is device-local and survives a store reset.
///
/// The macOS and iOS app shells gate their onboarding sheet/cover on
/// `hasCompletedOnboarding()` at cold start, flip it via
/// `markCompleted()` when the user finishes (or skips) the flow, and
/// never read it again until next launch.
///
/// See design Section 7 ("Onboarding").
public final class OnboardingState: @unchecked Sendable {
    private let devicePreferences: DevicePreferencesStore

    public init(devicePreferences: DevicePreferencesStore) {
        self.devicePreferences = devicePreferences
    }

    /// Whether the user has completed (or skipped past) the one-screen
    /// onboarding flow. Returns `false` on a fresh install.
    public func hasCompletedOnboarding() async -> Bool {
        await devicePreferences.hasCompletedOnboarding()
    }

    /// Mark onboarding as complete. Idempotent — re-running on an
    /// already-completed flow is a no-op write.
    public func markCompleted() async {
        await devicePreferences.setHasCompletedOnboarding(true)
    }

    /// Test/debug helper to reset onboarding. Not exposed in UI.
    public func resetForTesting() async {
        await devicePreferences.setHasCompletedOnboarding(false)
    }
}
