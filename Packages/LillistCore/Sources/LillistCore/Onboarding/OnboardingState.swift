import Foundation

/// First-launch state for Lillist.
///
/// Reads and writes the `hasCompletedOnboarding` flag on `AppPreferences`
/// via `PreferencesStore`. The macOS and iOS app shells gate their
/// onboarding sheet/cover on `hasCompletedOnboarding()` at cold start,
/// flip it via `markCompleted()` when the user finishes (or skips) the
/// flow, and never read it again until next launch.
///
/// See design Section 7 ("Onboarding").
public final class OnboardingState: @unchecked Sendable {
    private let preferences: PreferencesStore

    public init(preferences: PreferencesStore) {
        self.preferences = preferences
    }

    /// Whether the user has completed (or skipped past) the one-screen
    /// onboarding flow. Returns `false` on a fresh install.
    public func hasCompletedOnboarding() async throws -> Bool {
        try await preferences.read().hasCompletedOnboarding
    }

    /// Mark onboarding as complete. Idempotent — re-running on an
    /// already-completed flow is a no-op write.
    public func markCompleted() async throws {
        try await preferences.update { $0.hasCompletedOnboarding = true }
    }

    /// Test/debug helper to reset onboarding. Not exposed in UI.
    public func resetForTesting() async throws {
        try await preferences.update { $0.hasCompletedOnboarding = false }
    }
}
