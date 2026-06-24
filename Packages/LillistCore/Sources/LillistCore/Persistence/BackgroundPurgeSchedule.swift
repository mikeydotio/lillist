import Foundation

/// Single source of truth for the iOS background trash-purge task.
///
/// The identifier must match the `Info.plist`
/// `BGTaskSchedulerPermittedIdentifiers` entry and the
/// `BGProcessingTaskRequest` the iOS app submits; the interval bounds how
/// soon after the last run the OS may re-dispatch the task. Lives in
/// `LillistCore` so it is host-testable under `swift test` (the
/// `BackgroundTasks` API itself is iOS-only and stays in the app target).
public enum BackgroundPurgeSchedule {
    /// Reverse-DNS task identifier registered with `BGTaskScheduler`.
    public static let taskIdentifier = "app.lillist.autopurge"

    /// Soonest the OS may launch the task after submission (one day).
    public static let earliestBeginInterval: TimeInterval = 24 * 60 * 60
}
