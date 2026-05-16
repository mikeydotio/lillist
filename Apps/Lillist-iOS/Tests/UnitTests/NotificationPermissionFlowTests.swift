import XCTest
@preconcurrency import UserNotifications
import LillistCore

/// Plan 10 Task 16. iOS variant of macOS Task 11. Exercises the
/// onboarding-completion sequence against LillistCore directly: the
/// standalone iOS test bundle can't `@testable import Lillist_iOS`,
/// so the test runs against NotificationPermissions, DefaultsInstaller,
/// and OnboardingState.
@MainActor
final class NotificationPermissionFlowTests: XCTestCase {
    func test_grantedPath_installsDefaults() async throws {
        let env = try await makeEnvironment(grantedOnPrompt: true)
        let status = await env.notificationPermissions.requestAuthorization()
        XCTAssertEqual(status, .authorized)
        try await env.defaultsInstaller.installIfNeeded()
        try await env.onboardingState.markCompleted()
        let names = try await env.smartFilters.list().map(\.name).sorted()
        XCTAssertEqual(names, ["No Tags", "Recently Closed", "Stale", "This Week", "Today"])
        let done = try await env.onboardingState.hasCompletedOnboarding()
        XCTAssertTrue(done)
    }

    func test_deniedPath_completesAnyway() async throws {
        let env = try await makeEnvironment(grantedOnPrompt: false)
        let status = await env.notificationPermissions.requestAuthorization()
        XCTAssertEqual(status, .denied)
        try await env.defaultsInstaller.installIfNeeded()
        try await env.onboardingState.markCompleted()
        let done = try await env.onboardingState.hasCompletedOnboarding()
        XCTAssertTrue(done)
    }

    // MARK: - Fixture

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
        let onboarding = OnboardingState(preferences: prefs)
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
