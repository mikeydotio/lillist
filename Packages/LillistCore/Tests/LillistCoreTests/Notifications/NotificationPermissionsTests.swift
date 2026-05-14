import Testing
import Foundation
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
}
