import Foundation
@preconcurrency import UserNotifications

/// The slice of `UNUserNotificationCenter`'s API the `NotificationScheduler`
/// depends on. Wrapped in a protocol so tests can substitute a recording fake.
///
/// `@preconcurrency` on the `UserNotifications` import lets `UNNotificationRequest`
/// and friends cross actor boundaries without manual `@unchecked Sendable`
/// shims: the protocol's `Sendable` requirement applies to conformers, while
/// arguments inherit pre-Swift-6 relaxed checking.
public protocol UNUserNotificationCenterProtocol: Sendable {
    func add(_ request: UNNotificationRequest) async throws
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) async
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func notificationSettings() async -> UNNotificationSettings
    /// Just the authorization status, without forcing test doubles to mint
    /// a real `UNNotificationSettings` (which isn't constructible outside
    /// the framework). Production uses `notificationSettings().authorizationStatus`.
    func currentAuthorizationStatus() async -> UNAuthorizationStatus
}

/// Production adapter wrapping the real center.
public final class SystemUserNotificationCenter: UNUserNotificationCenterProtocol, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    public func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
    }

    public func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func setNotificationCategories(_ categories: Set<UNNotificationCategory>) async {
        center.setNotificationCategories(categories)
    }

    public func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    public func notificationSettings() async -> UNNotificationSettings {
        await center.notificationSettings()
    }

    public func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }
}
