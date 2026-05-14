import Foundation
import Observation

/// Sync indicator states per design Section 8.
public enum SyncIndicator: Sendable, Equatable {
    case idle(lastSync: Date?)
    case inProgress
    case error(message: String, lastSuccess: Date?)
}

/// Protocol the UI reads from. Plan 2 provides the real CloudKit-backed
/// implementation; until then `IdleSyncStatusMonitor` stands in.
///
/// Named `SyncIndicatorMonitor` (not `SyncStatusMonitor`) to avoid a name
/// collision with `LillistCore.SyncStatusMonitor`, which is a concrete actor
/// shipped by Plan 2. A `CloudKitSyncStatusAdapter` (future) can bridge the
/// Plan-2 actor to this UI-facing protocol.
@MainActor
public protocol SyncIndicatorMonitor: AnyObject {
    var indicator: SyncIndicator { get }
    func retry() async
}

/// Stub used until Plan 2's `LillistCore.SyncStatusMonitor` is bridged into
/// this UI-facing protocol. Always reports `.idle` with a recent timestamp.
@MainActor
@Observable
public final class IdleSyncIndicatorMonitor: SyncIndicatorMonitor {
    public var indicator: SyncIndicator = .idle(lastSync: Date())
    public init() {}
    public func retry() async { /* no-op */ }
}
