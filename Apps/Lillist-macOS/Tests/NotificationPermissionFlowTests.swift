import XCTest
@preconcurrency import UserNotifications
import LillistCore

/// Plan 10 Task 11. Covers the two onboarding-completion paths against
/// LillistCore directly — the standalone macOS test bundle can't
/// `@testable import Lillist_macOS`, so the test exercises the same
/// sequence the OnboardingSheet's complete() helper runs:
///   1. NotificationPermissions.requestAuthorization() (granted/denied)
///   2. DefaultsInstaller.installIfNeeded()
///   3. OnboardingState.markCompleted()
///
/// `MockNotificationCenter` is a tiny in-file double conforming to
/// `UNUserNotificationCenterProtocol`. We can't reach LillistCore's
/// internal `FakeUserNotificationCenter` from the app test bundle, and
/// re-using one mock across two bundles isn't worth the cross-target
/// re-export.
@MainActor
final class NotificationPermissionFlowTests: XCTestCase {
    func test_grantedPath_completesOnboarding() async throws {
        let env = try await makeEnvironment(grantedOnPrompt: true)

        var done = await env.onboardingState.hasCompletedOnboarding()
        XCTAssertFalse(done)

        let status = await env.notificationPermissions.requestAuthorization()
        XCTAssertEqual(status, .authorized)
        try await env.defaultsInstaller.installIfNeeded()
        await env.onboardingState.markCompleted()

        done = await env.onboardingState.hasCompletedOnboarding()
        XCTAssertTrue(done)
        let filters = try await env.smartFilters.list().map(\.name).sorted()
        XCTAssertEqual(filters, ["No Tags", "Recently Closed", "Stale", "This Week", "Today"])
    }

    func test_deniedPath_stillCompletesOnboarding() async throws {
        let env = try await makeEnvironment(grantedOnPrompt: false)

        let status = await env.notificationPermissions.requestAuthorization()
        XCTAssertEqual(status, .denied)
        try await env.defaultsInstaller.installIfNeeded()
        await env.onboardingState.markCompleted()

        let done = await env.onboardingState.hasCompletedOnboarding()
        XCTAssertTrue(done)
    }

    // MARK: - Test fixture

    private struct TestEnvironment {
        let preferences: PreferencesStore
        let smartFilters: SmartFilterStore
        let onboardingState: OnboardingState
        let defaultsInstaller: DefaultsInstaller
        let notificationPermissions: NotificationPermissions
    }

    private func makeEnvironment(grantedOnPrompt: Bool) async throws -> TestEnvironment {
        let p = try await PersistenceController(configuration: .inMemory)
        let prefs = PreferencesStore(persistence: p)
        let filters = SmartFilterStore(persistence: p)
        // Plan 21: onboarding flag lives in App Group UserDefaults.
        let suite = "NotificationPermissionFlowTests-\(UUID().uuidString)"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        let devicePrefs = DevicePreferencesStore(suiteName: suite)
        let onboarding = OnboardingState(devicePreferences: devicePrefs)
        let installer = DefaultsInstaller(filters: filters)
        let center = MockNotificationCenter(grantedOnPrompt: grantedOnPrompt)
        let perms = NotificationPermissions(center: center)
        return TestEnvironment(
            preferences: prefs,
            smartFilters: filters,
            onboardingState: onboarding,
            defaultsInstaller: installer,
            notificationPermissions: perms
        )
    }
}

/// Lightweight `UNUserNotificationCenterProtocol` double scoped to
/// this test bundle. Implements just enough surface for
/// `NotificationPermissions.requestAuthorization()` and
/// `currentStatus()`.
private final class MockNotificationCenter: UNUserNotificationCenterProtocol, @unchecked Sendable {
    let grantedOnPrompt: Bool
    init(grantedOnPrompt: Bool) { self.grantedOnPrompt = grantedOnPrompt }

    func add(_ request: UNNotificationRequest) async throws {}
    func pendingNotificationRequests() async -> [UNNotificationRequest] { [] }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {}
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) async {}
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        grantedOnPrompt
    }
    func notificationSettings() async -> UNNotificationSettings {
        // Tests in this bundle shouldn't need real UNNotificationSettings; if a
        // test reaches this path, surface it as a test failure rather than
        // crashing the runner. Fall back to the real center so the call still
        // returns a value.
        XCTFail("MockNotificationCenter.notificationSettings() called — tests should not need real UNNotificationSettings")
        return await UNUserNotificationCenter.current().notificationSettings()
    }
    func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        .notDetermined
    }
}
