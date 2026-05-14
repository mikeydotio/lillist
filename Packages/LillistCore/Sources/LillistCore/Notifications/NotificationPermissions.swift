import Foundation
import UserNotifications

/// Wraps notification authorization. Apps call `requestAuthorization` on
/// first launch; on denial they surface a banner with a Settings deep-link
/// per design Section 4.
public actor NotificationPermissions {
    public enum AuthorizationStatus: Sendable, Equatable {
        case authorized
        case denied
    }

    private let center: any UNUserNotificationCenterProtocol

    public init(center: any UNUserNotificationCenterProtocol = SystemUserNotificationCenter()) {
        self.center = center
    }

    /// Requests the standard `[.alert, .sound, .badge]` authorization.
    /// Returns `.authorized` if granted, `.denied` otherwise. Errors from
    /// the underlying center are mapped to `.denied` so callers can degrade
    /// gracefully without try/catch.
    public func requestAuthorization() async -> AuthorizationStatus {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted ? .authorized : .denied
        } catch {
            return .denied
        }
    }
}
