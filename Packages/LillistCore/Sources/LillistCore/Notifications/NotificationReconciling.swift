import Foundation

/// Abstract "thing that reconciles notifications for a given task." Stores
/// take this protocol (not the concrete `NotificationScheduler`) so they
/// can trigger reconciliation without pulling in `UserNotifications` types
/// or creating a circular dependency.
///
/// The app's composition root constructs a `NotificationScheduler` and
/// assigns it to each store's `notificationScheduler` property. Tests
/// either inject a fake or leave the property `nil` (in which case the
/// reconcile call is a no-op — a deliberate choice so the 100+ existing
/// store tests don't need to be updated to know about notifications).
public protocol NotificationReconciling: Sendable {
    func reconcile(taskID: UUID) async
}
