import Foundation
@preconcurrency import UserNotifications

/// Builds the `UNNotificationCategory` set for the app, one per
/// `NotificationKind`, each carrying actions for every action currently
/// registered in the given `SnoozeRegistry`.
public enum NotificationCategoryFactory {
    public static func makeCategories(registry: SnoozeRegistry) async -> Set<UNNotificationCategory> {
        let snoozeActions = await registry.actions
        let unActions: [UNNotificationAction] = snoozeActions.map { snooze in
            UNNotificationAction(
                identifier: snooze.id,
                title: snooze.displayName,
                options: []
            )
        }

        var categories: Set<UNNotificationCategory> = []
        for kind in NotificationKind.allCases {
            let cat = UNNotificationCategory(
                identifier: NotificationCategoryID.categoryID(for: kind),
                actions: unActions,
                intentIdentifiers: [],
                options: []
            )
            categories.insert(cat)
        }

        // Morning summary has no actions (tap to open the app).
        categories.insert(UNNotificationCategory(
            identifier: MorningSummary.categoryID,
            actions: [],
            intentIdentifiers: [],
            options: []
        ))
        return categories
    }
}
