import Foundation
import UserNotifications

/// Wraps notification authorization. Apps call `requestAuthorization` on
/// first launch; on denial they surface a banner with a Settings deep-link
/// per design Section 4.
public actor NotificationPermissions {
    public enum AuthorizationStatus: Sendable, Equatable {
        case authorized
        case denied
        case notDetermined
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

    /// Snapshot of the current authorization state — does NOT show a
    /// permission prompt. Plan 10's onboarding uses this to distinguish
    /// "first launch, never asked" from "user already chose". Provisional
    /// and ephemeral are both treated as `.authorized` for UI purposes.
    public func currentStatus() async -> AuthorizationStatus {
        let raw = await center.currentAuthorizationStatus()
        switch raw {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }
}
