import Foundation
import Observation
import LillistCore

/// Sync indicator states per design Section 8 + Plan 21 paused
/// indicator.
public enum SyncIndicator: Sendable, Equatable {
    case idle(lastSync: Date?)
    case inProgress
    case error(message: String, lastSuccess: Date?)
    /// Plan 21: iCloud sync is paused because of a known condition
    /// (`PauseReason`). The badge renders the cloud-with-slash glyph
    /// and the explainer dialog opens on tap. The app keeps working
    /// locally throughout.
    case paused(reason: PauseReason)
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
    /// Connect to the underlying status source and begin reflecting live
    /// state. The app calls this once during `bootstrap()`. Static/stub
    /// monitors (previews, screen-tour tests) get the default no-op.
    func start() async
}

public extension SyncIndicatorMonitor {
    func start() async {}
}

/// Stub used until Plan 2's `LillistCore.SyncStatusMonitor` is bridged into
/// this UI-facing protocol. Always reports `.idle` with a recent timestamp.
@MainActor
@Observable
public final class IdleSyncIndicatorMonitor: SyncIndicatorMonitor {
    public var indicator: SyncIndicator = .idle(lastSync: Date())
    public init() {}
}
