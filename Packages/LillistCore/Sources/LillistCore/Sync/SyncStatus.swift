import Foundation

/// Snapshot of the current CloudKit sync state, published by
/// `SyncStatusMonitor` and consumed by UI / CLI status indicators
/// (design Sections 3 and 8).
public struct SyncStatus: Sendable, Equatable {
    public var lastSyncedAt: Date?
    public var inProgress: Bool
    public var error: LillistError?

    public init(lastSyncedAt: Date? = nil, inProgress: Bool = false, error: LillistError? = nil) {
        self.lastSyncedAt = lastSyncedAt
        self.inProgress = inProgress
        self.error = error
    }

    /// Convenience for "nothing has happened yet."
    public static let idle = SyncStatus()
}
