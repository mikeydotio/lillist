import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

/// Platform-aware AX announcement posting. iOS 17+ routes to
/// `AccessibilityNotification.Announcement`; macOS routes to
/// `NSAccessibility.post(_:argument:)`. Use `.low` for completion
/// confirmations, `.high` for time-sensitive errors.
public enum AccessibilityAnnouncements {
    public enum Priority: Sendable { case low, high }

    @MainActor
    public static func post(_ message: String, priority: Priority = .low) {
        #if canImport(UIKit)
        AccessibilityNotification.Announcement(AttributedString(message)).post()
        #elseif canImport(AppKit)
        // NSApp is implicitly unwrapped; under unit tests there's no
        // application instance so we no-op safely.
        guard let app = NSApplication.shared as NSApplication? else { return }
        let target: Any = app.mainWindow ?? app.windows.first ?? NSAccessibilityElement()
        let argument: [NSAccessibility.NotificationUserInfoKey: Any] = [
            .announcement: message,
            .priority: priority == .high
                ? NSAccessibilityPriorityLevel.high.rawValue
                : NSAccessibilityPriorityLevel.medium.rawValue
        ]
        NSAccessibility.post(element: target,
                             notification: .announcementRequested,
                             userInfo: argument)
        #endif
    }
}
