import Testing
import Foundation
@preconcurrency import UserNotifications
@testable import LillistCore

@Suite("NotificationPermissions")
struct NotificationPermissionsTests {
    @Test("requestAuthorization granted returns .authorized")
    func granted() async {
        let fake = FakeUserNotificationCenter()
        await fake.setAuthorizationGranted(true)
        let perms = NotificationPermissions(center: fake)
        let status = await perms.requestAuthorization()
        #expect(status == .authorized)
        #expect(await fake.requestAuthorizationCallCount() == 1)
    }

    @Test("requestAuthorization denied returns .denied")
    func denied() async {
        let fake = FakeUserNotificationCenter()
        await fake.setAuthorizationGranted(false)
        let perms = NotificationPermissions(center: fake)
        let status = await perms.requestAuthorization()
        #expect(status == .denied)
    }

    @Test("currentStatus reports .notDetermined before any prompt")
    func currentStatusFirstLaunch() async {
        let fake = FakeUserNotificationCenter()
        await fake.setCurrentAuthorizationStatus(.notDetermined)
        let perms = NotificationPermissions(center: fake)
        let status = await perms.currentStatus()
        #expect(status == .notDetermined)
        // Asking for the snapshot must NOT trigger a prompt.
        #expect(await fake.requestAuthorizationCallCount() == 0)
    }

    @Test("currentStatus reports .authorized after the user grants")
    func currentStatusAuthorized() async {
        let fake = FakeUserNotificationCenter()
        await fake.setCurrentAuthorizationStatus(.authorized)
        let perms = NotificationPermissions(center: fake)
        #expect(await perms.currentStatus() == .authorized)
    }

    @Test("currentStatus reports .denied after the user refuses")
    func currentStatusDenied() async {
        let fake = FakeUserNotificationCenter()
        await fake.setCurrentAuthorizationStatus(.denied)
        let perms = NotificationPermissions(center: fake)
        #expect(await perms.currentStatus() == .denied)
    }

    @Test("currentStatus folds .provisional into .authorized")
    func currentStatusProvisionalIsAuthorized() async {
        let fake = FakeUserNotificationCenter()
        await fake.setCurrentAuthorizationStatus(.provisional)
        let perms = NotificationPermissions(center: fake)
        #expect(await perms.currentStatus() == .authorized)
        // `.ephemeral` is iOS-only (App Clips); not testable from a
        // shared LillistCore test target, but exercised by the same
        // switch arm at runtime on iOS.
    }
}
