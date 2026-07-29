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

    /// Cancels every pending OS notification for each id in `taskIDs`,
    /// without requiring the corresponding task row to still exist.
    ///
    /// H3: `reconcile(taskID:)` starts by fetching the task from the store —
    /// correct for every other mutation (soft-delete, restore, status
    /// change), where the row still exists at reconcile time. After a hard
    /// delete or trash purge the row is entirely gone, so `reconcile` would
    /// throw `.notFound` internally and silently no-op (its own top-level
    /// `catch` swallows the error) — a guaranteed-missed cancellation, not a
    /// safe default. `cancelPending` matches purely by
    /// `request.content.userInfo["taskID"]`, never touching the store.
    func cancelPending(forTaskIDs taskIDs: [UUID]) async
}
